-- Serialize rollout with report writes so backfill and trigger cannot miss an insert.
lock table public.reports in share row exclusive mode;
create table app_private.report_events (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index report_events_actor_created on app_private.report_events(actor_id,created_at);
alter table app_private.report_events enable row level security;
revoke all on app_private.report_events from public,anon,authenticated;
-- Deleted historical reports cannot be reconstructed. Preserve surviving recent usage.
insert into app_private.report_events(actor_id,created_at)
  select reporter_id,created_at from public.reports where created_at>now()-interval '1 day';

-- All public report writers already hold the actor's advisory lock (seed 3).
-- AFTER INSERT records only successful inserts, in the report's transaction.
-- No report/target reference: deleting a report must not refund its quota.
create function app_private.record_report_event() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  delete from app_private.report_events where actor_id=new.reporter_id
    and created_at<=now()-interval '1 day';
  insert into app_private.report_events(actor_id,created_at) values(new.reporter_id,new.created_at);
  return new;
end $$;
revoke all on function app_private.record_report_event() from public,anon,authenticated;
create trigger record_report_event after insert on public.reports
for each row execute function app_private.record_report_event();

create or replace function app_private.report_profile(p_target uuid, p_reason text) returns void language plpgsql security definer set search_path = '' as $$
declare me uuid := app_private.actor();
begin
 if p_target=me or p_target is null or not app_private.has_profile() then raise exception 'INVALID_TARGET'; end if;
 perform pg_advisory_xact_lock(hashtextextended(me::text, 3));
 if (select count(*) from app_private.report_events where actor_id=me and created_at > now() - interval '1 day') >= 10 then raise exception 'REPORT_LIMIT'; end if;
 insert into public.reports(reporter_id,reported_id,reason) values(me,p_target,btrim(p_reason));
end $$;

create or replace function app_private.report_message(p_match uuid,p_message bigint,p_reason text) returns uuid
language plpgsql security definer set search_path='' as $$
declare me uuid:=app_private.actor(); m public.matches; msg public.messages; e app_private.report_message_evidence; r public.reports; target uuid;
begin
  if p_match is null or p_message is null or p_message<=0 or p_reason is null
    or char_length(btrim(p_reason)) not between 5 and 1000 or not app_private.has_profile() then raise exception 'INVALID_REPORT'; end if;
  perform pg_advisory_xact_lock(hashtextextended(me::text,3));
  select * into e from app_private.report_message_evidence where reporter_id=me and message_id=p_message;
  if found then
    select * into r from public.reports where id=e.report_id;
    if e.match_id=p_match and r.reason=btrim(p_reason) then return r.id; end if;
    raise exception 'REPORT_CONFLICT';
  end if;
  select * into m from public.matches where id=p_match and me in(user_low,user_high);
  if not found then raise exception 'CHAT_UNAVAILABLE'; end if;
  perform pg_advisory_xact_lock(hashtextextended(m.user_low::text||m.user_high::text,2));
  perform app_private.actor();
  select * into m from public.matches where id=p_match and me in(user_low,user_high) for update;
  if not found then raise exception 'CHAT_UNAVAILABLE'; end if;
  target:=case when me=m.user_low then m.user_high else m.user_low end;
  if not app_private.account_available(target) or app_private.blocked(target) then raise exception 'CHAT_UNAVAILABLE'; end if;
  select * into msg from public.messages where id=p_message and match_id=m.id and sender_id=target for share;
  if not found then raise exception 'MESSAGE_UNAVAILABLE'; end if;
  if (select count(*) from app_private.report_events where actor_id=me and created_at>now()-interval '1 day')>=10 then raise exception 'REPORT_LIMIT'; end if;
  insert into public.reports(reporter_id,reported_id,reason) values(me,target,btrim(p_reason)) returning * into r;
  insert into app_private.report_message_evidence(report_id,reporter_id,message_id,match_id,body,message_created_at)
    values(r.id,me,msg.id,m.id,msg.body,msg.created_at);
  return r.id;
end $$;

create or replace function app_private.prepare_photo_report(p_actor uuid,p_target uuid,p_path text,p_request uuid,p_reason text,p_sha256 text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare e app_private.report_photo_evidence; r public.reports; source_id uuid;
begin
  perform app_private.photo_report_actor(p_actor);
  if p_request is null or p_reason is null or char_length(btrim(p_reason)) not between 5 and 1000
    or p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$' or p_path is null or char_length(p_path)>200 then raise exception 'INVALID_REPORT'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_actor::text,3));
  select * into e from app_private.report_photo_evidence where reporter_id=p_actor and request_id=p_request;
  if found then
    select * into r from public.reports where id=e.report_id;
    if r.reported_id=p_target and r.reason=btrim(p_reason) and e.source_path=p_path and e.sha256=p_sha256
      then return jsonb_build_object('status','completed','report_id',r.id); end if;
    raise exception 'REPORT_CONFLICT';
  end if;
  source_id:=app_private.photo_report_source(p_actor,p_target,p_path);
  if (select count(*) from app_private.report_events where actor_id=p_actor and created_at>now()-interval '1 day')>=10 then raise exception 'REPORT_LIMIT'; end if;
  return jsonb_build_object('status','capture','source_path',p_path,'source_object_id',source_id);
end $$;

