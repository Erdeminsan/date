create table app_private.moderators (
  user_id uuid primary key references auth.users(id) on delete cascade,
  granted_at timestamptz not null default clock_timestamp()
);
create table app_private.report_reviews (
  report_id uuid primary key references public.reports(id) on delete cascade,
  reviewer_id uuid references auth.users(id) on delete set null,
  decision text not null check(decision in ('dismissed','escalated')),
  note text not null check(char_length(btrim(note)) between 5 and 1000),
  reviewed_at timestamptz not null default clock_timestamp()
);
alter table app_private.moderators enable row level security;
alter table app_private.report_reviews enable row level security;
revoke all on app_private.moderators,app_private.report_reviews from public,anon,authenticated;
create index reports_review_feed on public.reports(created_at desc,id desc);
create function app_private.moderation_access() returns boolean
language plpgsql security definer set search_path='' as $$
declare me uuid:=app_private.actor();
begin
  return exists(select 1 from app_private.moderators where user_id=me);
end $$;
create function app_private.moderator_actor() returns uuid
language plpgsql security definer set search_path='' as $$
declare me uuid:=app_private.actor();
begin
  -- A role deletion waits for this transaction; subsequent requests fail closed.
  perform 1 from app_private.moderators where user_id=me for share;
  if not found then raise exception 'MODERATOR_REQUIRED' using errcode='42501'; end if;
  return me;
end $$;
create function app_private.moderation_reports(p_status text,p_before_time timestamptz,p_before_id uuid)
returns table(id uuid,reporter_name text,reported_name text,reason text,created_at timestamptz,decision text,review_note text)
language plpgsql security definer set search_path='' as $$
declare me uuid:=app_private.moderator_actor();
begin
  if p_status is null or p_status not in ('pending','reviewed') then raise exception 'INVALID_STATUS'; end if;
  if (p_before_time is null)<>(p_before_id is null) then raise exception 'INVALID_CURSOR'; end if;
  return query select r.id,a.display_name,b.display_name,r.reason,r.created_at,v.decision,v.note
    from public.reports r join public.profiles a on a.id=r.reporter_id join public.profiles b on b.id=r.reported_id
    left join app_private.report_reviews v on v.report_id=r.id
    where me not in(r.reporter_id,r.reported_id)
      and ((p_status='pending' and v.report_id is null) or (p_status='reviewed' and v.report_id is not null))
      and (p_before_time is null or (r.created_at,r.id)<(p_before_time,p_before_id))
    order by r.created_at desc,r.id desc limit 21;
end $$;
create function app_private.review_report(p_report uuid,p_decision text,p_note text) returns void
language plpgsql security definer set search_path='' as $$
declare me uuid:=app_private.moderator_actor(); r public.reports; existing app_private.report_reviews;
begin
  if p_decision is null or p_decision not in ('dismissed','escalated') or p_note is null
    or char_length(btrim(p_note)) not between 5 and 1000 then raise exception 'INVALID_REVIEW'; end if;
  select * into r from public.reports where id=p_report for update;
  if not found or me in(r.reporter_id,r.reported_id) then raise exception 'REPORT_UNAVAILABLE'; end if;
  perform app_private.actor();
  select * into existing from app_private.report_reviews where report_id=p_report;
  if found then
    if existing.reviewer_id=me and existing.decision=p_decision and existing.note=btrim(p_note) then return; end if;
    raise exception 'REVIEW_CONFLICT';
  end if;
  insert into app_private.report_reviews(report_id,reviewer_id,decision,note) values(p_report,me,p_decision,btrim(p_note));
end $$;
create function public.moderation_access() returns boolean language sql security invoker set search_path='' as $$ select app_private.moderation_access(); $$;
create function public.moderation_reports(p_status text default 'pending',p_before_time timestamptz default null,p_before_id uuid default null)
returns table(id uuid,reporter_name text,reported_name text,reason text,created_at timestamptz,decision text,review_note text)
language sql security invoker set search_path='' as $$ select * from app_private.moderation_reports(p_status,p_before_time,p_before_id); $$;
create function public.review_report(p_report uuid,p_decision text,p_note text) returns void
language sql security invoker set search_path='' as $$ select app_private.review_report(p_report,p_decision,p_note); $$;
revoke all on function app_private.moderation_access(),app_private.moderator_actor(),app_private.moderation_reports(text,timestamptz,uuid),app_private.review_report(uuid,text,text),public.moderation_access(),public.moderation_reports(text,timestamptz,uuid),public.review_report(uuid,text,text) from public,anon,authenticated;
grant execute on function app_private.moderation_access(),app_private.moderation_reports(text,timestamptz,uuid),app_private.review_report(uuid,text,text),public.moderation_access(),public.moderation_reports(text,timestamptz,uuid),public.review_report(uuid,text,text) to authenticated;
-- No moderator memberships are seeded. Operator designation is a separate action.
