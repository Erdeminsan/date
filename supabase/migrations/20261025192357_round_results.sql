alter table public.game_rooms drop constraint game_rooms_status_check;
alter table public.game_rooms add constraint game_rooms_status_check check(status in ('invited','accepted','countdown','running','awaiting_result','completed','declined','cancelled','expired'));
create table app_private.game_results (
  room_id uuid primary key references public.game_rooms(id) on delete cascade,
  match_id uuid not null references public.matches(id) on delete cascade,
  winner_id uuid references public.profiles(id) on delete cascade,
  low_score integer not null check(low_score between 0 and 28),
  high_score integer not null check(high_score between 0 and 28),
  low_hits integer not null check(low_hits between 0 and 5400),
  high_hits integer not null check(high_hits between 0 and 5400),
  created_at timestamptz not null default clock_timestamp()
);
create index game_results_progress on app_private.game_results(match_id,winner_id);
alter table app_private.game_results enable row level security;
revoke all on app_private.game_results from public,anon,authenticated;

-- All result paths share the same lock order as input, block and unmatch.
create function app_private.result_match(p_room uuid,p_actor uuid) returns public.matches
language plpgsql security definer set search_path='' as $$
declare m public.matches;
begin
  select x.* into m from public.matches x join public.game_rooms r on r.match_id=x.id
    where r.id=p_room and p_actor in (x.user_low,x.user_high);
  if not found then raise exception 'ROOM_UNAVAILABLE'; end if;
  perform pg_advisory_xact_lock(hashtextextended(m.user_low::text||m.user_high::text,2));
  select * into m from public.matches where id=m.id and p_actor in(user_low,user_high) for update;
  if not found then raise exception 'ROOM_UNAVAILABLE'; end if;
  if not app_private.account_available(m.user_low) or not app_private.account_available(m.user_high)
    or exists(select 1 from public.blocks where (blocker_id=m.user_low and blocked_id=m.user_high) or (blocker_id=m.user_high and blocked_id=m.user_low))
    then raise exception 'ROOM_UNAVAILABLE'; end if;
  return m;
