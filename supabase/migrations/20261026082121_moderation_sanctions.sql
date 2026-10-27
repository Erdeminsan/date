-- Application restrictions do not mutate Supabase-managed auth.users.
create table app_private.account_sanctions (
  id uuid primary key default gen_random_uuid(),
  report_id uuid unique references public.reports(id) on delete set null,
  reporter_id uuid references auth.users(id) on delete set null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  moderator_id uuid references auth.users(id) on delete set null,
  duration_hours integer not null check(duration_hours in (24,168)),
  reason text not null check(char_length(btrim(reason)) between 5 and 1000),
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  lifted_at timestamptz,
  lifted_by uuid references auth.users(id) on delete set null,
  lift_reason text,
  check(expires_at>created_at),
  check((lifted_at is null and lift_reason is null) or
    (lifted_at is not null and char_length(btrim(lift_reason)) between 5 and 1000))
);
alter table app_private.account_sanctions enable row level security;
revoke all on app_private.account_sanctions from public,anon,authenticated;
create index account_sanctions_active on app_private.account_sanctions(user_id,expires_at) where lifted_at is null;
create index account_sanctions_feed on app_private.account_sanctions(created_at desc,id desc);
-- No client grant: trusted service paths can check participants without auth.uid().
create function app_private.account_active(p_user uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from auth.users u where u.id=p_user and u.email_confirmed_at is not null
    and not u.is_anonymous and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now()))
  and not exists(select 1 from app_private.account_deletions where user_id=p_user)
  and not exists(select 1 from app_private.account_sanctions where user_id=p_user and lifted_at is null and expires_at>now());
$$;
revoke all on function app_private.account_active(uuid) from public,anon,authenticated;
create or replace function app_private.actor() returns uuid language plpgsql stable security definer set search_path='' as $$
declare me uuid:=auth.uid();
begin
  if not app_private.account_active(me) then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  return me;
