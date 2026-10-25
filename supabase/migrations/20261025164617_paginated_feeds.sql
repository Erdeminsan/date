-- Stable keyset order; the 21st row is a look-ahead for a 20-item client page.
create index profiles_feed_idx on public.profiles(created_at desc, id desc) where discoverable;
create index matches_low_feed_idx on public.matches(user_low, created_at desc, id desc);
create index matches_high_feed_idx on public.matches(user_high, created_at desc, id desc);

create function public.discover_page(p_before_time timestamptz default null, p_before_id uuid default null)
returns setof public.profiles language plpgsql stable security invoker set search_path = '' as $$
begin
  perform app_private.actor();
  if (p_before_time is null) <> (p_before_id is null) then raise exception 'INVALID_CURSOR'; end if;
  return query select p.* from public.profiles p
  where p.id <> (select auth.uid()) and p.discoverable
    and (p_before_time is null or (p.created_at,p.id) < (p_before_time,p_before_id))
    and not exists(select 1 from public.likes l where l.sender_id=(select auth.uid()) and l.recipient_id=p.id)
  order by p.created_at desc, p.id desc limit 21;
end $$;

create function public.matches_page(p_before_time timestamptz default null, p_before_id uuid default null)
returns table(id uuid, other_id uuid, display_name text, created_at timestamptz)
language plpgsql stable security invoker set search_path = '' as $$
begin
  perform app_private.actor();
  if (p_before_time is null) <> (p_before_id is null) then raise exception 'INVALID_CURSOR'; end if;
  return query
  select m.id, case when m.user_low=(select auth.uid()) then m.user_high else m.user_low end,
    coalesce(p.display_name,'Gizli profil'),m.created_at
  from public.matches m
  left join public.profiles p on p.id=case when m.user_low=(select auth.uid()) then m.user_high else m.user_low end
  where (select auth.uid()) in (m.user_low,m.user_high)
    and (p_before_time is null or (m.created_at,m.id) < (p_before_time,p_before_id))
  order by m.created_at desc,m.id desc limit 21;
end $$;
revoke all on function public.discover_page(timestamptz,uuid),public.matches_page(timestamptz,uuid) from public,anon,authenticated;
grant execute on function public.discover_page(timestamptz,uuid),public.matches_page(timestamptz,uuid) to authenticated;
