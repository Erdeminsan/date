create table app_private.sanction_appeals (
  id uuid primary key default gen_random_uuid(),
  sanction_id uuid not null unique references app_private.account_sanctions(id) on delete cascade,
  body text not null check(char_length(btrim(body)) between 5 and 2000),
  created_at timestamptz not null default clock_timestamp(),
  decision text check(decision in ('upheld','lifted')),
  response text,
  reviewer_id uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  check((decision is null and response is null and reviewed_at is null) or
    (decision is not null and response is not null and char_length(btrim(response)) between 5 and 1000 and reviewed_at is not null))
);
alter table app_private.sanction_appeals enable row level security;
revoke all on app_private.sanction_appeals from public,anon,authenticated;
create index sanction_appeals_feed on app_private.sanction_appeals(created_at desc,id desc);
create index account_sanctions_owner_feed on app_private.account_sanctions(user_id,created_at desc,id desc);
-- Identity check intentionally permits application-restricted users only for self-service.
create function app_private.appeal_actor() returns uuid
language plpgsql stable security definer set search_path='' as $$
declare me uuid:=auth.uid();
begin
  if me is null or not exists(select 1 from auth.users where id=me and email_confirmed_at is not null
    and not is_anonymous and deleted_at is null and (banned_until is null or banned_until<=now()))
    or exists(select 1 from app_private.account_deletions where user_id=me)
    then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  return me;
end $$;
create function app_private.account_restricted() returns boolean
language plpgsql stable security definer set search_path='' as $$
declare me uuid:=app_private.appeal_actor();
begin
  return exists(select 1 from app_private.account_sanctions where user_id=me and lifted_at is null and expires_at>now());
end $$;
create function app_private.own_sanctions(p_before_time timestamptz,p_before_id uuid)
returns table(id uuid,sanction_id uuid,appeal_id uuid,created_at timestamptz,expires_at timestamptz,active boolean,body text,decision text,response text,display_name text,internal_reason text)
language plpgsql security definer set search_path='' as $$
declare me uuid:=app_private.appeal_actor();
begin
  if (p_before_time is null)<>(p_before_id is null) then raise exception 'INVALID_CURSOR'; end if;
  return query select s.id,s.id,a.id,s.created_at,s.expires_at,s.lifted_at is null and s.expires_at>now(),
    a.body,a.decision,a.response,null::text,null::text
    from app_private.account_sanctions s left join app_private.sanction_appeals a on a.sanction_id=s.id
    where s.user_id=me and (p_before_time is null or (s.created_at,s.id)<(p_before_time,p_before_id))
    order by s.created_at desc,s.id desc limit 21;
end $$;
create function app_private.submit_sanction_appeal(p_sanction uuid,p_body text) returns uuid
language plpgsql security definer set search_path='' as $$
declare me uuid:=app_private.appeal_actor(); s app_private.account_sanctions; a app_private.sanction_appeals;
begin
  if p_body is null or char_length(btrim(p_body)) not between 5 and 2000 then raise exception 'INVALID_APPEAL'; end if;
  select * into s from app_private.account_sanctions where id=p_sanction and user_id=me for update;
  if not found then raise exception 'SANCTION_UNAVAILABLE'; end if;
  perform app_private.appeal_actor();
  select * into a from app_private.sanction_appeals where sanction_id=s.id;
  if found then
    if a.body=btrim(p_body) then return a.id; end if;
    raise exception 'APPEAL_CONFLICT';
  end if;
  insert into app_private.sanction_appeals(sanction_id,body) values(s.id,btrim(p_body)) returning id into a.id;
  return a.id;
end $$;
create function app_private.moderation_appeals(p_reviewed boolean,p_before_time timestamptz,p_before_id uuid)
returns table(id uuid,sanction_id uuid,appeal_id uuid,created_at timestamptz,expires_at timestamptz,active boolean,body text,decision text,response text,display_name text,internal_reason text)
language plpgsql security definer set search_path='' as $$
declare me uuid:=app_private.moderator_actor();
begin
  if p_reviewed is null then raise exception 'INVALID_STATUS'; end if;
  if (p_before_time is null)<>(p_before_id is null) then raise exception 'INVALID_CURSOR'; end if;
  return query select a.id,s.id,a.id,a.created_at,s.expires_at,s.lifted_at is null and s.expires_at>now(),
    a.body,a.decision,a.response,p.display_name,s.reason
    from app_private.sanction_appeals a join app_private.account_sanctions s on s.id=a.sanction_id
    join public.profiles p on p.id=s.user_id
    where me<>s.user_id and (s.reporter_id is null or me<>s.reporter_id)
      and (a.decision is not null)=p_reviewed
      and (p_before_time is null or (a.created_at,a.id)<(p_before_time,p_before_id))
    order by a.created_at desc,a.id desc limit 21;
