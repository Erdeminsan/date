-- PlayMatch foundation. Privileged operations live outside exposed schemas.
create schema if not exists app_private;
revoke all on schema app_private from public, anon, authenticated;
grant usage on schema app_private to authenticated;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(btrim(display_name)) between 2 and 30),
  discoverable boolean not null default true,
  created_at timestamptz not null default now()
);
create table public.profile_details (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  birth_date date not null check (birth_date <= (current_date - interval '18 years')::date and birth_date >= date '1900-01-01'),
  city text not null check (char_length(btrim(city)) between 1 and 80),
  interests text not null default '' check (char_length(interests) <= 300)
);
create table public.likes (
  sender_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(sender_id, recipient_id), check(sender_id <> recipient_id)
);
create index likes_recipient_idx on public.likes(recipient_id);
create index likes_sender_created_idx on public.likes(sender_id, created_at);
create table public.matches (
  id uuid primary key default gen_random_uuid(),
  user_low uuid not null references public.profiles(id) on delete cascade,
  user_high uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(user_low, user_high), check(user_low < user_high)
);
create index matches_high_idx on public.matches(user_high);
create table public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(blocker_id, blocked_id), check(blocker_id <> blocked_id)
);
create index blocks_blocked_idx on public.blocks(blocked_id);
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reported_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null check(char_length(btrim(reason)) between 5 and 1000),
  created_at timestamptz not null default now(),
  check(reporter_id <> reported_id)
);
create index reports_reporter_idx on public.reports(reporter_id, created_at);
create index reports_reported_idx on public.reports(reported_id);

alter table public.profiles enable row level security;
alter table public.profile_details enable row level security;
alter table public.likes enable row level security;
alter table public.matches enable row level security;
alter table public.blocks enable row level security;
alter table public.reports enable row level security;
revoke all on public.profiles, public.profile_details, public.likes, public.matches, public.blocks, public.reports from anon, authenticated;
grant select on public.profiles, public.profile_details, public.likes, public.matches, public.blocks, public.reports to authenticated;

create function app_private.actor() returns uuid language plpgsql stable security definer set search_path = '' as $$
declare actor_id uuid := auth.uid();
begin
  if actor_id is null or not exists (
    select 1 from auth.users u where u.id = actor_id and u.email_confirmed_at is not null
    and not u.is_anonymous and u.deleted_at is null and (u.banned_until is null or u.banned_until <= now())
  ) then raise exception 'AUTH_REQUIRED' using errcode = '42501'; end if;
  return actor_id;
end $$;
create function app_private.blocked(other_id uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.blocks b where
    (b.blocker_id = app_private.actor() and b.blocked_id = other_id) or
    (b.blocked_id = app_private.actor() and b.blocker_id = other_id));
$$;
create function app_private.has_profile() returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.profile_details where user_id = app_private.actor());
$$;
create policy profiles_read on public.profiles for select to authenticated using (
  id = (select app_private.actor()) or
  (discoverable and (select app_private.has_profile()) and not app_private.blocked(id))
);
create policy own_details on public.profile_details for select to authenticated using (user_id = (select app_private.actor()));
create policy own_likes on public.likes for select to authenticated using (sender_id = (select app_private.actor()));
create policy own_matches on public.matches for select to authenticated using (
  ((select app_private.actor()) in (user_low, user_high)) and
  not app_private.blocked(case when user_low = (select auth.uid()) then user_high else user_low end)
);
create policy own_blocks on public.blocks for select to authenticated using (blocker_id = (select app_private.actor()));
create policy own_reports on public.reports for select to authenticated using (reporter_id = (select app_private.actor()));

