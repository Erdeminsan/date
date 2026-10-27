-- Historical records remain null: never copy private evidence to user-visible text.
alter table app_private.account_sanctions add column public_notice text
  check(public_notice is null or char_length(btrim(public_notice)) between 5 and 1000);
create function app_private.suspend_reported_account(p_report uuid,p_hours integer,p_reason text,p_public_notice text) returns uuid
language plpgsql security definer set search_path='' as $$
declare me uuid:=app_private.moderator_actor(); r public.reports; s app_private.account_sanctions; stamp timestamptz;
begin
  if p_hours is null or p_hours not in (24,168) or p_reason is null or char_length(btrim(p_reason)) not between 5 and 1000 then raise exception 'INVALID_SANCTION'; end if;
  if p_public_notice is null or char_length(btrim(p_public_notice)) not between 5 and 1000 then raise exception 'PUBLIC_NOTICE_REQUIRED'; end if;
  select * into r from public.reports where id=p_report for update;
  if not found or me in(r.reporter_id,r.reported_id) then raise exception 'REPORT_UNAVAILABLE'; end if;
  if not exists(select 1 from app_private.report_reviews where report_id=p_report and decision='escalated') then raise exception 'ESCALATED_REVIEW_REQUIRED'; end if;
  -- Serialize target actions and role changes on its auth row. Role FK inserts take key-share.
  perform 1 from auth.users where id=r.reported_id for update;
  if exists(select 1 from app_private.moderators where user_id=r.reported_id) then raise exception 'MODERATOR_TARGET_FORBIDDEN'; end if;
  perform app_private.actor();
  select * into s from app_private.account_sanctions where report_id=p_report;
  if found then
    if s.moderator_id=me and s.duration_hours=p_hours and s.reason=btrim(p_reason) and s.public_notice=btrim(p_public_notice) then return s.id; end if;
    raise exception 'SANCTION_CONFLICT';
  end if;
  stamp:=clock_timestamp();
  insert into app_private.account_sanctions(report_id,reporter_id,user_id,moderator_id,duration_hours,reason,public_notice,created_at,expires_at)
    values(p_report,r.reporter_id,r.reported_id,me,p_hours,btrim(p_reason),btrim(p_public_notice),stamp,stamp+make_interval(hours=>p_hours)) returning id into s.id;
  return s.id;
end $$;

create function public.suspend_reported_account(p_report uuid,p_hours integer,p_reason text,p_public_notice text) returns uuid
language sql security invoker set search_path='' as $$ select app_private.suspend_reported_account(p_report,p_hours,p_reason,p_public_notice); $$;
revoke all on function app_private.suspend_reported_account(uuid,integer,text,text),public.suspend_reported_account(uuid,integer,text,text) from public,anon,authenticated;
grant execute on function app_private.suspend_reported_account(uuid,integer,text,text),public.suspend_reported_account(uuid,integer,text,text) to authenticated;
-- Older clients cannot create an unexplained restriction. Do not fall back to internal notes.
create or replace function app_private.suspend_reported_account(p_report uuid,p_hours integer,p_reason text) returns uuid
language plpgsql security definer set search_path='' as $$
begin
  perform app_private.moderator_actor();
  raise exception 'PUBLIC_NOTICE_REQUIRED';
end $$;
create function app_private.own_sanctions_v2(p_before_time timestamptz,p_before_id uuid) returns table(id uuid,sanction_id uuid,appeal_id uuid,created_at timestamptz,expires_at timestamptz,active boolean,body text,decision text,response text,display_name text,internal_reason text,public_notice text)
language plpgsql security definer set search_path='' as $$
begin
  perform app_private.appeal_actor();
  return query select r.*,s.public_notice from app_private.own_sanctions(p_before_time,p_before_id) r
    join app_private.account_sanctions s on s.id=r.sanction_id order by r.created_at desc,r.id desc;
end $$;
create function public.own_sanctions_v2(p_before_time timestamptz default null,p_before_id uuid default null) returns table(id uuid,sanction_id uuid,appeal_id uuid,created_at timestamptz,expires_at timestamptz,active boolean,body text,decision text,response text,display_name text,internal_reason text,public_notice text)
language sql security invoker set search_path='' as $$ select * from app_private.own_sanctions_v2(p_before_time,p_before_id); $$;
revoke all on function app_private.own_sanctions_v2(timestamptz,uuid),public.own_sanctions_v2(timestamptz,uuid) from public,anon,authenticated;
grant execute on function app_private.own_sanctions_v2(timestamptz,uuid),public.own_sanctions_v2(timestamptz,uuid) to authenticated;
create function app_private.moderation_appeals_v2(p_reviewed boolean,p_before_time timestamptz,p_before_id uuid) returns table(id uuid,sanction_id uuid,appeal_id uuid,created_at timestamptz,expires_at timestamptz,active boolean,body text,decision text,response text,display_name text,internal_reason text,public_notice text)
language plpgsql security definer set search_path='' as $$
begin
  perform app_private.moderator_actor();
  return query select r.*,s.public_notice from app_private.moderation_appeals(p_reviewed,p_before_time,p_before_id) r
    join app_private.account_sanctions s on s.id=r.sanction_id order by r.created_at desc,r.id desc;
end $$;
create function public.moderation_appeals_v2(p_reviewed boolean default false,p_before_time timestamptz default null,p_before_id uuid default null) returns table(id uuid,sanction_id uuid,appeal_id uuid,created_at timestamptz,expires_at timestamptz,active boolean,body text,decision text,response text,display_name text,internal_reason text,public_notice text)
language sql security invoker set search_path='' as $$ select * from app_private.moderation_appeals_v2(p_reviewed,p_before_time,p_before_id); $$;
revoke all on function app_private.moderation_appeals_v2(boolean,timestamptz,uuid),public.moderation_appeals_v2(boolean,timestamptz,uuid) from public,anon,authenticated;
grant execute on function app_private.moderation_appeals_v2(boolean,timestamptz,uuid),public.moderation_appeals_v2(boolean,timestamptz,uuid) to authenticated;
create function app_private.moderation_sanctions_v2(p_before_time timestamptz,p_before_id uuid) returns table(id uuid,reported_name text,reason text,created_at timestamptz,expires_at timestamptz,lifted_at timestamptz,lift_reason text,active boolean,public_notice text)
language plpgsql security definer set search_path='' as $$
begin
  perform app_private.moderator_actor();
  return query select r.*,s.public_notice from app_private.moderation_sanctions(p_before_time,p_before_id) r
    join app_private.account_sanctions s on s.id=r.id order by r.created_at desc,r.id desc;
end $$;
create function public.moderation_sanctions_v2(p_before_time timestamptz default null,p_before_id uuid default null) returns table(id uuid,reported_name text,reason text,created_at timestamptz,expires_at timestamptz,lifted_at timestamptz,lift_reason text,active boolean,public_notice text)
language sql security invoker set search_path='' as $$ select * from app_private.moderation_sanctions_v2(p_before_time,p_before_id); $$;
revoke all on function app_private.moderation_sanctions_v2(timestamptz,uuid),public.moderation_sanctions_v2(timestamptz,uuid) from public,anon,authenticated;
grant execute on function app_private.moderation_sanctions_v2(timestamptz,uuid),public.moderation_sanctions_v2(timestamptz,uuid) to authenticated;
