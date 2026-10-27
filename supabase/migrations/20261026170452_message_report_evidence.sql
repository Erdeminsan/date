-- Snapshot lifetime follows the report, not the chat/match.
create table app_private.report_message_evidence (
  report_id uuid primary key references public.reports(id) on delete cascade,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  message_id bigint not null,
  match_id uuid not null,
  body text not null check(char_length(btrim(body)) between 1 and 1000),
  message_created_at timestamptz not null,
  captured_at timestamptz not null default clock_timestamp(),
  unique(reporter_id,message_id)
);
alter table app_private.report_message_evidence enable row level security;
revoke all on app_private.report_message_evidence from public,anon,authenticated;
create function app_private.report_message(p_match uuid,p_message bigint,p_reason text) returns uuid
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
  if (select count(*) from public.reports where reporter_id=me and created_at>now()-interval '1 day')>=10 then raise exception 'REPORT_LIMIT'; end if;
  insert into public.reports(reporter_id,reported_id,reason) values(me,target,btrim(p_reason)) returning * into r;
  insert into app_private.report_message_evidence(report_id,reporter_id,message_id,match_id,body,message_created_at)
    values(r.id,me,msg.id,m.id,msg.body,msg.created_at);
  return r.id;
end $$;
create function public.report_message(p_match uuid,p_message bigint,p_reason text) returns uuid
language sql security invoker set search_path='' as $$ select app_private.report_message(p_match,p_message,p_reason); $$;
revoke all on function app_private.report_message(uuid,bigint,text),public.report_message(uuid,bigint,text) from public,anon,authenticated;
grant execute on function app_private.report_message(uuid,bigint,text),public.report_message(uuid,bigint,text) to authenticated;
create function app_private.moderation_reports_v2(p_status text,p_before_time timestamptz,p_before_id uuid)
returns table(id uuid,reporter_name text,reported_name text,reason text,created_at timestamptz,decision text,review_note text,message_body text,message_created_at timestamptz,evidence_captured_at timestamptz) language plpgsql security definer set search_path='' as $$
begin
  perform app_private.moderator_actor();
  return query select r.*,e.body,e.message_created_at,e.captured_at from app_private.moderation_reports(p_status,p_before_time,p_before_id) r
    left join app_private.report_message_evidence e on e.report_id=r.id order by r.created_at desc,r.id desc;
end $$;
create function public.moderation_reports_v2(p_status text default 'pending',p_before_time timestamptz default null,p_before_id uuid default null)
returns table(id uuid,reporter_name text,reported_name text,reason text,created_at timestamptz,decision text,review_note text,message_body text,message_created_at timestamptz,evidence_captured_at timestamptz) language sql security invoker set search_path='' as $$ select * from app_private.moderation_reports_v2(p_status,p_before_time,p_before_id); $$;
revoke all on function app_private.moderation_reports_v2(text,timestamptz,uuid),public.moderation_reports_v2(text,timestamptz,uuid) from public,anon,authenticated;
grant execute on function app_private.moderation_reports_v2(text,timestamptz,uuid),public.moderation_reports_v2(text,timestamptz,uuid) to authenticated;
create function app_private.moderation_appeals_v3(p_reviewed boolean,p_before_time timestamptz,p_before_id uuid)
returns table(id uuid,sanction_id uuid,appeal_id uuid,created_at timestamptz,expires_at timestamptz,active boolean,body text,decision text,response text,display_name text,internal_reason text,public_notice text,message_body text,message_created_at timestamptz,evidence_captured_at timestamptz) language plpgsql security definer set search_path='' as $$
begin
  perform app_private.moderator_actor();
  return query select a.*,e.body,e.message_created_at,e.captured_at from app_private.moderation_appeals_v2(p_reviewed,p_before_time,p_before_id) a
    join app_private.account_sanctions s on s.id=a.sanction_id
    left join app_private.report_message_evidence e on e.report_id=s.report_id order by a.created_at desc,a.id desc;
end $$;
create function public.moderation_appeals_v3(p_reviewed boolean default false,p_before_time timestamptz default null,p_before_id uuid default null)
returns table(id uuid,sanction_id uuid,appeal_id uuid,created_at timestamptz,expires_at timestamptz,active boolean,body text,decision text,response text,display_name text,internal_reason text,public_notice text,message_body text,message_created_at timestamptz,evidence_captured_at timestamptz) language sql security invoker set search_path='' as $$ select * from app_private.moderation_appeals_v3(p_reviewed,p_before_time,p_before_id); $$;
revoke all on function app_private.moderation_appeals_v3(boolean,timestamptz,uuid),public.moderation_appeals_v3(boolean,timestamptz,uuid) from public,anon,authenticated;
grant execute on function app_private.moderation_appeals_v3(boolean,timestamptz,uuid),public.moderation_appeals_v3(boolean,timestamptz,uuid) to authenticated;
