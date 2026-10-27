create table app_private.game_result_jobs (
  room_id uuid primary key references public.game_rooms(id) on delete cascade,
  status text not null default 'pending' check(status in ('pending','completed','failed')),
  created_at timestamptz not null default clock_timestamp(),
  not_before timestamptz not null,
  deadline timestamptz not null,
  next_attempt_at timestamptz not null,
  attempts integer not null default 0,
  delivery_token uuid,
  last_request_id bigint,
  last_error text check(last_error in ('deadline_exceeded','room_closed','invalid_round')),
  finished_at timestamptz
);
create index game_result_jobs_due on app_private.game_result_jobs(next_attempt_at) where status='pending';
alter table app_private.game_result_jobs enable row level security;
revoke all on app_private.game_result_jobs from public,anon,authenticated,service_role;

-- Called only while submit_game_input holds the pair + match + room locks.
create function app_private.enqueue_complete_round(p_room uuid) returns void
language plpgsql security definer set search_path='' as $$
declare r public.game_rooms; m public.matches;
begin
 select * into r from public.game_rooms where id=p_room;
 if not found or r.status not in ('countdown','running','awaiting_result') or r.expires_at<=clock_timestamp() then return; end if;
 select * into m from public.matches where id=r.match_id;
 if (select count(*) from app_private.game_input_packets where room_id=r.id and player_id in (m.user_low,m.user_high))<>90 then return; end if;
 insert into app_private.game_result_jobs(room_id,not_before,deadline,next_attempt_at)
 values(r.id,r.ends_at,r.ends_at+interval '24 hours',r.ends_at) on conflict do nothing;
 update public.game_rooms set status='awaiting_result',expires_at=r.ends_at+interval '24 hours' where id=r.id;
end $$;
revoke all on function app_private.enqueue_complete_round(uuid) from public,anon,authenticated,service_role;

-- Only postgres/scheduler can claim deliveries. Pair lock precedes job row lock.
create function app_private.claim_game_result_dispatches(p_limit integer default 10)
returns table(room_id uuid,delivery_token uuid) language plpgsql security definer set search_path='' as $$
declare candidate record; j app_private.game_result_jobs; r public.game_rooms; token uuid;
begin
 if p_limit is null or p_limit not between 1 and 20 then raise exception 'INVALID_LIMIT'; end if;
 for candidate in
   select q.room_id,m.user_low,m.user_high from app_private.game_result_jobs q
   join public.game_rooms g on g.id=q.room_id join public.matches m on m.id=g.match_id
   where q.status='pending' and q.next_attempt_at<=clock_timestamp()
   order by q.next_attempt_at,q.room_id limit p_limit
 loop
   if not pg_try_advisory_xact_lock(hashtextextended(candidate.user_low::text||candidate.user_high::text,2)) then continue; end if;
   select * into r from public.game_rooms where id=candidate.room_id for update;
   select * into j from app_private.game_result_jobs q where q.room_id=candidate.room_id for update;
   if not found or j.status<>'pending' or j.next_attempt_at>clock_timestamp() then continue; end if;
   if r.status='completed' then
     update app_private.game_result_jobs q set status='completed',finished_at=clock_timestamp(),delivery_token=null where q.room_id=j.room_id;
   elsif j.deadline<=clock_timestamp() or r.status not in ('countdown','running','awaiting_result') then
     update app_private.game_result_jobs q set status='failed',finished_at=clock_timestamp(),delivery_token=null,
       last_error=case when j.deadline<=clock_timestamp() then 'deadline_exceeded' else 'room_closed' end where q.room_id=j.room_id;
     update public.game_rooms set status='expired' where id=j.room_id and status in ('countdown','running','awaiting_result');
   else
     token:=gen_random_uuid();
     update app_private.game_result_jobs q set delivery_token=token,attempts=attempts+1,
       next_attempt_at=clock_timestamp()+make_interval(secs=>least(300,30*power(2,least(attempts,4)))::double precision)
       where q.room_id=j.room_id;
     room_id:=j.room_id;delivery_token:=token;return next;
   end if;
 end loop;
end $$;
revoke all on function app_private.claim_game_result_dispatches(integer) from public,anon,authenticated,service_role;

