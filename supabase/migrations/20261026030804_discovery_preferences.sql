create table app_private.discovery_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  min_age integer not null check(min_age between 18 and 100),
  max_age integer check(max_age between min_age and 99)
);
alter table app_private.discovery_preferences enable row level security;
revoke all on app_private.discovery_preferences from public,anon,authenticated;
create function app_private.discovery_preferences_action(p_save boolean,p_min integer,p_max integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=app_private.actor(); r app_private.discovery_preferences;
begin
  if p_save is null then raise exception 'INVALID_PREFERENCES'; end if;
  if p_save then
    if p_min is null or p_min not between 18 and 100 or (p_max is not null and (p_max<p_min or p_max>99)) then raise exception 'INVALID_PREFERENCES'; end if;
    perform pg_advisory_xact_lock(hashtextextended(me::text,1));
    perform app_private.actor();
    if not exists(select 1 from public.profiles where id=me) then raise exception 'PROFILE_REQUIRED'; end if;
    insert into app_private.discovery_preferences(user_id,min_age,max_age) values(me,p_min,p_max)
      on conflict(user_id) do update set min_age=excluded.min_age,max_age=excluded.max_age;
  end if;
  select * into r from app_private.discovery_preferences where user_id=me;
  return jsonb_build_object('min_age',coalesce(r.min_age,18),'max_age',r.max_age);
end $$;
-- Returns only eligibility for the caller's saved preference, never a birth date.
create function app_private.discovery_age_matches(p_target uuid) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare me uuid:=app_private.actor(); pref app_private.discovery_preferences; years integer;
begin
  if p_target=me or not app_private.account_available(p_target) or app_private.blocked(p_target)
    or not exists(select 1 from public.profiles where id=p_target and discoverable) then return false; end if;
  select * into pref from app_private.discovery_preferences where user_id=me;
  select extract(year from age(current_date,birth_date))::integer into years from public.profile_details where user_id=p_target;
  return coalesce(years>=coalesce(pref.min_age,18) and (pref.max_age is null or years<=pref.max_age),false);
end $$;
create function public.get_discovery_preferences() returns jsonb language sql security invoker set search_path='' as $$
  select app_private.discovery_preferences_action(false,null,null);
$$;
create function public.set_discovery_preferences(p_min integer,p_max integer default null) returns jsonb language sql security invoker set search_path='' as $$
  select app_private.discovery_preferences_action(true,p_min,p_max);
$$;
revoke all on function app_private.discovery_preferences_action(boolean,integer,integer),app_private.discovery_age_matches(uuid),public.get_discovery_preferences(),public.set_discovery_preferences(integer,integer) from public,anon,authenticated;
grant execute on function app_private.discovery_preferences_action(boolean,integer,integer),app_private.discovery_age_matches(uuid),public.get_discovery_preferences(),public.set_discovery_preferences(integer,integer) to authenticated;
create or replace function public.discover_page(p_before_time timestamptz default null,p_before_id uuid default null)
returns setof public.profiles language plpgsql stable security invoker set search_path='' as $$
begin
  perform app_private.actor();
  if (p_before_time is null) <> (p_before_id is null) then raise exception 'INVALID_CURSOR'; end if;
  return query select p.* from public.profiles p
  where p.id<>(select auth.uid()) and p.discoverable and app_private.discovery_age_matches(p.id)
    and (p_before_time is null or (p.created_at,p.id)<(p_before_time,p_before_id))
    and not exists(select 1 from public.likes l where l.sender_id=(select auth.uid()) and l.recipient_id=p.id)
  order by p.created_at desc,p.id desc limit 21;
end $$;
create or replace function public.discover_profiles() returns setof public.profiles
language sql stable security invoker set search_path='' as $$
  select p.* from public.profiles p
  where p.id<>(select auth.uid()) and p.discoverable and app_private.discovery_age_matches(p.id)
    and not exists(select 1 from public.likes l where l.sender_id=(select auth.uid()) and l.recipient_id=p.id)
  order by p.created_at desc,p.id limit 40;
$$;