create function app_private.save_profile(p_name text, p_birth_date date, p_city text, p_interests text, p_discoverable boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare me uuid := app_private.actor(); original_birth date;
begin
  -- Serialize updates by the same user, including first creation.
  perform pg_advisory_xact_lock(hashtextextended(me::text, 1));
  select birth_date into original_birth from public.profile_details where user_id = me;
  if original_birth is not null and original_birth <> p_birth_date then raise exception 'BIRTH_DATE_IMMUTABLE'; end if;
  if p_birth_date is null or p_birth_date > (current_date - interval '18 years')::date then raise exception 'ADULTS_ONLY'; end if;
  insert into public.profiles(id, display_name, discoverable) values(me, btrim(p_name), p_discoverable)
  on conflict(id) do update set display_name = excluded.display_name, discoverable = excluded.discoverable;
  insert into public.profile_details(user_id,birth_date,city,interests) values(me,p_birth_date,btrim(p_city),btrim(p_interests))
  on conflict(user_id) do update set city = excluded.city, interests = excluded.interests;
end $$;
create function public.save_profile(p_name text, p_birth_date date, p_city text, p_interests text, p_discoverable boolean default true)
returns void language sql security invoker set search_path = '' as $$
 select app_private.save_profile(p_name,p_birth_date,p_city,p_interests,p_discoverable);
$$;

create function app_private.like_profile(p_target uuid) returns uuid language plpgsql security definer set search_path = '' as $$
declare me uuid := app_private.actor(); lo uuid; hi uuid; match_id uuid;
begin
  if p_target is null or me = p_target or not app_private.has_profile() then raise exception 'INVALID_TARGET'; end if;
  perform pg_advisory_xact_lock(hashtextextended(me::text, 4));
  lo := least(me, p_target); hi := greatest(me, p_target);
  -- The same lock is used by blocks: opposing likes cannot miss a mutual match.
  perform pg_advisory_xact_lock(hashtextextended(lo::text || hi::text, 2));
  if app_private.blocked(p_target) or not exists(select 1 from public.profiles where id=p_target and discoverable)
    or not exists(select 1 from public.profiles where id=me and discoverable)
    then raise exception 'PROFILE_UNAVAILABLE'; end if;
  if not exists(select 1 from public.likes where sender_id=me and recipient_id=p_target) and
    (select count(*) from public.likes where sender_id=me and created_at > now() - interval '1 day') >= 100
    then raise exception 'LIKE_LIMIT'; end if;
  insert into public.likes(sender_id,recipient_id) values(me,p_target) on conflict do nothing;
  if exists(select 1 from public.likes where sender_id=p_target and recipient_id=me) then
    insert into public.matches(user_low,user_high) values(lo,hi) on conflict do nothing;
    select id into match_id from public.matches where user_low=lo and user_high=hi;
  end if;
  return match_id;
end $$;
create function public.like_profile(p_target uuid) returns uuid language sql security invoker set search_path = '' as $$
 select app_private.like_profile(p_target);
$$;
create function app_private.block_profile(p_target uuid) returns void language plpgsql security definer set search_path = '' as $$
declare me uuid := app_private.actor(); lo uuid := least(me,p_target); hi uuid := greatest(me,p_target);
begin
 if p_target is null or p_target=me or not app_private.has_profile() then raise exception 'INVALID_TARGET'; end if;
 perform pg_advisory_xact_lock(hashtextextended(lo::text || hi::text, 2));
 insert into public.blocks(blocker_id,blocked_id) values(me,p_target) on conflict do nothing;
 delete from public.matches where user_low=lo and user_high=hi;
 delete from public.likes where (sender_id=me and recipient_id=p_target) or (sender_id=p_target and recipient_id=me);
end $$;
create function public.block_profile(p_target uuid) returns void language sql security invoker set search_path = '' as $$
 select app_private.block_profile(p_target);
$$;
create function app_private.report_profile(p_target uuid, p_reason text) returns void language plpgsql security definer set search_path = '' as $$
declare me uuid := app_private.actor();
begin
 if p_target=me or p_target is null or not app_private.has_profile() then raise exception 'INVALID_TARGET'; end if;
 perform pg_advisory_xact_lock(hashtextextended(me::text, 3));
 if (select count(*) from public.reports where reporter_id=me and created_at > now() - interval '1 day') >= 10 then raise exception 'REPORT_LIMIT'; end if;
 insert into public.reports(reporter_id,reported_id,reason) values(me,p_target,btrim(p_reason));
end $$;
create function public.report_profile(p_target uuid,p_reason text) returns void language sql security invoker set search_path = '' as $$
 select app_private.report_profile(p_target,p_reason);
$$;

-- Postgres defaults EXECUTE to PUBLIC: remove it explicitly from every entrypoint.
revoke all on all functions in schema app_private from public, anon, authenticated;
grant execute on function app_private.actor(), app_private.blocked(uuid), app_private.has_profile(),
 app_private.save_profile(text,date,text,text,boolean), app_private.like_profile(uuid), app_private.block_profile(uuid), app_private.report_profile(uuid,text) to authenticated;
revoke all on function public.save_profile(text,date,text,text,boolean), public.like_profile(uuid), public.block_profile(uuid), public.report_profile(uuid,text) from public, anon, authenticated;
grant execute on function public.save_profile(text,date,text,text,boolean), public.like_profile(uuid), public.block_profile(uuid), public.report_profile(uuid,text) to authenticated;

-- RLS applies inside this invoker function. Only safe public columns are returned.
create function public.discover_profiles() returns setof public.profiles
language sql stable security invoker set search_path = '' as $$
  select p.* from public.profiles p
  where p.id <> (select auth.uid()) and p.discoverable
    and not exists(select 1 from public.likes l where l.sender_id = (select auth.uid()) and l.recipient_id = p.id)
  order by p.created_at desc, p.id limit 40;
$$;
revoke all on function public.discover_profiles() from public, anon, authenticated;
grant execute on function public.discover_profiles() to authenticated;
