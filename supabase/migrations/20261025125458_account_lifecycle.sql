-- Only a blocker may remove their own block. Opposing blocks are retained.
create function app_private.unblock_profile(p_target uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare me uuid := app_private.actor(); lo uuid := least(me,p_target); hi uuid := greatest(me,p_target);
begin
  if p_target is null or p_target = me then raise exception 'INVALID_TARGET'; end if;
  perform pg_advisory_xact_lock(hashtextextended(lo::text || hi::text, 2));
  delete from public.blocks where blocker_id = me and blocked_id = p_target;
end $$;
create function public.unblock_profile(p_target uuid) returns void
language sql security invoker set search_path = '' as $$
  select app_private.unblock_profile(p_target);
$$;
-- A user may see the display names only for profiles they themselves blocked.
create function app_private.blocked_profiles() returns table(id uuid, display_name text)
language sql stable security definer set search_path = '' as $$
  select p.id, p.display_name from public.blocks b
  join public.profiles p on p.id = b.blocked_id
  where b.blocker_id = app_private.actor() order by b.created_at desc;
$$;
create function public.blocked_profiles() returns table(id uuid, display_name text)
language sql stable security invoker set search_path = '' as $$
  select * from app_private.blocked_profiles();
$$;
revoke all on function app_private.unblock_profile(uuid), app_private.blocked_profiles(), public.unblock_profile(uuid), public.blocked_profiles() from public, anon, authenticated;
grant execute on function app_private.unblock_profile(uuid), app_private.blocked_profiles(), public.unblock_profile(uuid), public.blocked_profiles() to authenticated;
