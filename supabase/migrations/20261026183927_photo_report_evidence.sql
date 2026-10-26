-- Bounded binary snapshot in its own private table: report/account deletion is atomic,
-- with no orphaned Storage copies. Feed RPCs never return image bytes.
create table app_private.report_photo_evidence (
  report_id uuid primary key references public.reports(id) on delete cascade,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  source_path text not null,
  source_object_id uuid not null,
  sha256 text not null check(sha256 ~ '^[0-9a-f]{64}$'),
  image_bytes bytea not null check(octet_length(image_bytes) between 5 and 2097152),
  captured_at timestamptz not null default clock_timestamp(),
  unique(reporter_id,request_id)
);
alter table app_private.report_photo_evidence enable row level security;
revoke all on app_private.report_photo_evidence from public,anon,authenticated;
-- Trusted Edge-only actor parameter. This helper is not granted to clients.
create function app_private.photo_report_actor(p_actor uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
  if not app_private.account_active(p_actor) or not exists(select 1 from public.profile_details where user_id=p_actor)
    then raise exception 'AUTH_REQUIRED'; end if;
end $$;
create function app_private.photo_report_source(p_actor uuid,p_target uuid,p_path text) returns uuid
language plpgsql security definer set search_path='' as $$
declare object_id uuid;
begin
  perform app_private.photo_report_actor(p_actor);
  if p_target is null or p_target=p_actor or not app_private.account_active(p_target) then raise exception 'PHOTO_UNAVAILABLE'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_target::text,1));
  if not app_private.account_active(p_target) or exists(select 1 from public.blocks where
    (blocker_id=p_actor and blocked_id=p_target) or (blocker_id=p_target and blocked_id=p_actor))
    then raise exception 'PHOTO_UNAVAILABLE'; end if;
  perform 1 from public.profiles where id=p_target and discoverable and photo_path=p_path for share;
  if not found then raise exception 'PHOTO_UNAVAILABLE'; end if;
  select id into object_id from storage.objects where bucket_id='profile-photos' and name=p_path for share;
  if not found then raise exception 'PHOTO_UNAVAILABLE'; end if;
  return object_id;
