create function app_private.unmatch(p_match uuid) returns void
language plpgsql security definer set search_path='' as $$
declare me uuid:=app_private.actor(); m public.matches;
begin
  select * into m from public.matches where id=p_match and me in (user_low,user_high);
  -- A missing or inaccessible match has the same idempotent result.
  if not found then return; end if;
  perform pg_advisory_xact_lock(hashtextextended(m.user_low::text || m.user_high::text,2));
  perform app_private.actor();
  select * into m from public.matches where id=p_match and me in (user_low,user_high) for update;
  if not found then return; end if;
  delete from public.matches where id=p_match;
  delete from public.likes where (sender_id=m.user_low and recipient_id=m.user_high)
    or (sender_id=m.user_high and recipient_id=m.user_low);
end $$;
create function public.unmatch(p_match uuid) returns void
language sql security invoker set search_path='' as $$ select app_private.unmatch(p_match); $$;
revoke all on function app_private.unmatch(uuid),public.unmatch(uuid) from public,anon,authenticated;
grant execute on function app_private.unmatch(uuid),public.unmatch(uuid) to authenticated;
