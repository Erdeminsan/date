alter table public.game_rooms add column input_protocol text not null default 'sky-hop-input-v1';
create table app_private.game_input_packets (
  room_id uuid not null references public.game_rooms(id) on delete cascade,
  player_id uuid not null references public.profiles(id) on delete cascade,
  sequence integer not null check(sequence between 0 and 44),
  flaps integer[] not null check(cardinality(flaps)<=120),
  received_at timestamptz not null,
  primary key(room_id,player_id,sequence)
);
alter table app_private.game_input_packets enable row level security;
revoke all on app_private.game_input_packets from public,anon,authenticated;

-- Identity, receipt time and interval boundaries never come from the client.
create function app_private.submit_game_input(p_room uuid,p_sequence integer,p_flaps integer[])
returns jsonb language plpgsql security definer set search_path='' as $$
declare me uuid:=app_private.actor(); m public.matches; r public.game_rooms;
  packet app_private.game_input_packets; previous_packet app_private.game_input_packets;
  received timestamptz; received_ms bigint; start_ms bigint; tick integer; last_tick integer;
begin
  if p_sequence is null or p_sequence not between 0 and 44 or p_flaps is null
    or cardinality(p_flaps)>120 or coalesce(array_ndims(p_flaps),1)<>1
    or (cardinality(p_flaps)>0 and array_lower(p_flaps,1)<>1)
    then raise exception 'INVALID_INPUT'; end if;
  last_tick:=p_sequence*120-1;
  foreach tick in array p_flaps loop
    if tick is null or tick<=last_tick or tick>=(p_sequence+1)*120 then raise exception 'INVALID_INPUT'; end if;
    last_tick:=tick;
  end loop;
  select m0.* into m from public.matches m0 join public.game_rooms r0 on r0.match_id=m0.id
    where r0.id=p_room and me in (m0.user_low,m0.user_high);
  if not found then raise exception 'ROOM_UNAVAILABLE'; end if;
  perform pg_advisory_xact_lock(hashtextextended(m.user_low::text||m.user_high::text,2));
  perform app_private.actor();
  select * into m from public.matches where id=m.id and me in (user_low,user_high) for update;
  if not found then raise exception 'ROOM_UNAVAILABLE'; end if;
  if not app_private.account_available(m.user_low) or not app_private.account_available(m.user_high)
    or app_private.blocked(case when me=m.user_low then m.user_high else m.user_low end)
    then raise exception 'ROOM_UNAVAILABLE'; end if;
  select * into r from public.game_rooms where id=p_room and match_id=m.id for update;
  received:=clock_timestamp();
  if not found or r.status not in ('countdown','running','awaiting_result') or r.starts_at is null
    or r.expires_at<=received or r.engine_version<>'sky-hop-v1' or r.input_protocol<>'sky-hop-input-v1'
    then raise exception 'ROOM_UNAVAILABLE'; end if;
  select * into packet from app_private.game_input_packets where room_id=p_room and player_id=me and sequence=p_sequence;
  if found then
    if packet.flaps<>p_flaps then raise exception 'INPUT_CONFLICT'; end if;
    return jsonb_build_object('sequence',packet.sequence,'received_at',packet.received_at);
  end if;
  if p_sequence>0 then
    select * into previous_packet from app_private.game_input_packets where room_id=p_room and player_id=me and sequence=p_sequence-1;
    if not found then raise exception 'INPUT_SEQUENCE'; end if;
    if previous_packet.received_at>received then raise exception 'INPUT_WINDOW'; end if;
  end if;
  received_ms:=floor(extract(epoch from received)*1000);
  start_ms:=floor(extract(epoch from r.starts_at)*1000);
  if received_ms<start_ms+(p_sequence+1)*1000-250 or received_ms>start_ms+p_sequence*1000+5000
    then raise exception 'INPUT_WINDOW'; end if;
  insert into app_private.game_input_packets(room_id,player_id,sequence,flaps,received_at)
    values(p_room,me,p_sequence,p_flaps,received) returning * into packet;
  return jsonb_build_object('sequence',packet.sequence,'received_at',packet.received_at);
end $$;
create function public.submit_game_input(p_room uuid,p_sequence integer,p_flaps integer[])
returns jsonb language sql security invoker set search_path='' as $$
  select app_private.submit_game_input(p_room,p_sequence,p_flaps);
$$;
revoke all on function app_private.submit_game_input(uuid,integer,integer[]),public.submit_game_input(uuid,integer,integer[]) from public,anon,authenticated;
grant execute on function app_private.submit_game_input(uuid,integer,integer[]),public.submit_game_input(uuid,integer,integer[]) to authenticated;