end $$;
create function app_private.prepare_photo_report(p_actor uuid,p_target uuid,p_path text,p_request uuid,p_reason text,p_sha256 text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare e app_private.report_photo_evidence; r public.reports; source_id uuid;
begin
  perform app_private.photo_report_actor(p_actor);
  if p_request is null or p_reason is null or char_length(btrim(p_reason)) not between 5 and 1000
    or p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$' or p_path is null or char_length(p_path)>200 then raise exception 'INVALID_REPORT'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_actor::text,3));
  select * into e from app_private.report_photo_evidence where reporter_id=p_actor and request_id=p_request;
  if found then
    select * into r from public.reports where id=e.report_id;
    if r.reported_id=p_target and r.reason=btrim(p_reason) and e.source_path=p_path and e.sha256=p_sha256
      then return jsonb_build_object('status','completed','report_id',r.id); end if;
    raise exception 'REPORT_CONFLICT';
  end if;
  source_id:=app_private.photo_report_source(p_actor,p_target,p_path);
  if (select count(*) from public.reports where reporter_id=p_actor and created_at>now()-interval '1 day')>=10 then raise exception 'REPORT_LIMIT'; end if;
  return jsonb_build_object('status','capture','source_path',p_path,'source_object_id',source_id);
end $$;
create function app_private.finalize_photo_report(p_actor uuid,p_target uuid,p_path text,p_request uuid,p_reason text,p_sha256 text,p_source_object uuid,p_base64 text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare prepared jsonb; bytes bytea; report uuid;
begin
  -- Recheck visibility, object identity, quota and retry after the remote download.
  prepared:=app_private.prepare_photo_report(p_actor,p_target,p_path,p_request,p_reason,p_sha256);
  if prepared->>'status'='completed' then return prepared; end if;
  if p_source_object is null or (prepared->>'source_object_id')::uuid<>p_source_object then raise exception 'PHOTO_CHANGED'; end if;
  if p_base64 is null or length(p_base64)>2796204 then raise exception 'INVALID_IMAGE'; end if;
  bytes:=decode(p_base64,'base64');
  if octet_length(bytes) not between 5 and 2097152 or substring(bytes from 1 for 3)<>decode('ffd8ff','hex')
    or substring(bytes from octet_length(bytes)-1 for 2)<>decode('ffd9','hex')
    or encode(sha256(bytes),'hex')<>p_sha256 then raise exception 'INVALID_IMAGE'; end if;
  insert into public.reports(reporter_id,reported_id,reason) values(p_actor,p_target,btrim(p_reason)) returning id into report;
  insert into app_private.report_photo_evidence(report_id,reporter_id,request_id,source_path,source_object_id,sha256,image_bytes)
    values(report,p_actor,p_request,p_path,p_source_object,p_sha256,bytes);
  return jsonb_build_object('status','completed','report_id',report);
end $$;
create function public.prepare_photo_report(p_actor uuid,p_target uuid,p_path text,p_request uuid,p_reason text,p_sha256 text) returns jsonb
language sql security invoker set search_path='' as $$ select app_private.prepare_photo_report(p_actor,p_target,p_path,p_request,p_reason,p_sha256); $$;
create function public.finalize_photo_report(p_actor uuid,p_target uuid,p_path text,p_request uuid,p_reason text,p_sha256 text,p_source_object uuid,p_base64 text) returns jsonb
language sql security invoker set search_path='' as $$ select app_private.finalize_photo_report(p_actor,p_target,p_path,p_request,p_reason,p_sha256,p_source_object,p_base64); $$;
revoke all on function app_private.photo_report_actor(uuid),app_private.photo_report_source(uuid,uuid,text),app_private.prepare_photo_report(uuid,uuid,text,uuid,text,text),app_private.finalize_photo_report(uuid,uuid,text,uuid,text,text,uuid,text),public.prepare_photo_report(uuid,uuid,text,uuid,text,text),public.finalize_photo_report(uuid,uuid,text,uuid,text,text,uuid,text) from public,anon,authenticated;
grant execute on function app_private.prepare_photo_report(uuid,uuid,text,uuid,text,text),app_private.finalize_photo_report(uuid,uuid,text,uuid,text,text,uuid,text),public.prepare_photo_report(uuid,uuid,text,uuid,text,text),public.finalize_photo_report(uuid,uuid,text,uuid,text,text,uuid,text) to service_role;
create function app_private.moderation_photo_evidence(p_report uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=app_private.moderator_actor(); r public.reports; e app_private.report_photo_evidence;
begin
  select * into r from public.reports where id=p_report;
  if not found or me in(r.reporter_id,r.reported_id) then raise exception 'REPORT_UNAVAILABLE'; end if;
  select * into e from app_private.report_photo_evidence where report_id=r.id;
  if not found then raise exception 'PHOTO_UNAVAILABLE'; end if;
  return jsonb_build_object('base64',replace(encode(e.image_bytes,'base64'),E'\n',''),'sha256',e.sha256,'captured_at',e.captured_at);
end $$;
create function public.moderation_photo_evidence(p_report uuid) returns jsonb language sql security invoker set search_path='' as $$ select app_private.moderation_photo_evidence(p_report); $$;
revoke all on function app_private.moderation_photo_evidence(uuid),public.moderation_photo_evidence(uuid) from public,anon,authenticated;
grant execute on function app_private.moderation_photo_evidence(uuid),public.moderation_photo_evidence(uuid) to authenticated;
create function app_private.moderation_reports_v3(p_status text,p_before_time timestamptz,p_before_id uuid) returns table(id uuid,reporter_name text,reported_name text,reason text,created_at timestamptz,decision text,review_note text,message_body text,message_created_at timestamptz,evidence_captured_at timestamptz,photo_report_id uuid)
language plpgsql security definer set search_path='' as $$ begin
  perform app_private.moderator_actor();
  return query select r.*,e.report_id from app_private.moderation_reports_v2(p_status,p_before_time,p_before_id) r left join app_private.report_photo_evidence e on e.report_id=r.id order by r.created_at desc,r.id desc;
end $$;
create function public.moderation_reports_v3(p_status text default 'pending',p_before_time timestamptz default null,p_before_id uuid default null) returns table(id uuid,reporter_name text,reported_name text,reason text,created_at timestamptz,decision text,review_note text,message_body text,message_created_at timestamptz,evidence_captured_at timestamptz,photo_report_id uuid)
language sql security invoker set search_path='' as $$ select * from app_private.moderation_reports_v3(p_status,p_before_time,p_before_id); $$;
revoke all on function app_private.moderation_reports_v3(text,timestamptz,uuid),public.moderation_reports_v3(text,timestamptz,uuid) from public,anon,authenticated;
grant execute on function app_private.moderation_reports_v3(text,timestamptz,uuid),public.moderation_reports_v3(text,timestamptz,uuid) to authenticated;
create function app_private.moderation_appeals_v4(p_reviewed boolean,p_before_time timestamptz,p_before_id uuid) returns table(id uuid,sanction_id uuid,appeal_id uuid,created_at timestamptz,expires_at timestamptz,active boolean,body text,decision text,response text,display_name text,internal_reason text,public_notice text,message_body text,message_created_at timestamptz,evidence_captured_at timestamptz,photo_report_id uuid)
language plpgsql security definer set search_path='' as $$ begin
  perform app_private.moderator_actor();
  return query select r.*,e.report_id from app_private.moderation_appeals_v3(p_reviewed,p_before_time,p_before_id) r join app_private.account_sanctions s on s.id=r.sanction_id left join app_private.report_photo_evidence e on e.report_id=s.report_id order by r.created_at desc,r.id desc;
end $$;
create function public.moderation_appeals_v4(p_reviewed boolean default false,p_before_time timestamptz default null,p_before_id uuid default null) returns table(id uuid,sanction_id uuid,appeal_id uuid,created_at timestamptz,expires_at timestamptz,active boolean,body text,decision text,response text,display_name text,internal_reason text,public_notice text,message_body text,message_created_at timestamptz,evidence_captured_at timestamptz,photo_report_id uuid)
language sql security invoker set search_path='' as $$ select * from app_private.moderation_appeals_v4(p_reviewed,p_before_time,p_before_id); $$;
revoke all on function app_private.moderation_appeals_v4(boolean,timestamptz,uuid),public.moderation_appeals_v4(boolean,timestamptz,uuid) from public,anon,authenticated;
grant execute on function app_private.moderation_appeals_v4(boolean,timestamptz,uuid),public.moderation_appeals_v4(boolean,timestamptz,uuid) to authenticated;
create function app_private.moderation_photo_access(p_report uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare me uuid:=app_private.moderator_actor();
begin
  return exists(select 1 from public.reports r join app_private.report_photo_evidence e on e.report_id=r.id
    where r.id=p_report and me not in(r.reporter_id,r.reported_id));
end $$;
create function public.moderation_photo_access(p_report uuid) returns boolean language sql security invoker set search_path='' as $$ select app_private.moderation_photo_access(p_report); $$;
revoke all on function app_private.moderation_photo_access(uuid),public.moderation_photo_access(uuid) from public,anon,authenticated;
grant execute on function app_private.moderation_photo_access(uuid),public.moderation_photo_access(uuid) to authenticated;
