-- Additive RPC: old clients retain report_profile(uuid,text) during rollout.
alter table public.reports add column profile_request_id uuid;
create unique index reports_profile_request_unique
  on public.reports(reporter_id,profile_request_id) where profile_request_id is not null;

create function app_private.report_profile_once(p_target uuid,p_reason text,p_request uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare me uuid:=app_private.actor(); existing public.reports; result uuid;
begin
  if p_request is null or p_target is null or p_target=me or p_reason is null
    or char_length(btrim(p_reason)) not between 5 and 1000
    or not app_private.has_profile() then raise exception 'INVALID_REPORT'; end if;
  perform pg_advisory_xact_lock(hashtextextended(me::text,3));
  select * into existing from public.reports
    where reporter_id=me and profile_request_id=p_request;
  if found then
    if existing.reported_id=p_target and existing.reason=btrim(p_reason) then return existing.id; end if;
    raise exception 'REPORT_CONFLICT';
  end if;
  if (select count(*) from app_private.report_events
    where actor_id=me and created_at>now()-interval '1 day')>=10 then raise exception 'REPORT_LIMIT'; end if;
  insert into public.reports(reporter_id,reported_id,reason,profile_request_id)
    values(me,p_target,btrim(p_reason),p_request) returning id into result;
  return result;
end $$;
create function public.report_profile_once(p_target uuid,p_reason text,p_request uuid)
returns uuid language sql security invoker set search_path='' as $$
  select app_private.report_profile_once(p_target,p_reason,p_request);
$$;
revoke all on function app_private.report_profile_once(uuid,text,uuid),public.report_profile_once(uuid,text,uuid)
  from public,anon,authenticated;
grant execute on function app_private.report_profile_once(uuid,text,uuid),public.report_profile_once(uuid,text,uuid)
  to authenticated;
