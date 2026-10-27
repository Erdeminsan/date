-- pg_net is not relocatable. Re-register it outside public only with an empty
-- disposable transport queue; durable result jobs remain untouched.
lock table app_private.game_result_worker_config in access exclusive mode;
do $$
begin
 if exists(select 1 from net.http_request_queue) then
   raise exception 'TRANSPORT_QUEUE_NOT_EMPTY';
 end if;
end $$;
drop extension pg_net;
create extension pg_net with schema extensions;
