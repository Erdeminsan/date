-- Reads accumulated access independently of the latest invitation/room.
create function app_private.match_unlocks(p_match uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=app_private.actor(); m public.matches; other uuid; wins integer; details public.profile_details;
begin
  select * into m from public.matches where id=p_match and me in(user_low,user_high);
  if not found then raise exception 'MATCH_UNAVAILABLE'; end if;
  perform pg_advisory_xact_lock(hashtextextended(m.user_low::text||m.user_high::text,2));
  perform app_private.actor();
  select * into m from public.matches where id=p_match and me in(user_low,user_high) for update;
  if not found then raise exception 'MATCH_UNAVAILABLE'; end if;
  other:=case when me=m.user_low then m.user_high else m.user_low end;
  if not app_private.account_available(m.user_low) or not app_private.account_available(m.user_high)
    or app_private.blocked(other) then raise exception 'MATCH_UNAVAILABLE'; end if;
  select least(count(*),2)::integer into wins from app_private.game_results where match_id=p_match and winner_id=me;
  select * into details from public.profile_details where user_id=other;
  return jsonb_build_object('unlock_level',wins,'city',case when wins>=1 then details.city end,
    'interests',case when wins>=2 then details.interests end);
end $$;
create function public.match_unlocks(p_match uuid) returns jsonb language sql security invoker set search_path='' as $$
  select app_private.match_unlocks(p_match);
$$;
revoke all on function app_private.match_unlocks(uuid),public.match_unlocks(uuid) from public,anon,authenticated;
grant execute on function app_private.match_unlocks(uuid),public.match_unlocks(uuid) to authenticated;
