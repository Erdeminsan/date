create table public.messages (
  id bigint generated always as identity primary key,
  match_id uuid not null references public.matches(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  request_id uuid not null,
  body text not null check(char_length(btrim(body)) between 1 and 1000),
  created_at timestamptz not null default clock_timestamp(),
  unique(sender_id,request_id)
);
create index messages_match_id on public.messages(match_id,id desc);
alter table public.messages enable row level security;
revoke all on public.messages from public,anon,authenticated;
grant select on public.messages to authenticated;
create policy messages_participants on public.messages for select to authenticated using (
  exists(select 1 from public.matches m where m.id=match_id)
);
create table app_private.message_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default clock_timestamp()
);
create index message_events_user_time on app_private.message_events(user_id,created_at);
alter table app_private.message_events enable row level security;
revoke all on app_private.message_events from public,anon,authenticated;

create function app_private.send_message(p_match uuid,p_request uuid,p_body text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=app_private.actor(); m public.matches; r public.messages; checked_at timestamptz;
begin
  if p_request is null or p_body is null or char_length(btrim(p_body)) not between 1 and 1000 then raise exception 'INVALID_MESSAGE'; end if;
  perform pg_advisory_xact_lock(hashtextextended(me::text,7));
  select * into m from public.matches where id=p_match and me in (user_low,user_high);
  if not found then raise exception 'CHAT_UNAVAILABLE'; end if;
  perform pg_advisory_xact_lock(hashtextextended(m.user_low::text || m.user_high::text,2));
  perform app_private.actor();
  select * into m from public.matches where id=p_match and me in (user_low,user_high) for update;
  if not found then raise exception 'CHAT_UNAVAILABLE'; end if;
  if not app_private.account_available(m.user_low) or not app_private.account_available(m.user_high)
    or app_private.blocked(case when me=m.user_low then m.user_high else m.user_low end)
    then raise exception 'CHAT_UNAVAILABLE'; end if;
  select * into r from public.messages where sender_id=me and request_id=p_request;
  if found then
    if r.match_id<>p_match or r.body<>btrim(p_body) then raise exception 'MESSAGE_CONFLICT'; end if;
    return to_jsonb(r)||jsonb_build_object('id',r.id::text);
  end if;
  checked_at:=clock_timestamp();
  delete from app_private.message_events where user_id=me and created_at<=checked_at-interval '1 minute';
  if (select count(*) from app_private.message_events where user_id=me)>=60 then raise exception 'MESSAGE_LIMIT'; end if;
  insert into public.messages(match_id,sender_id,request_id,body,created_at)
    values(p_match,me,p_request,btrim(p_body),checked_at) returning * into r;
  insert into app_private.message_events(user_id,created_at) values(me,checked_at);
  return to_jsonb(r)||jsonb_build_object('id',r.id::text);
end $$;
create function public.send_message(p_match uuid,p_request uuid,p_body text) returns jsonb
language sql security invoker set search_path='' as $$ select app_private.send_message(p_match,p_request,p_body); $$;
revoke all on function app_private.send_message(uuid,uuid,text),public.send_message(uuid,uuid,text) from public,anon,authenticated;
grant execute on function app_private.send_message(uuid,uuid,text),public.send_message(uuid,uuid,text) to authenticated;

create function public.messages_page(p_match uuid,p_before bigint default null,p_after bigint default null) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
  perform app_private.actor();
  if (p_before is not null and p_after is not null) or p_before<=0 or p_after<=0 then raise exception 'INVALID_CURSOR'; end if;
  if not exists(select 1 from public.matches where id=p_match) then raise exception 'CHAT_UNAVAILABLE'; end if;
  if p_after is not null then
    with page as (select * from public.messages where match_id=p_match and id>p_after order by id asc limit 51),
    shown as (select * from page order by id asc limit 50)
    select jsonb_build_object('messages',coalesce((select jsonb_agg(to_jsonb(shown)||jsonb_build_object('id',shown.id::text) order by shown.id asc) from shown),'[]'::jsonb),
      'has_more',(select count(*)>50 from page)) into result;
  else
    with page as (select * from public.messages where match_id=p_match and (p_before is null or id<p_before) order by id desc limit 51),
    shown as (select * from page order by id desc limit 50)
    select jsonb_build_object('messages',coalesce((select jsonb_agg(to_jsonb(shown)||jsonb_build_object('id',shown.id::text) order by shown.id desc) from shown),'[]'::jsonb),
      'has_more',(select count(*)>50 from page)) into result;
  end if;
  return result;
end $$;
revoke all on function public.messages_page(uuid,bigint,bigint) from public,anon,authenticated;
grant execute on function public.messages_page(uuid,bigint,bigint) to authenticated;
