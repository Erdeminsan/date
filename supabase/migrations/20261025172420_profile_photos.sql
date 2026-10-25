alter table public.profiles add column photo_path text;
create table app_private.account_deletions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  token uuid not null,
  started_at timestamptz not null default now()
);
alter table app_private.account_deletions enable row level security;
revoke all on app_private.account_deletions from public,anon,authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('profile-photos','profile-photos',false,2097152,array['image/jpeg']);

-- Deletion, profile saves and photo writes share the user advisory lock.
-- The private lease also protects accounts without a profile yet.
create function app_private.photo_write_allowed(p_name text, p_deleting boolean default false)
returns boolean language plpgsql security definer set search_path='' as $$
declare me uuid := app_private.actor(); current_path text;
begin
  perform pg_advisory_xact_lock(hashtextextended(me::text,1));
  perform app_private.actor();
  select photo_path into current_path from public.profiles where id=me for update;
  if not found then return false; end if;
  if p_name is null or p_name !~ ('^' || me::text || '/[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.jpg$') then return false; end if;
  if p_deleting then return current_path is distinct from p_name; end if;
  return (select count(*) from storage.objects where bucket_id='profile-photos' and split_part(name,'/',1)=me::text) < 3;
end $$;
revoke all on function app_private.photo_write_allowed(text,boolean) from public,anon,authenticated;
grant execute on function app_private.photo_write_allowed(text,boolean) to authenticated;

create policy photo_read on storage.objects for select to authenticated using (
  bucket_id='profile-photos' and (
    split_part(name,'/',1)=(select app_private.actor())::text or
    exists(select 1 from public.profiles p where p.photo_path=storage.objects.name)
  )
);
create policy photo_insert on storage.objects for insert to authenticated with check (
  bucket_id='profile-photos' and app_private.photo_write_allowed(name,false)
);
create policy photo_delete on storage.objects for delete to authenticated using (
  bucket_id='profile-photos' and app_private.photo_write_allowed(name,true)
);
-- No update/upsert policy: object names are unique and never reused.
create function app_private.set_profile_photo(p_path text) returns text
language plpgsql security definer set search_path='' as $$
declare me uuid:=app_private.actor(); previous text;
begin
  perform pg_advisory_xact_lock(hashtextextended(me::text,1));
  perform app_private.actor();
  select photo_path into previous from public.profiles where id=me for update;
  if not found then raise exception 'PROFILE_UNAVAILABLE'; end if;
  if p_path is not null then
    if split_part(p_path,'/',1) <> me::text or not exists(
      select 1 from storage.objects where bucket_id='profile-photos' and name=p_path
    ) then raise exception 'PHOTO_UNAVAILABLE'; end if;
  end if;
  update public.profiles set photo_path=p_path where id=me;
  return previous;
end $$;
create function public.set_profile_photo(p_path text) returns text
language sql security invoker set search_path='' as $$ select app_private.set_profile_photo(p_path); $$;
revoke all on function app_private.set_profile_photo(text),public.set_profile_photo(text) from public,anon,authenticated;
grant execute on function app_private.set_profile_photo(text),public.set_profile_photo(text) to authenticated;

-- While deletion is pending, old access JWTs must not permit app activity.
create or replace function app_private.actor() returns uuid language plpgsql stable security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();
begin
  if actor_id is null or not exists(
    select 1 from auth.users u where u.id=actor_id and u.email_confirmed_at is not null
      and not u.is_anonymous and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now())
  ) or exists(select 1 from app_private.account_deletions where user_id=actor_id)
  then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  return actor_id;
end $$;
create or replace function app_private.account_available(p_user uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select app_private.actor() is not null and exists(
    select 1 from auth.users u where u.id=p_user and u.email_confirmed_at is not null
      and not u.is_anonymous and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now())
  ) and not exists(select 1 from app_private.account_deletions where user_id=p_user);
$$;

create function app_private.begin_account_deletion(p_user uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare started timestamptz; lease uuid:=gen_random_uuid();
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user::text,1));
  select started_at into started from app_private.account_deletions where user_id=p_user;
  if started > now()-interval '10 minutes' then raise exception 'DELETE_IN_PROGRESS'; end if;
  insert into app_private.account_deletions(user_id,token) values(p_user,lease)
  on conflict(user_id) do update set token=excluded.token,started_at=now();
  return lease;
end $$;
create function app_private.abort_account_deletion(p_user uuid,p_token uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user::text,1));
  delete from app_private.account_deletions where user_id=p_user and token=p_token;
end $$;
create function public.begin_account_deletion(p_user uuid) returns uuid language sql security invoker set search_path='' as $$
  select app_private.begin_account_deletion(p_user);
$$;
create function public.abort_account_deletion(p_user uuid,p_token uuid) returns void language sql security invoker set search_path='' as $$
  select app_private.abort_account_deletion(p_user,p_token);
$$;
revoke all on function app_private.begin_account_deletion(uuid),app_private.abort_account_deletion(uuid,uuid),
 public.begin_account_deletion(uuid),public.abort_account_deletion(uuid,uuid) from public,anon,authenticated;
grant usage on schema app_private to service_role;
grant execute on function app_private.begin_account_deletion(uuid),app_private.abort_account_deletion(uuid,uuid),
 public.begin_account_deletion(uuid),public.abort_account_deletion(uuid,uuid) to service_role;

create function public.matches_page_v2(p_before_time timestamptz default null, p_before_id uuid default null)
returns table(id uuid, other_id uuid, display_name text, created_at timestamptz, photo_path text)
language plpgsql stable security invoker set search_path = '' as $$
begin
  perform app_private.actor();
  if (p_before_time is null) <> (p_before_id is null) then raise exception 'INVALID_CURSOR'; end if;
  return query
  select m.id, case when m.user_low=(select auth.uid()) then m.user_high else m.user_low end,
    coalesce(p.display_name,'Gizli profil'),m.created_at,p.photo_path
  from public.matches m
  left join public.profiles p on p.id=case when m.user_low=(select auth.uid()) then m.user_high else m.user_low end
  where (select auth.uid()) in (m.user_low,m.user_high)
    and (p_before_time is null or (m.created_at,m.id) < (p_before_time,p_before_id))
  order by m.created_at desc,m.id desc limit 21;
end $$;
revoke all on function public.matches_page_v2(timestamptz,uuid) from public,anon,authenticated;
grant execute on function public.matches_page_v2(timestamptz,uuid) to authenticated;

create or replace function app_private.save_profile(p_name text, p_birth_date date, p_city text, p_interests text, p_discoverable boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare me uuid := app_private.actor(); original_birth date;
begin
  -- Serialize updates by the same user, including first creation.
  perform pg_advisory_xact_lock(hashtextextended(me::text, 1));
  perform app_private.actor(); -- Recheck after waiting behind a deletion request.
  select birth_date into original_birth from public.profile_details where user_id = me;
  if original_birth is not null and original_birth <> p_birth_date then raise exception 'BIRTH_DATE_IMMUTABLE'; end if;
  if p_birth_date is null or p_birth_date > (current_date - interval '18 years')::date then raise exception 'ADULTS_ONLY'; end if;
  insert into public.profiles(id, display_name, discoverable) values(me, btrim(p_name), p_discoverable)
  on conflict(id) do update set display_name = excluded.display_name, discoverable = excluded.discoverable;
  insert into public.profile_details(user_id,birth_date,city,interests) values(me,p_birth_date,btrim(p_city),btrim(p_interests))
  on conflict(user_id) do update set city = excluded.city, interests = excluded.interests;
end $$;
