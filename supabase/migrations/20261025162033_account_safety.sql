-- Abuse accounting survives block/unblock. Contains no target or profile data.
create table app_private.like_events (
  id bigint generated always as identity primary key,
  actor_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index like_events_actor_created_idx on app_private.like_events(actor_id, created_at);
alter table app_private.like_events enable row level security;
revoke all on app_private.like_events from public, anon, authenticated;
revoke all on sequence app_private.like_events_id_seq from public, anon, authenticated;
-- Preserve still-visible recent activity during deployment. Deleted historical
-- likes cannot be reconstructed; full rolling-window accounting starts here.
insert into app_private.like_events(actor_id,created_at)
select sender_id,created_at from public.likes where created_at > now() - interval '1 day';

create function app_private.account_available(p_user uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select app_private.actor() is not null and exists (
    select 1 from auth.users u where u.id=p_user and u.email_confirmed_at is not null
    and not u.is_anonymous and u.deleted_at is null
    and (u.banned_until is null or u.banned_until <= now())
  );
$$;
revoke all on function app_private.account_available(uuid) from public, anon, authenticated;
grant execute on function app_private.account_available(uuid) to authenticated;

alter policy profiles_read on public.profiles using (
  id = (select app_private.actor()) or
  (discoverable and (select app_private.has_profile())
    and app_private.account_available(id) and not app_private.blocked(id))
);
alter policy own_matches on public.matches using (
  ((select app_private.actor()) in (user_low, user_high))
  and app_private.account_available(case when user_low = (select auth.uid()) then user_high else user_low end)
  and not app_private.blocked(case when user_low = (select auth.uid()) then user_high else user_low end)
);

create or replace function app_private.like_profile(p_target uuid) returns uuid language plpgsql security definer set search_path = '' as $$
declare me uuid := app_private.actor(); lo uuid; hi uuid; match_id uuid;
begin
  if p_target is null or me = p_target or not app_private.has_profile() then raise exception 'INVALID_TARGET'; end if;
  perform pg_advisory_xact_lock(hashtextextended(me::text, 4));
  lo := least(me, p_target); hi := greatest(me, p_target);
  -- The same lock is used by blocks: opposing likes cannot miss a mutual match.
  perform pg_advisory_xact_lock(hashtextextended(lo::text || hi::text, 2));
  if not app_private.account_available(p_target) or app_private.blocked(p_target) or not exists(select 1 from public.profiles where id=p_target and discoverable)
    or not exists(select 1 from public.profiles where id=me and discoverable)
    then raise exception 'PROFILE_UNAVAILABLE'; end if;
  if not exists(select 1 from public.likes where sender_id=me and recipient_id=p_target) then
    delete from app_private.like_events where actor_id=me and created_at <= now() - interval '1 day';
    if (select count(*) from app_private.like_events
        where actor_id=me and created_at > now() - interval '1 day') >= 100
      then raise exception 'LIKE_LIMIT'; end if;
    insert into public.likes(sender_id,recipient_id) values(me,p_target);
    insert into app_private.like_events(actor_id) values(me);
  end if;
  if exists(select 1 from public.likes where sender_id=p_target and recipient_id=me) then
    insert into public.matches(user_low,user_high) values(lo,hi) on conflict do nothing;
    select id into match_id from public.matches where user_low=lo and user_high=hi;
  end if;
  return match_id;
end $$;