end $$;
create function app_private.result_payload(p_room uuid,p_actor uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare m public.matches; r app_private.game_results; wins integer; other uuid; details public.profile_details;
begin
  m:=app_private.result_match(p_room,p_actor);
  select * into r from app_private.game_results where room_id=p_room;
  if not found then return jsonb_build_object('status','pending'); end if;
  select least(count(*),2)::integer into wins from app_private.game_results where match_id=m.id and winner_id=p_actor;
  other:=case when p_actor=m.user_low then m.user_high else m.user_low end;
  select * into details from public.profile_details where user_id=other;
  return jsonb_build_object('status','completed','room_id',p_room,'winner_id',r.winner_id,
    'my_score',case when p_actor=m.user_low then r.low_score else r.high_score end,
    'opponent_score',case when p_actor=m.user_low then r.high_score else r.low_score end,
    'my_hits',case when p_actor=m.user_low then r.low_hits else r.high_hits end,
    'opponent_hits',case when p_actor=m.user_low then r.high_hits else r.low_hits end,
    'unlock_level',wins,'city',case when wins>=1 then details.city end,
    'interests',case when wins>=2 then details.interests end);
end $$;
create function app_private.prepare_game_result(p_room uuid,p_actor uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare m public.matches; r public.game_rooms; stamp timestamptz:=clock_timestamp(); streams jsonb;
begin
  m:=app_private.result_match(p_room,p_actor);
  select * into r from public.game_rooms where id=p_room for update;
  stamp:=clock_timestamp();
  if r.status='completed' then return app_private.result_payload(p_room,p_actor); end if;
  if r.status not in ('countdown','running','awaiting_result') or r.expires_at<=stamp then raise exception 'ROOM_UNAVAILABLE'; end if;
  if r.ends_at>stamp or (select count(*) from app_private.game_input_packets where room_id=p_room)<>90 then
    return jsonb_build_object('status','pending');
  end if;
  update public.game_rooms set status='awaiting_result' where id=p_room;
  select jsonb_agg(jsonb_build_object('roomId',p_room,'playerId',player_id,'packets',packets)) into streams
  from (select player_id,jsonb_agg(jsonb_build_object('sequence',sequence,'fromTick',sequence*120,'throughTick',(sequence+1)*120,
    'flaps',flaps,'receivedAtMs',floor(extract(epoch from received_at)*1000)::bigint) order by sequence) packets
    from app_private.game_input_packets where room_id=p_room group by player_id) s;
  return jsonb_build_object('status','verify','nowMs',floor(extract(epoch from stamp)*1000)::bigint,'streams',streams,
    'room',jsonb_build_object('id',r.id,'players',jsonb_build_array(m.user_low,m.user_high),'status','awaiting_result',
      'seed',r.seed,'engineVersion',r.engine_version,'inputProtocol',r.input_protocol,
      'startsAtMs',floor(extract(epoch from r.starts_at)*1000)::bigint,'endsAtMs',floor(extract(epoch from r.ends_at)*1000)::bigint));
end $$;
create function app_private.finalize_game_result(p_room uuid,p_actor uuid,p_low_score integer,p_high_score integer,p_low_hits integer,p_high_hits integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare m public.matches; r public.game_rooms;
begin
  m:=app_private.result_match(p_room,p_actor);
  select * into r from public.game_rooms where id=p_room for update;
  if r.status='completed' then return app_private.result_payload(p_room,p_actor); end if;
  if r.status<>'awaiting_result' or r.ends_at>clock_timestamp() or r.expires_at<=clock_timestamp()
    or (select count(*) from app_private.game_input_packets where room_id=p_room)<>90 then raise exception 'ROOM_UNAVAILABLE'; end if;
  insert into app_private.game_results(room_id,match_id,winner_id,low_score,high_score,low_hits,high_hits)
    values(p_room,m.id,case when p_low_score=p_high_score then null when p_low_score>p_high_score then m.user_low else m.user_high end,
      p_low_score,p_high_score,p_low_hits,p_high_hits);
  update public.game_rooms set status='completed' where id=p_room;
  -- Progress is derived from this unique result row, in the same transaction.
  return app_private.result_payload(p_room,p_actor);
end $$;
create function app_private.game_result(p_room uuid) returns jsonb
language sql security definer set search_path='' as $$ select app_private.result_payload(p_room,app_private.actor()); $$;
create function public.game_result(p_room uuid) returns jsonb language sql security invoker set search_path='' as $$ select app_private.game_result(p_room); $$;
create function public.prepare_game_result(p_room uuid,p_actor uuid) returns jsonb language sql security invoker set search_path='' as $$ select app_private.prepare_game_result(p_room,p_actor); $$;
create function public.finalize_game_result(p_room uuid,p_actor uuid,p_low_score integer,p_high_score integer,p_low_hits integer,p_high_hits integer) returns jsonb language sql security invoker set search_path='' as $$ select app_private.finalize_game_result(p_room,p_actor,p_low_score,p_high_score,p_low_hits,p_high_hits); $$;
revoke all on function app_private.result_match(uuid,uuid),app_private.result_payload(uuid,uuid),app_private.prepare_game_result(uuid,uuid),app_private.finalize_game_result(uuid,uuid,integer,integer,integer,integer),app_private.game_result(uuid),public.game_result(uuid),public.prepare_game_result(uuid,uuid),public.finalize_game_result(uuid,uuid,integer,integer,integer,integer) from public,anon,authenticated;
grant usage on schema app_private to service_role;
grant execute on function app_private.prepare_game_result(uuid,uuid),app_private.finalize_game_result(uuid,uuid,integer,integer,integer,integer),public.prepare_game_result(uuid,uuid),public.finalize_game_result(uuid,uuid,integer,integer,integer,integer) to service_role;
grant execute on function app_private.game_result(uuid),public.game_result(uuid) to authenticated;