end $$;
create or replace function app_private.account_available(p_user uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select app_private.actor() is not null and app_private.account_active(p_user);
$$;
create function app_private.suspend_reported_account(p_report uuid,p_hours integer,p_reason text) returns uuid
language plpgsql security definer set search_path='' as $$
declare me uuid:=app_private.moderator_actor(); r public.reports; s app_private.account_sanctions; stamp timestamptz;
begin
  if p_hours is null or p_hours not in (24,168) or p_reason is null or char_length(btrim(p_reason)) not between 5 and 1000 then raise exception 'INVALID_SANCTION'; end if;
  select * into r from public.reports where id=p_report for update;
  if not found or me in(r.reporter_id,r.reported_id) then raise exception 'REPORT_UNAVAILABLE'; end if;
  if not exists(select 1 from app_private.report_reviews where report_id=p_report and decision='escalated') then raise exception 'ESCALATED_REVIEW_REQUIRED'; end if;
  -- Serialize target actions and role changes on its auth row. Role FK inserts take key-share.
  perform 1 from auth.users where id=r.reported_id for update;
  if exists(select 1 from app_private.moderators where user_id=r.reported_id) then raise exception 'MODERATOR_TARGET_FORBIDDEN'; end if;
  perform app_private.actor();
  select * into s from app_private.account_sanctions where report_id=p_report;
  if found then
    if s.moderator_id=me and s.duration_hours=p_hours and s.reason=btrim(p_reason) then return s.id; end if;
    raise exception 'SANCTION_CONFLICT';
  end if;
  stamp:=clock_timestamp();
  insert into app_private.account_sanctions(report_id,reporter_id,user_id,moderator_id,duration_hours,reason,created_at,expires_at)
    values(p_report,r.reporter_id,r.reported_id,me,p_hours,btrim(p_reason),stamp,stamp+make_interval(hours=>p_hours)) returning id into s.id;
  return s.id;
end $$;
create function app_private.lift_account_sanction(p_sanction uuid,p_reason text) returns void
language plpgsql security definer set search_path='' as $$
declare me uuid:=app_private.moderator_actor(); s app_private.account_sanctions;
begin
  if p_reason is null or char_length(btrim(p_reason)) not between 5 and 1000 then raise exception 'INVALID_SANCTION'; end if;
  select * into s from app_private.account_sanctions where id=p_sanction for update;
  if not found or me=s.user_id or me=s.reporter_id then raise exception 'SANCTION_UNAVAILABLE'; end if;
  perform app_private.actor();
  if s.lifted_at is not null then
    if s.lifted_by=me and s.lift_reason=btrim(p_reason) then return; end if;
    raise exception 'SANCTION_CONFLICT';
  end if;
  update app_private.account_sanctions set lifted_at=clock_timestamp(),lifted_by=me,lift_reason=btrim(p_reason) where id=s.id;
end $$;
create function app_private.moderation_sanctions(p_before_time timestamptz,p_before_id uuid)
returns table(id uuid,reported_name text,reason text,created_at timestamptz,expires_at timestamptz,lifted_at timestamptz,lift_reason text,active boolean)
language plpgsql security definer set search_path='' as $$
declare me uuid:=app_private.moderator_actor();
begin
  if (p_before_time is null)<>(p_before_id is null) then raise exception 'INVALID_CURSOR'; end if;
  return query select s.id,p.display_name,s.reason,s.created_at,s.expires_at,s.lifted_at,s.lift_reason,s.lifted_at is null and s.expires_at>now()
    from app_private.account_sanctions s join public.profiles p on p.id=s.user_id
    where me<>s.user_id and (s.reporter_id is null or me<>s.reporter_id)
    and (p_before_time is null or (s.created_at,s.id)<(p_before_time,p_before_id))
    order by s.created_at desc,s.id desc limit 21;
end $$;
create function public.suspend_reported_account(p_report uuid,p_hours integer,p_reason text) returns uuid
language sql security invoker set search_path='' as $$ select app_private.suspend_reported_account(p_report,p_hours,p_reason); $$;
create function public.lift_account_sanction(p_sanction uuid,p_reason text) returns void
language sql security invoker set search_path='' as $$ select app_private.lift_account_sanction(p_sanction,p_reason); $$;
create function public.moderation_sanctions(p_before_time timestamptz default null,p_before_id uuid default null)
returns table(id uuid,reported_name text,reason text,created_at timestamptz,expires_at timestamptz,lifted_at timestamptz,lift_reason text,active boolean)
language sql security invoker set search_path='' as $$ select * from app_private.moderation_sanctions(p_before_time,p_before_id); $$;
revoke all on function app_private.suspend_reported_account(uuid,integer,text),app_private.lift_account_sanction(uuid,text),app_private.moderation_sanctions(timestamptz,uuid),public.suspend_reported_account(uuid,integer,text),public.lift_account_sanction(uuid,text),public.moderation_sanctions(timestamptz,uuid) from public,anon,authenticated;
grant execute on function app_private.suspend_reported_account(uuid,integer,text),app_private.lift_account_sanction(uuid,text),app_private.moderation_sanctions(timestamptz,uuid),public.suspend_reported_account(uuid,integer,text),public.lift_account_sanction(uuid,text),public.moderation_sanctions(timestamptz,uuid) to authenticated;

create or replace function app_private.result_match(p_room uuid,p_actor uuid) returns public.matches
language plpgsql security definer set search_path='' as $$
declare m public.matches;
begin
  select x.* into m from public.matches x join public.game_rooms r on r.match_id=x.id
    where r.id=p_room and p_actor in (x.user_low,x.user_high);
  if not found then raise exception 'ROOM_UNAVAILABLE'; end if;
  perform pg_advisory_xact_lock(hashtextextended(m.user_low::text||m.user_high::text,2));
  select * into m from public.matches where id=m.id and p_actor in(user_low,user_high) for update;
  if not found then raise exception 'ROOM_UNAVAILABLE'; end if;
  if not app_private.account_active(m.user_low) or not app_private.account_active(m.user_high)
    or exists(select 1 from public.blocks where (blocker_id=m.user_low and blocked_id=m.user_high) or (blocker_id=m.user_high and blocked_id=m.user_low))
    then raise exception 'ROOM_UNAVAILABLE'; end if;
  return m;
end $$;
