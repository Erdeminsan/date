create extension if not exists pg_cron;
create extension if not exists pg_net;
revoke all on table net.http_request_queue from public,anon,authenticated;

create table app_private.game_result_worker_config (
  singleton boolean primary key default true check(singleton),
  endpoint text not null check(endpoint ~ '^https://[a-z0-9]+[.]supabase[.]co/functions/v1/process-game-result$'),
  enabled boolean not null default false
);
alter table app_private.game_result_worker_config enable row level security;
revoke all on app_private.game_result_worker_config from public,anon,authenticated,service_role;

create function app_private.dispatch_game_results() returns integer
language plpgsql security definer set search_path='' set statement_timeout='15s' as $$
declare config app_private.game_result_worker_config; job record; request_id bigint; dispatched integer:=0;
begin
 select * into config from app_private.game_result_worker_config where singleton and enabled;
 if not found then return 0; end if;
 for job in select * from app_private.claim_game_result_dispatches(10) loop
   request_id:=net.http_post(url:=config.endpoint,
     headers:=jsonb_build_object('Content-Type','application/json','x-job-token',job.delivery_token::text),
     body:=jsonb_build_object('room_id',job.room_id),timeout_milliseconds:=10000);
   update app_private.game_result_jobs set last_request_id=request_id where room_id=job.room_id;
   dispatched:=dispatched+1;
 end loop;
 -- Queue history is operational, not the authoritative result/award record.
 delete from app_private.game_result_jobs where status in ('completed','failed')
   and finished_at<clock_timestamp()-interval '7 days';
 return dispatched;
end $$;
revoke all on function app_private.dispatch_game_results() from public,anon,authenticated,service_role;
-- No key/token in this command. Per-delivery capabilities are generated in the
-- private queue and expire/rotate; net requests are disposable, jobs are durable.
select cron.schedule('playmatch-game-results','* * * * *','select app_private.dispatch_game_results();');