end $$;
create function app_private.review_sanction_appeal(p_appeal uuid,p_decision text,p_response text) returns void
language plpgsql security definer set search_path='' as $$
declare me uuid:=app_private.moderator_actor(); s app_private.account_sanctions; a app_private.sanction_appeals; sid uuid;
begin
  if p_decision is null or p_decision not in ('upheld','lifted') or p_response is null
    or char_length(btrim(p_response)) not between 5 and 1000 then raise exception 'INVALID_APPEAL_REVIEW'; end if;
  select sanction_id into sid from app_private.sanction_appeals where id=p_appeal;
  -- Match submission/manual lift lock ordering: sanction first, then appeal.
  select * into s from app_private.account_sanctions where id=sid for update;
  if not found or me=s.user_id or me=s.reporter_id then raise exception 'APPEAL_UNAVAILABLE'; end if;
  select * into a from app_private.sanction_appeals where id=p_appeal for update;
  if not found then raise exception 'APPEAL_UNAVAILABLE'; end if;
  perform app_private.actor();
  if a.decision is not null then
    if a.reviewer_id=me and a.decision=p_decision and a.response=btrim(p_response) then return; end if;
    raise exception 'APPEAL_REVIEW_CONFLICT';
  end if;
  if p_decision='lifted' and s.lifted_at is null then
    update app_private.account_sanctions set lifted_at=clock_timestamp(),lifted_by=me,lift_reason='Appeal accepted: '||a.id::text where id=s.id;
  end if;
  update app_private.sanction_appeals set decision=p_decision,response=btrim(p_response),reviewer_id=me,reviewed_at=clock_timestamp() where id=a.id;
end $$;
create function public.account_restricted() returns boolean
language sql security invoker set search_path='' as $$ select app_private.account_restricted(); $$;
create function public.own_sanctions(p_before_time timestamptz default null,p_before_id uuid default null) returns table(id uuid,sanction_id uuid,appeal_id uuid,created_at timestamptz,expires_at timestamptz,active boolean,body text,decision text,response text,display_name text,internal_reason text)
language sql security invoker set search_path='' as $$ select * from app_private.own_sanctions(p_before_time,p_before_id); $$;
create function public.submit_sanction_appeal(p_sanction uuid,p_body text) returns uuid
language sql security invoker set search_path='' as $$ select app_private.submit_sanction_appeal(p_sanction,p_body); $$;
create function public.moderation_appeals(p_reviewed boolean default false,p_before_time timestamptz default null,p_before_id uuid default null) returns table(id uuid,sanction_id uuid,appeal_id uuid,created_at timestamptz,expires_at timestamptz,active boolean,body text,decision text,response text,display_name text,internal_reason text)
language sql security invoker set search_path='' as $$ select * from app_private.moderation_appeals(p_reviewed,p_before_time,p_before_id); $$;
create function public.review_sanction_appeal(p_appeal uuid,p_decision text,p_response text) returns void
language sql security invoker set search_path='' as $$ select app_private.review_sanction_appeal(p_appeal,p_decision,p_response); $$;
revoke all on function app_private.appeal_actor(),app_private.account_restricted(),public.account_restricted(),app_private.own_sanctions(timestamptz,uuid),public.own_sanctions(timestamptz,uuid),app_private.submit_sanction_appeal(uuid,text),public.submit_sanction_appeal(uuid,text),app_private.moderation_appeals(boolean,timestamptz,uuid),public.moderation_appeals(boolean,timestamptz,uuid),app_private.review_sanction_appeal(uuid,text,text),public.review_sanction_appeal(uuid,text,text) from public,anon,authenticated;
grant execute on function app_private.account_restricted(),public.account_restricted(),app_private.own_sanctions(timestamptz,uuid),public.own_sanctions(timestamptz,uuid),app_private.submit_sanction_appeal(uuid,text),public.submit_sanction_appeal(uuid,text),app_private.moderation_appeals(boolean,timestamptz,uuid),public.moderation_appeals(boolean,timestamptz,uuid),app_private.review_sanction_appeal(uuid,text,text),public.review_sanction_appeal(uuid,text,text) to authenticated;
