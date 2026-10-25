alter table public.game_rooms drop constraint game_rooms_status_check;
alter table public.game_rooms add constraint game_rooms_status_check check(status in ('invited','accepted','countdown','running','awaiting_result','declined','cancelled','expired'));
alter table public.game_rooms add column ready_low boolean not null default false,
  add column ready_high boolean not null default false,
  add column engine_version text not null default 'sky-hop-v1',
  add column seed bigint check(seed between 0 and 4294967295),
  add column starts_at timestamptz,
  add column ends_at timestamptz;
alter table public.game_rooms add constraint game_schedule_valid check (
  (starts_at is null and ends_at is null and seed is null) or
  (starts_at is not null and ends_at is not null and ends_at=starts_at+interval '45 seconds' and seed is not null and ready_low and ready_high)
);
drop index public.game_rooms_one_active;
create unique index game_rooms_one_active on public.game_rooms(match_id)
where status in ('invited','accepted','countdown','running','awaiting_result');
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
    elsif r.status in ('invited','accepted','countdown','running','awaiting_result') and p_action='cancel' then
      update public.game_rooms set status='cancelled' where id=r.id returning * into r;
    end if;
  end if;
  return jsonb_build_object('room',to_jsonb(r),'server_now',checked_at,'my_ready',case when me=m.user_low then r.ready_low else r.ready_high end);
end $$;