-- A fresh, unguessable per-delivery capability authenticates the internal HTTP call.
-- Never return this capability through user-facing RPCs.
create function app_private.queued_result_actor(p_room uuid,p_delivery uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare j app_private.game_result_jobs; m public.matches;
begin
 if p_delivery is null or not exists(select 1 from app_private.game_result_jobs where room_id=p_room and delivery_token=p_delivery
   and status='pending' and next_attempt_at>clock_timestamp() and deadline>clock_timestamp()) then raise exception 'JOB_UNAVAILABLE'; end if;
 select x.* into m from public.matches x join public.game_rooms r on r.match_id=x.id where r.id=p_room;
 if not found then raise exception 'JOB_UNAVAILABLE'; end if;
 m:=app_private.result_match(p_room,m.user_low);
 select * into j from app_private.game_result_jobs where room_id=p_room for update;
 if not found or j.delivery_token is distinct from p_delivery or j.status<>'pending'
   or j.next_attempt_at<=clock_timestamp() or j.deadline<=clock_timestamp() then raise exception 'JOB_UNAVAILABLE'; end if;
 return m.user_low;
end $$;
create function app_private.prepare_queued_game_result(p_room uuid,p_delivery uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 return app_private.prepare_game_result(p_room,app_private.queued_result_actor(p_room,p_delivery));
end $$;
create function app_private.finalize_queued_game_result(p_room uuid,p_delivery uuid,p_low_score integer,p_high_score integer,p_low_hits integer,p_high_hits integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 result:=app_private.finalize_game_result(p_room,app_private.queued_result_actor(p_room,p_delivery),p_low_score,p_high_score,p_low_hits,p_high_hits);
 return jsonb_build_object('status',result->>'status');
end $$;
create function app_private.fail_queued_game_result(p_room uuid,p_delivery uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform app_private.queued_result_actor(p_room,p_delivery);
 update app_private.game_result_jobs set status='failed',last_error='invalid_round',delivery_token=null,finished_at=clock_timestamp() where room_id=p_room;
 update public.game_rooms set status='expired' where id=p_room and status='awaiting_result';
end $$;
create function app_private.complete_result_job() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 update app_private.game_result_jobs set status='completed',delivery_token=null,finished_at=clock_timestamp() where room_id=new.room_id;
 return new;
end $$;
create trigger complete_result_job after insert on app_private.game_results for each row execute function app_private.complete_result_job();

create function public.prepare_queued_game_result(p_room uuid,p_delivery uuid) returns jsonb language sql security invoker set search_path='' as $$ select app_private.prepare_queued_game_result(p_room,p_delivery); $$;
create function public.finalize_queued_game_result(p_room uuid,p_delivery uuid,p_low_score integer,p_high_score integer,p_low_hits integer,p_high_hits integer) returns jsonb language sql security invoker set search_path='' as $$ select app_private.finalize_queued_game_result(p_room,p_delivery,p_low_score,p_high_score,p_low_hits,p_high_hits); $$;
create function public.fail_queued_game_result(p_room uuid,p_delivery uuid) returns void language sql security invoker set search_path='' as $$ select app_private.fail_queued_game_result(p_room,p_delivery); $$;
revoke all on function app_private.queued_result_actor(uuid,uuid),app_private.complete_result_job(),app_private.prepare_queued_game_result(uuid,uuid),app_private.finalize_queued_game_result(uuid,uuid,integer,integer,integer,integer),app_private.fail_queued_game_result(uuid,uuid),public.prepare_queued_game_result(uuid,uuid),public.finalize_queued_game_result(uuid,uuid,integer,integer,integer,integer),public.fail_queued_game_result(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function app_private.prepare_queued_game_result(uuid,uuid),app_private.finalize_queued_game_result(uuid,uuid,integer,integer,integer,integer),app_private.fail_queued_game_result(uuid,uuid),public.prepare_queued_game_result(uuid,uuid),public.finalize_queued_game_result(uuid,uuid,integer,integer,integer,integer),public.fail_queued_game_result(uuid,uuid) to service_role;

create or replace function app_private.submit_game_input(p_room uuid,p_sequence integer,p_flaps integer[])
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
  perform app_private.enqueue_complete_round(p_room);
  return jsonb_build_object('sequence',packet.sequence,'received_at',packet.received_at);
end $$;

create or replace function app_private.game_room_action(p_match uuid,p_action text,p_room uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare me uuid:=app_private.actor(); m public.matches; r public.game_rooms; checked_at timestamptz;
begin
  if p_action is null or p_action not in ('read','invite','accept','decline','cancel','ready') then raise exception 'INVALID_ROOM_ACTION'; end if;
  if p_action='invite' then
    if p_room is not null then raise exception 'INVALID_ROOM_ACTION'; end if;
    perform pg_advisory_xact_lock(hashtextextended(me::text,6));
  elsif p_action<>'read' and p_room is null then raise exception 'ROOM_UNAVAILABLE';
  end if;
  select * into m from public.matches where id=p_match and me in (user_low,user_high);
  if not found then raise exception 'ROOM_UNAVAILABLE'; end if;
  perform pg_advisory_xact_lock(hashtextextended(m.user_low::text || m.user_high::text,2));
  perform app_private.actor();
  select * into m from public.matches where id=p_match and me in (user_low,user_high) for update;
  if not found then raise exception 'ROOM_UNAVAILABLE'; end if;
  if not app_private.account_available(m.user_low) or not app_private.account_available(m.user_high)
    or app_private.blocked(case when me=m.user_low then m.user_high else m.user_low end)
    then raise exception 'ROOM_UNAVAILABLE'; end if;
  checked_at:=clock_timestamp();
  update public.game_rooms set status='expired' where match_id=p_match
    and status in ('invited','accepted','countdown','running','awaiting_result') and expires_at<=checked_at;
  update public.game_rooms set status='running' where match_id=p_match and status='countdown' and starts_at<=checked_at;
  update public.game_rooms set status='awaiting_result' where match_id=p_match and status='running' and ends_at<=checked_at;
  if p_action='invite' then
    select * into r from public.game_rooms where match_id=p_match and status in ('invited','accepted','countdown','running','awaiting_result');
    if not found then
      if not exists(select 1 from public.profiles where id=m.user_low and discoverable)
        or not exists(select 1 from public.profiles where id=m.user_high and discoverable)
        then raise exception 'PROFILE_UNAVAILABLE'; end if;
      delete from app_private.game_invite_events where user_id=me and created_at<=checked_at-interval '1 day';
      if (select count(*) from app_private.game_invite_events where user_id=me)>=20 then raise exception 'INVITE_LIMIT'; end if;
      insert into public.game_rooms(match_id,inviter_id,created_at,expires_at)
        values(p_match,me,checked_at,checked_at+interval '60 seconds') returning * into r;
      insert into app_private.game_invite_events(user_id,created_at) values(me,checked_at);
    end if;
  else
    if p_room is null then
      select * into r from public.game_rooms where match_id=p_match order by created_at desc,id desc limit 1;
      if not found then return jsonb_build_object('room',null,'server_now',checked_at); end if;
    else
      select * into r from public.game_rooms where id=p_room and match_id=p_match;
      if not found then raise exception 'ROOM_UNAVAILABLE'; end if;
    end if;
    if p_action in ('accept','decline') and r.inviter_id=me then raise exception 'ROOM_ACTION_FORBIDDEN'; end if;
    if r.status='invited' and p_action='accept' then
      update public.game_rooms set status='accepted',expires_at=checked_at+interval '120 seconds' where id=r.id returning * into r;
    elsif r.status='invited' and p_action='decline' then
      update public.game_rooms set status='declined' where id=r.id returning * into r;
    elsif r.status='accepted' and p_action='ready' then
      update public.game_rooms set ready_low=ready_low or me=m.user_low,
        ready_high=ready_high or me=m.user_high where id=r.id returning * into r;
      if r.ready_low and r.ready_high then
        update public.game_rooms set status='countdown',
          seed=('x'||substr(replace(gen_random_uuid()::text,'-',''),1,8))::bit(32)::bigint,
          starts_at=checked_at+interval '5 seconds', ends_at=checked_at+interval '50 seconds',
          expires_at=checked_at+interval '65 seconds'
          where id=r.id returning * into r;
      end if;
    elsif r.status in ('invited','accepted','countdown','running','awaiting_result') and p_action='cancel'
      and not exists(select 1 from app_private.game_result_jobs where room_id=r.id and status='pending') then
      update public.game_rooms set status='cancelled' where id=r.id returning * into r;
    end if;
  end if;
  return jsonb_build_object('room',to_jsonb(r),'server_now',checked_at,'my_ready',case when me=m.user_low then r.ready_low else r.ready_high end);
end $$;

create or replace function app_private.prepare_game_result(p_room uuid,p_actor uuid) returns jsonb
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
  return jsonb_build_object('status','verify','resultDeadlineMs',floor(extract(epoch from least(r.expires_at,r.ends_at+interval '24 hours'))*1000)::bigint,'nowMs',floor(extract(epoch from stamp)*1000)::bigint,'streams',streams,
    'room',jsonb_build_object('id',r.id,'players',jsonb_build_array(m.user_low,m.user_high),'status','awaiting_result',
      'seed',r.seed,'engineVersion',r.engine_version,'inputProtocol',r.input_protocol,
      'startsAtMs',floor(extract(epoch from r.starts_at)*1000)::bigint,'endsAtMs',floor(extract(epoch from r.ends_at)*1000)::bigint));
end $$;
