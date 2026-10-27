import { PGlite } from '@electric-sql/pglite';
import { readFile, readdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {verifyRound, INPUT_PROTOCOL} from '../../supabase/functions/_shared/round-verifier.mjs';

// Local PostgreSQL engine; auth.users and auth.uid are compatibility fixtures.
// This does not validate Supabase Auth email delivery or hosted configuration.
const db = new PGlite();
const ids = {
  a: '00000000-0000-4000-8000-000000000001',
  b: '00000000-0000-4000-8000-000000000002',
  c: '00000000-0000-4000-8000-000000000003',
  d: '00000000-0000-4000-8000-000000000004',
};
let passed = 0;
async function check(name, fn) { await fn(); passed++; console.log(`PASS ${name}`); }
async function asUser(name) {
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claim.sub', $1, false)", [ids[name]]);
  await db.exec('set role authenticated');
}
async function scalar(sql, args = []) { return (await db.query(sql, args)).rows[0]; }
async function save(name, date = '2000-01-01') {
  return db.query('select public.save_profile($1,$2::date,$3,$4,true)', [name,date,'Private city','Private interests']);
}
try {
  await db.exec(`
    create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;
    create schema auth;
    -- Storage service fixtures validate policies, not the hosted object API.
    create schema storage;
    create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text,unique(bucket_id,name));
    alter table storage.objects enable row level security;
    grant usage on schema storage to authenticated;
    grant select,insert,delete on storage.objects to authenticated;
    create table auth.users(id uuid primary key, email_confirmed_at timestamptz,
      is_anonymous boolean not null default false, deleted_at timestamptz, banned_until timestamptz);
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;
    $$;
    grant usage on schema auth to authenticated, anon;
    grant execute on function auth.uid() to authenticated, anon;
  `);
  for (const [name, id] of Object.entries(ids)) {
    await db.query('insert into auth.users(id,email_confirmed_at) values($1,$2)', [id, name === 'd' ? null : new Date().toISOString()]);
  }
  const migrationDir = new URL('../../supabase/migrations/', import.meta.url);
  for (const file of (await readdir(migrationDir)).filter(f => f.endsWith('.sql')).sort()) {
    const quotaMigration=file.endsWith('_durable_report_quota.sql');
    const reporter='99000000-0000-4000-8000-000000000040', target='99000000-0000-4000-8000-000000000041';
    if(quotaMigration) {
      await db.query('insert into auth.users(id,email_confirmed_at) values($1,now()),($2,now())',[reporter,target]);
      await db.query("insert into public.profiles(id,display_name) values($1,'Migration reporter'),($2,'Migration target')",[reporter,target]);
      await db.query("insert into public.reports(reporter_id,reported_id,reason,created_at) values($1,$2,'Recent report',now()),($1,$2,'Older report',now()-interval '25 hours')",[reporter,target]);
    }
    let migration=await readFile(new URL(file, migrationDir), 'utf8');
    if(file.endsWith('_game_result_worker_schedule.sql')) {
      // PGlite cannot run extension background workers. Stub only transport and
      // scheduling; execute the production dispatcher SQL unchanged.
      await db.exec(`create schema net;create schema cron;
        create table net.http_request_queue(id bigint generated always as identity, url text,body jsonb,headers jsonb);
        create function net.http_post(url text,body jsonb,headers jsonb,timeout_milliseconds integer) returns bigint
          language sql as $$ insert into net.http_request_queue(url,body,headers) values(url,body,headers) returning id $$;
        create table cron.jobs(name text,schedule text,command text);
        create function cron.schedule(text,text,text) returns bigint language sql as $$
          insert into cron.jobs values($1,$2,$3);select 1::bigint $$;`);
      migration=migration.replace(/^create extension if not exists (pg_cron|pg_net);$/gm,'');
    }
    if(file.endsWith('_result_worker_transport_hardening.sql')) {
      migration=migration.replace(/^drop extension pg_net;$/gm,'')
        .replace(/^create extension pg_net with schema extensions;$/gm,'');
    }
    await db.exec(migration);
    if(quotaMigration) await check('quota migration backfills only recent surviving reports', async()=>{
      assert.equal((await scalar('select count(*)::int as n from app_private.report_events where actor_id=$1',[reporter])).n,1);
      await db.query('delete from auth.users where id=$1',[target]);
      assert.equal((await scalar('select count(*)::int as n from app_private.report_events where actor_id=$1',[reporter])).n,1);
      await db.query('delete from auth.users where id=$1',[reporter]);
    });
  }
  await check('unconfirmed account cannot create a profile', async () => {
    await asUser('d'); await assert.rejects(() => save('Unconfirmed'), /AUTH_REQUIRED/);
  });
  await check('underage profile is rejected atomically', async () => {
    await asUser('a'); await assert.rejects(() => save('Minor','2020-01-01'), /ADULTS_ONLY/);
    assert.equal((await db.query('select * from public.profiles')).rows.length,0);
  });
  await asUser('a'); await save('Alice');
  await asUser('b'); await save('Bob');
  await asUser('c'); await save('Carol');
  await check('profiles are discoverable, private details are owner-only', async () => {
    await asUser('a');
    assert.equal((await db.query('select * from public.discover_profiles()')).rows.length, 2);
    const details = (await db.query('select * from public.profile_details')).rows;
    assert.equal(details.length,1); assert.equal(details[0].user_id,ids.a);
    assert.equal((await db.query('select * from public.profile_details where user_id=$1',[ids.b])).rows.length,0);
  });
  await check('clients cannot forge matches or directly edit profiles', async () => {
    await assert.rejects(() => db.query('insert into public.matches(user_low,user_high) values($1,$2)',[ids.a,ids.b]), /permission denied/);
    await assert.rejects(() => db.query("update public.profiles set display_name='Hacked' where id=$1",[ids.b]), /permission denied/);
  });
  await check('birth date cannot be changed after creation', async () => {
    await assert.rejects(() => save('Alice','1999-01-01'), /BIRTH_DATE_IMMUTABLE/);
  });
  await check('discovery age preferences are private, validated, inclusive and applied before pagination', async () => {
    await asUser('a');
    const get=async()=>(await scalar('select public.get_discovery_preferences() as r')).r;
    assert.deepEqual(await get(),{min_age:18,max_age:null});
    for(const [lo,hi] of [[17,null],[25,24],[18,100],[101,null],[null,30]])
      await assert.rejects(()=>db.query('select public.set_discovery_preferences($1,$2)',[lo,hi]),/INVALID_PREFERENCES/);
    await db.exec('reset role');
    await db.query("update public.profile_details set birth_date=current_date-interval '30 years' where user_id=$1",[ids.b]);
    await db.query("update public.profile_details set birth_date=current_date-interval '31 years' where user_id=$1",[ids.c]);
    await asUser('a');await db.query('select public.set_discovery_preferences(30,30)');
    assert.deepEqual(await get(),{min_age:30,max_age:30});
    const page=(await db.query('select * from public.discover_page()')).rows;
    assert.deepEqual(page.map(p=>p.id),[ids.b]);assert.equal('birth_date' in page[0],false);
    assert.deepEqual((await db.query('select * from public.discover_profiles()')).rows.map(p=>p.id),[ids.b]);
    await assert.rejects(()=>db.query('select * from app_private.discovery_preferences'),/permission denied/);
    await asUser('b');assert.deepEqual(await get(),{min_age:18,max_age:null});
    await asUser('a');await db.query('select public.set_discovery_preferences(31,null)');
    assert.deepEqual((await db.query('select * from public.discover_page()')).rows.map(p=>p.id),[ids.c]);
    await db.query('select public.set_discovery_preferences(18,null)');
    await db.exec('reset role');
    await db.query("update public.profile_details set birth_date='2000-01-01' where user_id=any($1::uuid[])",[[ids.b,ids.c]]);
    await asUser('a');
  });
  await check('one-sided like produces no match', async () => {
    assert.equal((await scalar('select public.like_profile($1) as id',[ids.b])).id,null);
    assert.equal((await db.query('select * from public.matches')).rows.length,0);
  });
  await check('incoming likes are not readable', async () => {
    await asUser('b'); assert.equal((await db.query('select * from public.likes')).rows.length,0);
  });
  await check('reciprocal like creates exactly one match; repeats are idempotent', async () => {
    const first = (await scalar('select public.like_profile($1) as id',[ids.a])).id;
    assert.ok(first);
    assert.equal((await scalar('select public.like_profile($1) as id',[ids.a])).id,first);
    assert.equal((await db.query('select * from public.matches')).rows.length,1);
  });
  await check('third party cannot read another pair match', async () => {
    await asUser('c'); assert.equal((await db.query('select * from public.matches')).rows.length,0);
  });
  await check('matches do not expose locked profile details', async () => {
    await asUser('b'); assert.equal((await db.query('select * from public.profile_details where user_id=$1',[ids.a])).rows.length,0);
  });
  await check('game invitations isolate participants and keep a single active room', async () => {
    await asUser('a');
    const match=(await scalar('select id from public.matches')).id;
    const call=async(action,room=null)=>(await scalar('select public.game_room_action($1,$2,$3) as result',[match,action,room])).result;
    const first=(await call('invite')).room;
    assert.equal((await call('invite')).room.id,first.id);
    await assert.rejects(()=>call('accept',first.id),/ROOM_ACTION_FORBIDDEN/);
    await assert.rejects(()=>db.query("update public.game_rooms set status='accepted'"),/permission denied/);
    await asUser('c');
    assert.equal((await db.query('select * from public.game_rooms')).rows.length,0);
    await assert.rejects(()=>call('read'),/ROOM_UNAVAILABLE/);
    await asUser('b');
    assert.equal((await call('invite')).room.id,first.id);
    const accepted=(await call('accept',first.id)).room;
    assert.equal(accepted.status,'accepted');
    assert.equal((await call('accept',first.id)).room.expires_at,accepted.expires_at);
    assert.equal((await call('cancel',first.id)).room.status,'cancelled');
    await asUser('a');
    const second=(await call('invite')).room;
    assert.notEqual(second.id,first.id);
    await call('cancel',first.id);
    assert.equal((await call('read')).room.id,second.id);
    await asUser('b');
    assert.equal((await call('decline',second.id)).room.status,'declined');
    await asUser('a');
    const third=(await call('invite')).room;
    await db.exec('reset role');
    await db.query("update public.game_rooms set expires_at=now()-interval '1 second' where id=$1",[third.id]);
    await asUser('b');
    assert.equal((await call('accept',third.id)).room.status,'expired');
    await db.exec('reset role');
    await db.query("update auth.users set banned_until=now()+interval '1 hour' where id=$1",[ids.a]);
    await asUser('b'); await assert.rejects(()=>call('read'),/ROOM_UNAVAILABLE/);
    assert.equal((await db.query('select * from public.game_rooms')).rows.length,0);
    await db.exec('reset role');
    await db.query('update auth.users set banned_until=null where id=$1',[ids.a]);
    await db.query("insert into app_private.game_invite_events(user_id) select $1 from generate_series(1,20)",[ids.a]);
    await asUser('a'); await assert.rejects(()=>call('invite'),/INVITE_LIMIT/);
    await db.exec('reset role'); await db.query('delete from app_private.game_invite_events where user_id=$1',[ids.a]);
    await asUser('a');
  });
  await check('both participants must be ready; shared schedule is immutable and expires', async () => {
    await asUser('a'); const match=(await scalar('select id from public.matches')).id;
    const call=async(action,room=null)=>(await scalar('select public.game_room_action($1,$2,$3) as r',[match,action,room])).r;
    const room=(await call('invite')).room;
    await asUser('b'); await call('accept',room.id);
    const one=await call('ready',room.id);
    assert.equal(one.my_ready,true);assert.equal(one.room.starts_at,null);assert.equal(one.room.status,'accepted');
    assert.equal((await call('ready',room.id)).room.starts_at,null);
    await asUser('c'); await assert.rejects(()=>call('ready',room.id),/ROOM_UNAVAILABLE/);
    await asUser('a'); const scheduled=(await call('ready',room.id)).room;
    assert.equal(scheduled.status,'countdown');
    assert.ok(scheduled.seed>=0 && scheduled.seed<=4294967295);
    assert.equal(scheduled.engine_version,'sky-hop-v1');
    assert.equal(new Date(scheduled.ends_at)-new Date(scheduled.starts_at),45000);
    assert.equal((await call('ready',room.id)).room.starts_at,scheduled.starts_at);
    assert.equal((await call('invite')).room.seed,scheduled.seed);
    await assert.rejects(()=>db.query('update public.game_rooms set seed=0 where id=$1',[room.id]),/permission denied/);
    await db.exec('reset role');
    await db.query("update public.game_rooms set starts_at=now()-interval '6 seconds',ends_at=now()+interval '39 seconds',expires_at=now()+interval '54 seconds' where id=$1",[room.id]);
    await asUser('b'); assert.equal((await call('read',room.id)).room.status,'running');
    await db.exec('reset role');
    await db.query("update public.game_rooms set starts_at=now()-interval '46 seconds',ends_at=now()-interval '1 second',expires_at=now()+interval '14 seconds' where id=$1",[room.id]);
    await asUser('a'); assert.equal((await call('read',room.id)).room.status,'awaiting_result');
    await db.exec('reset role');
    await db.query("update public.game_rooms set expires_at=now()-interval '1 second' where id=$1",[room.id]);
    await asUser('b'); assert.equal((await call('ready',room.id)).room.status,'expired');
    await asUser('a');
  });
  await check('game inputs require live participants, bounded ordered packets and immutable retries', async () => {
    await asUser('a'); const match=(await scalar('select id from public.matches')).id;
    const call=async(action,room=null)=>(await scalar('select public.game_room_action($1,$2,$3) as r',[match,action,room])).r;
    const room=(await call('invite')).room.id;
    const submit=async(sequence=0,flaps=[]) => (await scalar('select public.submit_game_input($1,$2,$3::integer[]) as r',[room,sequence,flaps])).r;
    await assert.rejects(()=>submit(),/ROOM_UNAVAILABLE/);
    await asUser('b'); await call('accept',room); await call('ready',room);
    await asUser('a'); await call('ready',room);
    await assert.rejects(()=>submit(),/INPUT_WINDOW/);
    await db.exec('reset role');
    await db.query("update public.game_rooms set starts_at=now()-interval '2 seconds',ends_at=now()+interval '43 seconds',expires_at=now()+interval '58 seconds' where id=$1",[room]);
    await asUser('c'); await assert.rejects(()=>submit(),/ROOM_UNAVAILABLE/);
    await asUser('a');
    await assert.rejects(()=>submit(1),/INPUT_SEQUENCE/);
    for(const flaps of [[-1],[120],[1,1],[2,1],[null],null,Array(121).fill(0)])
      await assert.rejects(()=>submit(0,flaps),/INVALID_INPUT/);
    for(const seq of [-1,45,null]) await assert.rejects(()=>submit(seq),/INVALID_INPUT/);
    const first=await submit(0,[0,119]);
    assert.deepEqual(await submit(0,[0,119]),first);
    await assert.rejects(()=>submit(0,[1]),/INPUT_CONFLICT/);
    assert.equal((await submit(1,[])).sequence,1);
    await assert.rejects(()=>db.query('select * from app_private.game_input_packets'),/permission denied/);
    await assert.rejects(()=>db.query('delete from app_private.game_input_packets'),/permission denied/);
    await asUser('b'); assert.equal((await submit()).sequence,0);
    await db.exec('reset role');
    assert.equal((await scalar('select count(*)::int as n from app_private.game_input_packets where room_id=$1',[room])).n,3);
    await db.query("update auth.users set banned_until=now()+interval '1 hour' where id=$1",[ids.b]);
    await asUser('a'); await assert.rejects(()=>submit(0,[0,119]),/ROOM_UNAVAILABLE/);
    await db.exec('reset role'); await db.query('update auth.users set banned_until=null where id=$1',[ids.b]);
    await asUser('a'); await call('cancel',room);
    await assert.rejects(()=>submit(0,[0,119]),/ROOM_UNAVAILABLE/);
  });
  await check('late input histories and unsupported protocols are refused', async () => {
    await asUser('a'); const match=(await scalar('select id from public.matches')).id;
    const call=async(action,room=null)=>(await scalar('select public.game_room_action($1,$2,$3) as r',[match,action,room])).r;
    const room=(await call('invite')).room.id;
    await asUser('b'); await call('accept',room); await call('ready',room);
    await asUser('a'); await call('ready',room);
    await db.exec('reset role');
    await db.query("update public.game_rooms set starts_at=now()-interval '6 seconds',ends_at=now()+interval '39 seconds',expires_at=now()+interval '54 seconds' where id=$1",[room]);
    await asUser('a'); await assert.rejects(()=>db.query('select public.submit_game_input($1,0,array[]::integer[])',[room]),/INPUT_WINDOW/);
    await db.exec('reset role');
    await db.query("update public.game_rooms set input_protocol='unknown' where id=$1",[room]);
    await asUser('a'); await assert.rejects(()=>db.query('select public.submit_game_input($1,0,array[]::integer[])',[room]),/ROOM_UNAVAILABLE/);
    await call('cancel',room);
  });
  await check('stored receipts feed the verifier; final retry is stable and expiry closes writes', async () => {
    await asUser('a'); const match=(await scalar('select id from public.matches')).id;
    const call=async(action,room=null)=>(await scalar('select public.game_room_action($1,$2,$3) as r',[match,action,room])).r;
    const room=(await call('invite')).room.id;
    await asUser('b'); await call('accept',room); await call('ready',room);
    await asUser('a'); await call('ready',room);
    await db.exec('reset role');
    // Seed trusted prior receipts instead of waiting 45 wall-clock seconds.
    await db.query("update public.game_rooms set status='awaiting_result',starts_at=now()-interval '45 seconds',ends_at=now(),expires_at=now()+interval '15 seconds' where id=$1",[room]);
    await db.query(`insert into app_private.game_input_packets(room_id,player_id,sequence,flaps,received_at)
      select r.id,p.id,n,array[]::integer[],r.starts_at+(n+1)*interval '1 second'
      from public.game_rooms r cross join unnest($2::uuid[]) p(id) cross join generate_series(0,43) n where r.id=$1`,[room,[ids.a,ids.b]]);
    const submit=async()=>(await scalar('select public.submit_game_input($1,44,array[]::integer[]) as r',[room])).r;
    const completed=[];
    for(const player of ['a','b']) {
      await asUser(player); const ack=await submit(); completed.push(ack);
      assert.deepEqual(await submit(),ack);
    }
    await db.exec('reset role');
    const r=await scalar(`select *,floor(extract(epoch from starts_at)*1000)::float8 as start_ms,
      floor(extract(epoch from ends_at)*1000)::float8 as end_ms,
      floor(extract(epoch from clock_timestamp())*1000)::float8 as now_ms from public.game_rooms where id=$1`,[room]);
    const packets=(await db.query(`select *,floor(extract(epoch from received_at)*1000)::float8 as received_ms
      from app_private.game_input_packets where room_id=$1 order by sequence`,[room])).rows;
    const result=verifyRound({room:{id:room,players:[ids.a,ids.b],status:r.status,seed:Number(r.seed),
      engineVersion:r.engine_version,inputProtocol:r.input_protocol,startsAtMs:r.start_ms,endsAtMs:r.end_ms},nowMs:r.now_ms,
      streams:[ids.a,ids.b].map(playerId=>({roomId:room,playerId,packets:packets.filter(p=>p.player_id===playerId).map(p=>({
        sequence:p.sequence,fromTick:p.sequence*120,throughTick:(p.sequence+1)*120,flaps:p.flaps,receivedAtMs:p.received_ms}))}))});
    assert.equal(r.input_protocol,INPUT_PROTOCOL); assert.equal(packets.length,90); assert.equal(result.winnerId,null);
    await db.query("update public.game_rooms set expires_at=now()-interval '1 second' where id=$1",[room]);
    await asUser('a'); await assert.rejects(()=>submit(),/ROOM_UNAVAILABLE/);
    await call('read',room);
  });
  await check('service results are idempotent; winner-only unlocks progress independently', async () => {
    await asUser('a'); const match=(await scalar('select id from public.matches')).id;
    async function roomFixture() {
      await db.exec('reset role');
      const r=await scalar(`insert into public.game_rooms(match_id,inviter_id,status,ready_low,ready_high,seed,starts_at,ends_at,expires_at)
        values($1,$2,'running',true,true,42,now()-interval '45 seconds',now(),now()+interval '15 seconds') returning id`,[match,ids.a]);
      await db.query(`insert into app_private.game_input_packets(room_id,player_id,sequence,flaps,received_at)
        select r.id,p.id,n,array[]::integer[],r.starts_at+(n+1)*interval '1 second' from public.game_rooms r
        cross join unnest($2::uuid[]) p(id) cross join generate_series(0,44) n where r.id=$1`,[r.id,[ids.a,ids.b]]);
      return r.id;
    }
    async function finish(room,low,high) {
      await db.exec('reset role; set role service_role');
      await db.query("select set_config('request.jwt.claim.sub','',false)");
      const prepared=(await scalar('select public.prepare_game_result($1,$2) as r',[room,ids.a])).r;
      assert.equal(prepared.status,'verify'); assert.equal(verifyRound(prepared).winnerId,null);
      // Trusted worker output fixture; Edge tests separately prove client claims cannot reach this RPC.
      return (await scalar('select public.finalize_game_result($1,$2,$3,$4,1,1) as r',[room,ids.a,low,high])).r;
    }
    const room=await roomFixture();
    await asUser('a');
    await assert.rejects(()=>db.query('select public.prepare_game_result($1,$2)',[room,ids.a]),/permission denied/);
    await assert.rejects(()=>db.query('select public.finalize_game_result($1,$2,9,0,0,0)',[room,ids.a]),/permission denied/);
    await assert.rejects(()=>db.query('select * from app_private.game_results'),/permission denied/);
    await asUser('c'); await assert.rejects(()=>db.query('select public.game_result($1)',[room]),/ROOM_UNAVAILABLE/);
    const first=await finish(room,2,1);
    assert.equal(first.unlock_level,1); assert.equal(first.city,'Private city'); assert.equal(first.interests,null);
    assert.equal('birth_date' in first,false); assert.equal('email' in first,false);
    const retry=(await scalar('select public.finalize_game_result($1,$2,0,9,1,1) as r',[room,ids.a])).r;
    assert.deepEqual(retry,first);
    await asUser('b'); const loser=(await scalar('select public.game_result($1) as r',[room])).r;
    assert.equal(loser.unlock_level,0); assert.equal(loser.city,null); assert.equal(loser.interests,null);
    const second=await finish(await roomFixture(),3,1);
    assert.equal(second.unlock_level,2); assert.equal(second.interests,'Private interests');
    const third=await roomFixture(); await finish(third,0,1);
    await asUser('b'); const b=(await scalar('select public.game_result($1) as r',[third])).r;
    assert.equal(b.unlock_level,1); assert.equal(b.interests,null);
    const tie=await finish(await roomFixture(),2,2); assert.equal(tie.winner_id,null); assert.equal(tie.unlock_level,2);
    await db.exec('reset role');
    assert.equal((await scalar('select count(*)::int as n from app_private.game_results where match_id=$1',[match])).n,4);
  });
  await check('match unlocks survive a new invitation, follow current profile, and reject outsiders/bans', async () => {
    await asUser('a'); const match=(await scalar('select id from public.matches')).id;
    const read=async()=>(await scalar('select public.match_unlocks($1) as r',[match])).r;
    const previous=await read(); assert.equal(previous.unlock_level,2);
    const room=(await scalar("select public.game_room_action($1,'invite') as r",[match])).r.room.id;
    assert.deepEqual(await read(),previous);
    assert.deepEqual(Object.keys(previous).sort(),['city','interests','unlock_level']);
    await asUser('b'); const b=await read(); assert.equal(b.unlock_level,1);assert.equal(b.interests,null);
    await asUser('c');await assert.rejects(()=>read(),/MATCH_UNAVAILABLE/);
    await db.exec('reset role');
    await db.query("update public.profile_details set city='New city' where user_id=$1",[ids.b]);
    await asUser('a');assert.equal((await read()).city,'New city');
    await db.exec('reset role');
    await db.query("update public.profile_details set city='Private city' where user_id=$1",[ids.b]);
    await db.query("update auth.users set banned_until=now()+interval '1 hour' where id=$1",[ids.b]);
    await asUser('a');await assert.rejects(()=>read(),/MATCH_UNAVAILABLE/);
    await db.exec('reset role');await db.query('update auth.users set banned_until=null where id=$1',[ids.b]);
    await asUser('a');await db.query("select public.game_room_action($1,'cancel',$2)",[match,room]);
  });
  await check('cancellation between verification and finalization grants nothing', async () => {
    await db.exec('reset role'); const match=(await scalar('select id from public.matches')).id;
    const r=await scalar(`insert into public.game_rooms(match_id,inviter_id,status,ready_low,ready_high,seed,starts_at,ends_at,expires_at)
      values($1,$2,'awaiting_result',true,true,42,now()-interval '45 seconds',now(),now()+interval '15 seconds') returning id`,[match,ids.a]);
    await db.query(`insert into app_private.game_input_packets(room_id,player_id,sequence,flaps,received_at)
      select r.id,p.id,n,array[]::integer[],r.starts_at+(n+1)*interval '1 second' from public.game_rooms r
      cross join unnest($2::uuid[]) p(id) cross join generate_series(0,44) n where r.id=$1`,[r.id,[ids.a,ids.b]]);
    await db.exec('set role service_role');
    assert.equal((await scalar('select public.prepare_game_result($1,$2) as r',[r.id,ids.a])).r.status,'verify');
    await db.exec('reset role');
    const restriction=(await scalar("insert into app_private.account_sanctions(user_id,duration_hours,reason,expires_at) values($1,24,'Test restriction',now()+interval '24 hours') returning id",[ids.b])).id;
    await db.exec('set role service_role');
    await db.query("select set_config('request.jwt.claim.sub','',false)");
    await assert.rejects(()=>db.query('select public.prepare_game_result($1,$2)',[r.id,ids.a]),/ROOM_UNAVAILABLE/);
    await assert.rejects(()=>db.query('select public.finalize_game_result($1,$2,1,0,0,0)',[r.id,ids.a]),/ROOM_UNAVAILABLE/);
    await db.exec('reset role');await db.query('delete from app_private.account_sanctions where id=$1',[restriction]);
    await asUser('a'); await db.query("select public.game_room_action($1,'cancel',$2)",[match,r.id]);
    await db.exec('reset role; set role service_role');
    await assert.rejects(()=>db.query('select public.finalize_game_result($1,$2,1,0,0,0)',[r.id,ids.a]),/ROOM_UNAVAILABLE/);
    await db.exec('reset role');
    assert.equal((await scalar('select count(*)::int as n from app_private.game_results where room_id=$1',[r.id])).n,0);
  });
  await check('messaging enforces membership, stable retry, cursor pages and durable limits', async () => {
    await asUser('a'); const match=(await scalar('select id from public.matches')).id;
    const nonce='10000000-0000-4000-8000-000000000001';
    const send=async(body,request=nonce)=>(await scalar('select public.send_message($1,$2,$3) as m',[match,request,body])).m;
    const first=await send('Hello');
    assert.equal((await send('Hello')).id,first.id);
    await assert.rejects(()=>send('Changed'),/MESSAGE_CONFLICT/);
    await assert.rejects(()=>send('   '),/INVALID_MESSAGE/);
    await assert.rejects(()=>send('a'.repeat(1001)),/INVALID_MESSAGE/);
    await assert.rejects(()=>db.query("update public.messages set body='forged'"),/permission denied/);
    await asUser('c');
    assert.equal((await db.query('select * from public.messages')).rows.length,0);
    await assert.rejects(()=>send('Spy'),/CHAT_UNAVAILABLE/);
    await assert.rejects(()=>db.query('select public.messages_page($1)',[match]),/CHAT_UNAVAILABLE/);
    await asUser('b');
    assert.equal((await scalar('select public.messages_page($1) as p',[match])).p.messages[0].body,'Hello');
    await db.exec('reset role');
    await db.query("insert into public.messages(match_id,sender_id,request_id,body) select $1,$2,gen_random_uuid(),'History '||n from generate_series(1,65) n",[match,ids.a]);
    await asUser('a');
    const page=(await scalar('select public.messages_page($1) as p',[match])).p;
    assert.equal(page.messages.length,50);assert.equal(page.has_more,true);
    const older=(await scalar('select public.messages_page($1,$2) as p',[match,page.messages.at(-1).id])).p;
    assert.equal(older.messages.length,16);assert.equal(older.has_more,false);
    assert.equal(new Set([...page.messages,...older.messages].map(m=>m.id)).size,66);
    await assert.rejects(()=>db.query('select public.messages_page($1,1,2)',[match]),/INVALID_CURSOR/);
    await db.exec('reset role');
    await db.query("insert into public.messages(match_id,sender_id,request_id,body) select $1,$2,gen_random_uuid(),'Catchup '||n from generate_series(1,65) n",[match,ids.b]);
    await asUser('a');
    const newer=(await scalar('select public.messages_page($1,null,$2) as p',[match,page.messages[0].id])).p;
    assert.equal(newer.messages.length,50);assert.equal(newer.has_more,true);
    const rest=(await scalar('select public.messages_page($1,null,$2) as p',[match,newer.messages.at(-1).id])).p;
    assert.equal(rest.messages.length,15);assert.equal(rest.has_more,false);
    await db.exec('reset role');
    await db.query('insert into app_private.message_events(user_id) select $1 from generate_series(1,59)',[ids.a]);
    await asUser('a');
    assert.equal((await send('Hello')).id,first.id);
    await assert.rejects(()=>send('Too fast','10000000-0000-4000-8000-000000000002'),/MESSAGE_LIMIT/);
    await db.exec('reset role');
    await db.query("update auth.users set banned_until=now()+interval '1 hour' where id=$1",[ids.b]);
    await asUser('a'); await assert.rejects(()=>db.query('select public.messages_page($1)',[match]),/CHAT_UNAVAILABLE/);
    await assert.rejects(()=>send('Hello'),/CHAT_UNAVAILABLE/);
    await db.exec('reset role'); await db.query('update auth.users set banned_until=null where id=$1',[ids.b]);
    await asUser('a');
  });
  await check('unmatching removes the pair and rooms, preserves quotas and ignores stale IDs', async () => {
    await asUser('a'); const match=(await scalar('select id from public.matches')).id;
    const room=(await scalar("select public.game_room_action($1,'invite') as r",[match])).r.room.id;
    await db.exec('reset role');
    const budget=(await scalar('select count(*)::int as n from app_private.like_events where actor_id=$1',[ids.a])).n;
    const messageBudget=(await scalar('select count(*)::int as n from app_private.message_events where user_id=$1',[ids.a])).n;
    const invites=(await scalar('select count(*)::int as n from app_private.game_invite_events where user_id=$1',[ids.a])).n;
    await asUser('c'); await db.query('select public.unmatch($1)',[match]);
    await asUser('a'); assert.equal((await db.query('select id from public.matches')).rows.length,1);
    await db.query('select public.unmatch($1)',[match]);
    assert.equal((await db.query('select id from public.matches')).rows.length,0);
    await assert.rejects(()=>db.query('select public.match_unlocks($1)',[match]),/MATCH_UNAVAILABLE/);
    assert.equal((await db.query('select id from public.game_rooms')).rows.length,0);
    assert.equal((await db.query('select id from public.messages')).rows.length,0);
    assert.equal((await db.query('select * from public.likes')).rows.length,0);
    await assert.rejects(()=>db.query("select public.game_room_action($1,'accept',$2)",[match,room]),/ROOM_UNAVAILABLE/);
    await db.query('select public.unmatch($1)',[match]);
    await db.exec('reset role');
    assert.equal((await scalar('select count(*)::int as n from app_private.like_events where actor_id=$1',[ids.a])).n,budget);
    assert.equal((await scalar('select count(*)::int as n from app_private.message_events where user_id=$1',[ids.a])).n,messageBudget);
    assert.equal((await scalar('select count(*)::int as n from app_private.game_invite_events where user_id=$1',[ids.a])).n,invites);
    await asUser('a'); assert.equal((await scalar('select public.like_profile($1) as id',[ids.b])).id,null);
    await asUser('b'); const fresh=(await scalar('select public.like_profile($1) as id',[ids.a])).id;
    assert.notEqual(fresh,match);
    assert.deepEqual((await scalar('select public.match_unlocks($1) as r',[fresh])).r,{unlock_level:0,city:null,interests:null});
    await asUser('a'); await db.query('select public.unmatch($1)',[match]);
    assert.equal((await scalar('select id from public.matches')).id,fresh);
    assert.equal((await db.query('select * from public.likes')).rows.length,1);
  });
  await check('blocking removes match and prevents future likes', async () => {
    await asUser('a'); await db.query('select public.block_profile($1)',[ids.b]);
    assert.equal((await db.query('select * from public.game_rooms')).rows.length,0);
    assert.equal((await db.query('select * from public.matches')).rows.length,0);
    await assert.rejects(() => db.query('select public.like_profile($1)',[ids.b]), /PROFILE_UNAVAILABLE/);
    await asUser('b'); await assert.rejects(() => db.query('select public.like_profile($1)',[ids.a]), /PROFILE_UNAVAILABLE/);
    assert.equal((await db.query('select * from public.profiles where id=$1',[ids.a])).rows.length,0);
    assert.equal((await db.query('select * from public.blocks')).rows.length,0);
  });
  await check('blocked list exposes only names of own blocked profiles', async () => {
    await asUser('a');
    assert.deepEqual((await db.query('select * from public.blocked_profiles()')).rows, [{id:ids.b, display_name:'Bob'}]);
    await asUser('c');
    assert.equal((await db.query('select * from public.blocked_profiles()')).rows.length,0);
  });
  await check('unblocking cannot remove another user block', async () => {
    await asUser('b'); await db.query('select public.unblock_profile($1)',[ids.a]);
    await assert.rejects(() => db.query('select public.like_profile($1)',[ids.a]), /PROFILE_UNAVAILABLE/);
    await db.query('select public.block_profile($1)',[ids.a]);
    await asUser('a'); await db.query('select public.unblock_profile($1)',[ids.b]);
    await assert.rejects(() => db.query('select public.like_profile($1)',[ids.b]), /PROFILE_UNAVAILABLE/);
  });
  await check('unblocking is idempotent and never restores an old match', async () => {
    await asUser('b'); await db.query('select public.unblock_profile($1)',[ids.a]);
    await db.query('select public.unblock_profile($1)',[ids.a]);
    assert.equal((await db.query('select * from public.matches')).rows.length,0);
    assert.equal((await db.query('select * from public.likes')).rows.length,0);
    assert.equal((await scalar('select public.like_profile($1) as id',[ids.a])).id,null);
  });
  await check('report records are visible only to their reporter', async () => {
    await asUser('a'); await db.query('select public.report_profile($1,$2)',[ids.b,'Unwanted contact']);
    assert.equal((await db.query('select * from public.reports')).rows.length,1);
    await asUser('b'); assert.equal((await db.query('select * from public.reports')).rows.length,0);
  });
  await check('moderation role gates private reports and records immutable, idempotent decisions', async () => {
    await asUser('a');const report=(await scalar('select id from public.reports limit 1')).id;
    assert.equal((await scalar('select public.moderation_access() as allowed')).allowed,false);
    await assert.rejects(()=>db.query('select * from public.moderation_reports_v3()'),/MODERATOR_REQUIRED/);
    await assert.rejects(()=>db.query("select public.review_report($1,'dismissed','A reason')",[report]),/MODERATOR_REQUIRED/);
    await assert.rejects(()=>db.query('insert into app_private.moderators(user_id) values($1)',[ids.a]),/permission denied/);
    await db.exec('reset role');await db.query('insert into app_private.moderators(user_id) values($1)',[ids.c]);
    await asUser('c');assert.equal((await scalar('select public.moderation_access() as allowed')).allowed,true);
    const rows=(await db.query('select * from public.moderation_reports_v3()')).rows;
    assert.equal(rows.length,1);assert.equal(rows[0].id,report);assert.equal('birth_date' in rows[0],false);
    for(const [decision,note] of [['ban','Valid note'],['dismissed','x'],[null,'Valid note']])
      await assert.rejects(()=>db.query('select public.review_report($1,$2,$3)',[report,decision,note]),/INVALID_REVIEW/);
    await db.query("select public.review_report($1,'escalated','Needs further investigation')",[report]);
    await db.query("select public.review_report($1,'escalated','Needs further investigation')",[report]);
    await assert.rejects(()=>db.query("select public.review_report($1,'dismissed','Different reason')",[report]),/REVIEW_CONFLICT/);
    assert.equal((await db.query('select * from public.moderation_reports_v3()')).rows.length,0);
    const reviewed=(await db.query("select * from public.moderation_reports_v3('reviewed')")).rows;
    assert.equal(reviewed.length,1);assert.equal(reviewed[0].review_note,'Needs further investigation');
    await assert.rejects(()=>db.query('delete from app_private.report_reviews'),/permission denied/);
    await asUser('a');assert.equal((await db.query('select * from public.reports')).rows.length,1);
    await assert.rejects(()=>db.query('select * from app_private.report_reviews'),/permission denied/);
    await db.exec('reset role');
    assert.equal((await scalar('select count(*)::int as n from app_private.report_reviews')).n,1);
    await db.query('insert into app_private.moderators(user_id) values($1)',[ids.a]);
    await asUser('a');assert.equal((await db.query("select * from public.moderation_reports_v3('reviewed')")).rows.length,0);
    await assert.rejects(()=>db.query("select public.review_report($1,'dismissed','My own case')",[report]),/REPORT_UNAVAILABLE/);
    await db.exec('reset role');
    const fixtures=(await db.query("insert into public.reports(reporter_id,reported_id,reason,created_at) select $1,$2,'Queue fixture','2020-01-01' from generate_series(1,25) returning id",[ids.a,ids.b])).rows.map(r=>r.id);
    await asUser('c');
    const first=(await db.query("select *,created_at::text as cursor_time from public.moderation_reports_v3()")).rows;
    assert.equal(first.length,21);const last=first[19];
    const next=(await db.query("select * from public.moderation_reports_v3('pending',$1,$2)",[last.cursor_time,last.id])).rows;
    assert.equal(next.length,5);assert.equal(new Set([...first.slice(0,20),...next].map(r=>r.id)).size,25);
    await db.exec('reset role');await db.query('delete from public.reports where id=any($1::uuid[])',[fixtures]);
    await db.exec('reset role');await db.query('delete from app_private.moderators');
    await asUser('c');await assert.rejects(()=>db.query("select * from public.moderation_reports_v3('reviewed')"),/MODERATOR_REQUIRED/);
    await asUser('a');
  });
  await check('sanctions require escalated independent review and reject privilege abuse', async () => {
    await asUser('a');
    await assert.rejects(()=>db.query('select * from public.moderation_sanctions_v2()'),/MODERATOR_REQUIRED/);
    await assert.rejects(()=>db.query('select * from app_private.account_sanctions'),/permission denied/);
    await assert.rejects(()=>db.query('select app_private.account_active($1)',[ids.b]),/permission denied/);
    await assert.rejects(()=>db.query("select public.suspend_reported_account($1,24,'Evidence reviewed','User-facing notice')",[ids.a]),/MODERATOR_REQUIRED/);
    await db.exec('reset role');await db.query('insert into app_private.moderators(user_id) values($1)',[ids.c]);
    const report=(await scalar("insert into public.reports(reporter_id,reported_id,reason) values($1,$2,'Sanction fixture') returning id",[ids.a,ids.b])).id;
    await asUser('c');
    await assert.rejects(()=>db.query("select public.suspend_reported_account($1,24,'Evidence reviewed','User-facing notice')",[report]),/ESCALATED_REVIEW_REQUIRED/);
    for(const hours of [0,25,169,null])await assert.rejects(()=>db.query("select public.suspend_reported_account($1,$2,'Evidence reviewed','User-facing notice')",[report,hours]),/INVALID_SANCTION/);
    await db.query("select public.review_report($1,'escalated','Evidence reviewed')",[report]);
    await db.exec('reset role');await db.query('insert into app_private.moderators(user_id) values($1),($2)',[ids.a,ids.b]);
    await asUser('a');await assert.rejects(()=>db.query("select public.suspend_reported_account($1,24,'Evidence reviewed','User-facing notice')",[report]),/REPORT_UNAVAILABLE/);
    await asUser('c');await assert.rejects(()=>db.query("select public.suspend_reported_account($1,24,'Evidence reviewed','User-facing notice')",[report]),/MODERATOR_TARGET_FORBIDDEN/);
    await db.exec('reset role');await db.query('delete from app_private.moderators where user_id<>$1',[ids.c]);
    await asUser('c');
    const id=(await scalar("select public.suspend_reported_account($1,24,'Evidence reviewed','User-facing notice') as id",[report])).id;
    const original=(await db.query('select * from public.moderation_sanctions_v2()')).rows[0];
    assert.equal(original.id,id);assert.equal(original.active,true);
    assert.equal((await scalar("select public.suspend_reported_account($1,24,' Evidence reviewed ','User-facing notice') as id",[report])).id,id);
    assert.deepEqual((await db.query('select * from public.moderation_sanctions_v2()')).rows[0],original);
    await assert.rejects(()=>db.query("select public.suspend_reported_account($1,168,'Evidence reviewed','User-facing notice')",[report]),/SANCTION_CONFLICT/);
    await asUser('b');await assert.rejects(()=>save('Bob'),/AUTH_REQUIRED/);
    await assert.rejects(()=>db.query('select * from public.matches_page()'),/AUTH_REQUIRED/);
    await asUser('a');assert.equal((await db.query('select * from public.profiles where id=$1',[ids.b])).rows.length,0);
    // Removing the report must not implicitly release the restriction.
    await db.exec('reset role');await db.query('delete from public.reports where id=$1',[report]);
    await asUser('b');await assert.rejects(()=>save('Bob'),/AUTH_REQUIRED/);
    await asUser('c');assert.equal((await db.query('select * from public.moderation_sanctions_v2()')).rows[0].id,id);
    await db.query("select public.lift_account_sanction($1,'Appeal evidence accepted')",[id]);
    await db.query("select public.lift_account_sanction($1,'Appeal evidence accepted')",[id]);
    await assert.rejects(()=>db.query("select public.lift_account_sanction($1,'Different reason')",[id]),/SANCTION_CONFLICT/);
    assert.equal((await db.query('select * from public.moderation_sanctions_v2()')).rows[0].active,false);
    await asUser('b');await save('Bob');
    await db.exec('reset role');await db.query('delete from app_private.account_sanctions where id=$1',[id]);await db.query('delete from app_private.moderators');
  });
  await check('independent restrictions survive reporter deletion and expire without a scheduler', async () => {
    await db.exec('reset role');
    await db.query('insert into app_private.moderators(user_id) values($1)',[ids.c]);
    const reporter='99000000-0000-4000-8000-000000000001';
    await db.query('insert into auth.users(id,email_confirmed_at) values($1,now())',[reporter]);
    await db.query("insert into public.profiles(id,display_name) values($1,'Reporter fixture')",[reporter]);
    const reports=(await db.query("insert into public.reports(reporter_id,reported_id,reason) select $1,$2,'Evidence fixture' from generate_series(1,2) returning id",[reporter,ids.b])).rows;
    const sanctions=[];
    await asUser('c');
    for(const r of reports){
      await db.query("select public.review_report($1,'escalated','Evidence reviewed')",[r.id]);
      sanctions.push((await scalar("select public.suspend_reported_account($1,24,'Evidence reviewed','User-facing notice') as id",[r.id])).id);
    }
    await db.exec('reset role');await db.query('delete from auth.users where id=$1',[reporter]);
    assert.equal((await scalar('select count(*)::int as n from app_private.account_sanctions where report_id is null and reporter_id is null')).n,2);
    await asUser('c');await db.query("select public.lift_account_sanction($1,'One case cleared')",[sanctions[0]]);
    await asUser('b');await assert.rejects(()=>save('Bob'),/AUTH_REQUIRED/);
    await db.exec('reset role');
    await db.query("update app_private.account_sanctions set created_at=now()-interval '25 hours',expires_at=now()-interval '1 hour' where id=$1",[sanctions[1]]);
    await asUser('b');await save('Bob');
    await db.exec('reset role');await db.query('delete from app_private.account_sanctions');await db.query('delete from app_private.moderators');
  });
  await check('restricted users can access only their own appeals; retry is immutable', async () => {
    await db.exec('reset role');
    const sid=(await scalar("insert into app_private.account_sanctions(user_id,reporter_id,duration_hours,reason,expires_at) values($1,$2,24,'Private moderator evidence',now()+interval '24 hours') returning id",[ids.b,ids.a])).id;
    await asUser('b');
    assert.equal((await scalar('select public.account_restricted() as restricted')).restricted,true);
    await assert.rejects(()=>save('Bob'),/AUTH_REQUIRED/);
    const rows=(await db.query('select * from public.own_sanctions_v2()')).rows;
    assert.equal(rows.length,1);assert.equal(rows[0].id,sid);assert.equal(rows[0].internal_reason,null);assert.equal(rows[0].display_name,null);
    assert.ok(!JSON.stringify(rows).includes('Private moderator evidence'));
    await assert.rejects(()=>db.query("select public.submit_sanction_appeal($1,'x')",[sid]),/INVALID_APPEAL/);
    await assert.rejects(()=>db.query('select * from app_private.sanction_appeals'),/permission denied/);
    const aid=(await scalar("select public.submit_sanction_appeal($1,'Please review this decision') as id",[sid])).id;
    assert.equal((await scalar("select public.submit_sanction_appeal($1,' Please review this decision ') as id",[sid])).id,aid);
    await assert.rejects(()=>db.query("select public.submit_sanction_appeal($1,'A replacement body')",[sid]),/APPEAL_CONFLICT/);
    await asUser('a');assert.equal((await db.query('select * from public.own_sanctions_v2()')).rows.length,0);
    await assert.rejects(()=>db.query("select public.submit_sanction_appeal($1,'Not my sanction')",[sid]),/SANCTION_UNAVAILABLE/);
    await assert.rejects(()=>db.query('select * from public.moderation_appeals_v4()'),/MODERATOR_REQUIRED/);
    await db.exec('reset role');await db.query('insert into app_private.moderators(user_id) values($1),($2)',[ids.a,ids.c]);
    await asUser('a');assert.equal((await db.query('select * from public.moderation_appeals_v4()')).rows.length,0);
    await assert.rejects(()=>db.query("select public.review_sanction_appeal($1,'lifted','Accepted response')",[aid]),/APPEAL_UNAVAILABLE/);
    await asUser('c');assert.equal((await db.query('select * from public.moderation_appeals_v4()')).rows[0].internal_reason,'Private moderator evidence');
    await assert.rejects(()=>db.query("select public.review_sanction_appeal($1,'unknown','Public response')",[aid]),/INVALID_APPEAL_REVIEW/);
    await assert.rejects(()=>db.query("select public.review_sanction_appeal($1,'lifted','x')",[aid]),/INVALID_APPEAL_REVIEW/);
    await db.query("select public.review_sanction_appeal($1,'lifted','Your appeal is accepted')",[aid]);
    await db.query("select public.review_sanction_appeal($1,'lifted','Your appeal is accepted')",[aid]);
    await assert.rejects(()=>db.query("select public.review_sanction_appeal($1,'upheld','Changed response')",[aid]),/APPEAL_REVIEW_CONFLICT/);
    assert.equal((await db.query('select * from public.moderation_appeals_v4()')).rows.length,0);
    assert.equal((await db.query('select * from public.moderation_appeals_v4(true)')).rows.length,1);
    await asUser('b');assert.equal((await scalar('select public.account_restricted() as restricted')).restricted,false);
    await save('Bob');const result=(await db.query('select * from public.own_sanctions_v2()')).rows[0];
    assert.equal(result.decision,'lifted');assert.equal(result.response,'Your appeal is accepted');assert.equal(result.active,false);
    await db.exec('reset role');await db.query('delete from app_private.account_sanctions where id=$1',[sid]);
    assert.equal((await scalar('select count(*)::int as n from app_private.sanction_appeals')).n,0);
    await db.query('delete from app_private.moderators');
  });
  await check('appeal decisions preserve independent restrictions and prior manual lift audit', async () => {
    await db.exec('reset role');await db.query('insert into app_private.moderators(user_id) values($1)',[ids.c]);
    const sanctions=(await db.query("insert into app_private.account_sanctions(user_id,duration_hours,reason,expires_at) select $1,24,'Case evidence',now()+interval '24 hours' from generate_series(1,2) returning id",[ids.b])).rows;
    await asUser('b');const appeals=[];
    for(const r of sanctions) appeals.push((await scalar("select public.submit_sanction_appeal($1,'Please reconsider') as id",[r.id])).id);
    await asUser('c');await db.query("select public.review_sanction_appeal($1,'upheld','The original decision is retained')",[appeals[0]]);
    await db.query("select public.lift_account_sanction($1,'Manually resolved case')",[sanctions[1].id]);
    await db.query("select public.review_sanction_appeal($1,'lifted','Already resolved; accepted')",[appeals[1]]);
    await db.exec('reset role');assert.equal((await scalar('select lift_reason from app_private.account_sanctions where id=$1',[sanctions[1].id])).lift_reason,'Manually resolved case');
    await asUser('b');assert.equal((await scalar('select public.account_restricted() as restricted')).restricted,true);
    await assert.rejects(()=>save('Bob'),/AUTH_REQUIRED/);
    await db.exec('reset role');await db.query('delete from app_private.moderators');
    await asUser('c');await assert.rejects(()=>db.query('select * from public.moderation_appeals_v4(true)'),/MODERATOR_REQUIRED/);
    await db.exec('reset role');await db.query('delete from app_private.account_sanctions');
  });
  await check('own and moderator appeal feeds paginate tied timestamps without exposing other accounts', async () => {
    await db.exec('reset role');await db.query('insert into app_private.moderators(user_id) values($1)',[ids.c]);
    const sanctions=(await db.query("insert into app_private.account_sanctions(user_id,duration_hours,reason,created_at,expires_at) select $1,24,'Historical case','2020-01-01','2020-01-02' from generate_series(1,25) returning id",[ids.b])).rows;
    await asUser('b');
    const first=(await db.query('select *,created_at::text as cursor_time from public.own_sanctions_v2()')).rows;const last=first[19];
    const next=(await db.query('select * from public.own_sanctions_v2($1,$2)',[last.cursor_time,last.id])).rows;
    assert.equal(first.length,21);assert.equal(next.length,5);assert.equal(new Set([...first.slice(0,20),...next].map(r=>r.id)).size,25);
    for(const r of sanctions)await db.query("select public.submit_sanction_appeal($1,'Historical appeal')",[r.id]);
    await db.exec('reset role');await db.query("update app_private.sanction_appeals set created_at='2020-01-01'");
    await asUser('c');const queue=(await db.query('select *,created_at::text as cursor_time from public.moderation_appeals_v4()')).rows;
    const tail=(await db.query('select * from public.moderation_appeals_v4(false,$1,$2)',[queue[19].cursor_time,queue[19].id])).rows;
    assert.equal(queue.length,21);assert.equal(tail.length,5);assert.equal(new Set([...queue.slice(0,20),...tail].map(r=>r.id)).size,25);
    await assert.rejects(()=>db.query('select * from public.moderation_appeals_v4(false,now(),null)'),/INVALID_CURSOR/);
    await db.exec('reset role');await db.query('delete from app_private.account_sanctions');await db.query('delete from app_private.moderators');
    await asUser('d');await assert.rejects(()=>db.query('select public.account_restricted()'),/AUTH_REQUIRED/);
    await db.exec('reset role');await db.query("update auth.users set banned_until=now()+interval '1 hour' where id=$1",[ids.b]);
    await asUser('b');await assert.rejects(()=>db.query('select * from public.own_sanctions_v2()'),/AUTH_REQUIRED/);
    await db.exec('reset role');await db.query('update auth.users set banned_until=null where id=$1',[ids.b]);
    await db.exec('set role anon');await assert.rejects(()=>db.query('select public.account_restricted()'),/permission denied/);
    await assert.rejects(()=>db.query('select * from public.own_sanctions_v2()'),/permission denied/);
    await assert.rejects(()=>db.query('select app_private.appeal_actor()'),/permission denied/);
  });
  await check('new restrictions require a separate immutable public notice without leaking evidence', async () => {
    await db.exec('reset role');await db.query('insert into app_private.moderators(user_id) values($1)',[ids.c]);
    const report=(await scalar("insert into public.reports(reporter_id,reported_id,reason) values($1,$2,'Confidential reporter detail') returning id",[ids.a,ids.b])).id;
    await asUser('c');await db.query("select public.review_report($1,'escalated','Private review notes')",[report]);
    await assert.rejects(()=>db.query("select public.suspend_reported_account($1,24,'Private evidence')",[report]),/PUBLIC_NOTICE_REQUIRED/);
    for(const notice of [null,'','    ','abcd','x'.repeat(1001)])
      await assert.rejects(()=>db.query("select public.suspend_reported_account($1,24,'Private evidence',$2)",[report,notice]),/PUBLIC_NOTICE_REQUIRED/);
    assert.equal((await db.query('select * from public.moderation_sanctions_v2()')).rows.length,0);
    const sid=(await scalar("select public.suspend_reported_account($1,24,'Private evidence',' Repeated unwanted contact ') as id",[report])).id;
    const original=(await db.query('select * from public.moderation_sanctions_v2()')).rows[0];
    assert.equal(original.public_notice,'Repeated unwanted contact');assert.equal(original.reason,'Private evidence');
    assert.equal((await scalar("select public.suspend_reported_account($1,24,'Private evidence','Repeated unwanted contact') as id",[report])).id,sid);
    await assert.rejects(()=>db.query("select public.suspend_reported_account($1,24,'Private evidence','Changed notice')",[report]),/SANCTION_CONFLICT/);
    assert.deepEqual((await db.query('select * from public.moderation_sanctions_v2()')).rows[0],original);
    await asUser('b');const own=(await db.query('select * from public.own_sanctions_v2()')).rows;
    assert.equal(own[0].public_notice,'Repeated unwanted contact');
    for(const secret of ['Private evidence','Private review notes','Confidential reporter detail'])assert.ok(!JSON.stringify(own).includes(secret));
    assert.equal(own[0].internal_reason,null);
    const legacy=(await db.query('select * from public.own_sanctions()')).rows[0];
    assert.equal(legacy.internal_reason,null);assert.equal('public_notice' in legacy,false);
    await db.query("select public.submit_sanction_appeal($1,'Please reconsider')",[sid]);
    await asUser('c');assert.equal((await db.query('select * from public.moderation_appeals_v4()')).rows[0].public_notice,'Repeated unwanted contact');
    await asUser('a');assert.equal((await db.query('select * from public.own_sanctions_v2()')).rows.length,0);
    await assert.rejects(()=>db.query('select * from public.moderation_sanctions_v2()'),/MODERATOR_REQUIRED/);
    await db.exec('reset role; set role anon');
    await assert.rejects(()=>db.query("select public.suspend_reported_account($1,24,'Private evidence','Public notice')",[report]),/permission denied/);
    await assert.rejects(()=>db.query('select * from public.moderation_appeals_v4()'),/permission denied/);
    await db.exec('reset role');await db.query('delete from public.reports where id=$1',[report]);
    await asUser('b');assert.equal((await db.query('select * from public.own_sanctions_v2()')).rows[0].public_notice,'Repeated unwanted contact');
    await db.exec('reset role');await db.query('delete from app_private.account_sanctions where id=$1',[sid]);await db.query('delete from app_private.moderators');
  });
  await check('message evidence is server-captured, scoped, idempotent and survives unmatching', async () => {
    ids.e='99000000-0000-4000-8000-000000000010';ids.f='99000000-0000-4000-8000-000000000011';
    await db.exec('reset role');await db.query('insert into auth.users(id,email_confirmed_at) values($1,now()),($2,now())',[ids.e,ids.f]);
    await asUser('e');await save('Evidence reporter');await asUser('f');await save('Evidence target');
    await db.exec('reset role');const match=(await scalar('insert into public.matches(user_low,user_high) values($1,$2) returning id',[ids.e,ids.f])).id;
    const message=(await scalar("insert into public.messages(match_id,sender_id,request_id,body) values($1,$2,gen_random_uuid(),'Original server message') returning id::text,created_at",[match,ids.f]));
    const other=(await scalar("insert into public.messages(match_id,sender_id,request_id,body) values($1,$2,gen_random_uuid(),'Second message') returning id::text",[match,ids.f])).id;
    const own=(await scalar("insert into public.messages(match_id,sender_id,request_id,body) values($1,$2,gen_random_uuid(),'Own message') returning id::text",[match,ids.e])).id;
    await asUser('c');await assert.rejects(()=>db.query("select public.report_message($1,$2,'Not my chat')",[match,message.id]),/CHAT_UNAVAILABLE/);
    await asUser('e');
    await assert.rejects(()=>db.query("select public.report_message($1,$2,'Own message reason')",[match,own]),/MESSAGE_UNAVAILABLE/);
    await assert.rejects(()=>db.query("select public.report_message($1,$2,'x')",[match,message.id]),/INVALID_REPORT/);
    await assert.rejects(()=>db.query("select public.report_message($1,999999999,'Missing message')",[match]),/MESSAGE_UNAVAILABLE/);
    await assert.rejects(()=>db.query('select * from app_private.report_message_evidence'),/permission denied/);
    const report=(await scalar("select public.report_message($1,$2,'Unwanted contact') as id",[match,message.id])).id;
    assert.equal((await scalar("select public.report_message($1,$2,' Unwanted contact ') as id",[match,message.id])).id,report);
    await assert.rejects(()=>db.query("select public.report_message($1,$2,'Changed reason')",[match,message.id]),/REPORT_CONFLICT/);
    await db.exec('reset role');const snapshot=(await scalar('select * from app_private.report_message_evidence where report_id=$1',[report]));
    assert.equal(snapshot.body,'Original server message');assert.equal(snapshot.message_created_at.toISOString(),message.created_at.toISOString());
    assert.equal((await scalar('select reported_id from public.reports where id=$1',[report])).reported_id,ids.f);
    // Mixed profile/message reports share the current 10/day report budget.
    await db.query("insert into public.reports(reporter_id,reported_id,reason) select $1,$2,'Quota fixture' from generate_series(1,9)",[ids.e,ids.f]);
    await asUser('e');await assert.rejects(()=>db.query("select public.report_message($1,$2,'One too many')",[match,other]),/REPORT_LIMIT/);
    assert.equal((await scalar("select public.report_message($1,$2,'Unwanted contact') as id",[match,message.id])).id,report);
    await db.exec('reset role');assert.equal((await scalar('select count(*)::int as n from app_private.report_message_evidence where reporter_id=$1',[ids.e])).n,1);
    assert.equal((await scalar('select count(*)::int as n from app_private.report_events where actor_id=$1',[ids.e])).n,10);
    await db.query('insert into app_private.moderators(user_id) values($1),($2)',[ids.c,ids.e]);
    await asUser('e');assert.ok(!(await db.query('select * from public.moderation_reports_v3()')).rows.some(r=>r.id===report));
    await db.exec('reset role');await db.query('delete from app_private.moderators where user_id=$1',[ids.e]);
    await asUser('e');await db.query('select public.unmatch($1)',[match]);
    assert.equal((await scalar("select public.report_message($1,$2,'Unwanted contact') as id",[match,message.id])).id,report);
    await assert.rejects(()=>db.query("select public.report_message($1,$2,'New inaccessible report')",[match,other]),/CHAT_UNAVAILABLE/);
    await asUser('c');const record=(await db.query('select * from public.moderation_reports_v3()')).rows.find(r=>r.id===report);
    assert.equal(record.message_body,'Original server message');assert.ok(record.evidence_captured_at);
    await db.query("select public.review_report($1,'escalated','Review selected message')",[report]);
    const sanction=(await scalar("select public.suspend_reported_account($1,24,'Internal evidence note','Repeated unwanted contact') as id",[report])).id;
    await asUser('f');await db.query("select public.submit_sanction_appeal($1,'Please reconsider this context')",[sanction]);
    const self=(await db.query('select * from public.own_sanctions_v2()')).rows[0];assert.equal('message_body' in self,false);
    await asUser('c');assert.equal((await db.query('select * from public.moderation_appeals_v4()')).rows.find(r=>r.sanction_id===sanction).message_body,'Original server message');
    await db.exec('reset role');await db.query('delete from app_private.moderators');
    await asUser('c');await assert.rejects(()=>db.query('select * from public.moderation_reports_v3()'),/MODERATOR_REQUIRED/);
    await db.exec('reset role; set role anon');await assert.rejects(()=>db.query("select public.report_message($1,$2,'Unauthorized request')",[match,message.id]),/permission denied/);
    await db.exec('reset role');await db.query('delete from auth.users where id=$1',[ids.f]);
    assert.equal((await scalar('select count(*)::int as n from app_private.report_message_evidence where report_id=$1',[report])).n,0);
    await db.query('delete from auth.users where id=$1',[ids.e]);delete ids.e;delete ids.f;
  });
  await check('photo evidence validates source/version/hash, hides bytes and cascades with the report', async () => {
    ids.e='99000000-0000-4000-8000-000000000020';ids.f='99000000-0000-4000-8000-000000000021';
    const path=`${ids.f}/30000000-0000-4000-8000-000000000001.jpg`;
    const bytes=Buffer.from('ffd8ffffd9','hex'),digest=createHash('sha256').update(bytes).digest('hex');
    const request='30000000-0000-4000-8000-000000000010';
    const args=[ids.e,ids.f,path,request,'Photo report reason',digest];
    const service=async()=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub','',false)");await db.exec('set role service_role');};
    const prepare=async(values=args)=>(await scalar('select public.prepare_photo_report($1,$2,$3,$4,$5,$6) as r',values)).r;
    let objectId;
    const finalize=async(extra={})=>(await scalar('select public.finalize_photo_report($1,$2,$3,$4,$5,$6,$7,$8) as r',[...args,extra.object??objectId,extra.encoded??bytes.toString('base64')])).r;
    await db.exec('reset role');await db.query('insert into auth.users(id,email_confirmed_at) values($1,now()),($2,now())',[ids.e,ids.f]);
    await asUser('e');await save('Photo reporter');await asUser('f');await save('Photo target');
    objectId=(await scalar("insert into storage.objects(bucket_id,name) values('profile-photos',$1) returning id",[path])).id;
    await db.query('select public.set_profile_photo($1)',[path]);
    await asUser('e');await assert.rejects(()=>prepare(),/permission denied/);await assert.rejects(()=>finalize(),/permission denied/);
    await assert.rejects(()=>db.query('select * from app_private.report_photo_evidence'),/permission denied/);
    await service();const prepared=await prepare();assert.equal(prepared.status,'capture');assert.equal(prepared.source_object_id,objectId);
    await assert.rejects(()=>finalize({object:request}),/PHOTO_CHANGED/);
    await assert.rejects(()=>finalize({encoded:Buffer.from('ffd8ff00ffd9','hex').toString('base64')}),/INVALID_IMAGE/);
    await assert.rejects(()=>finalize({encoded:'a'.repeat(2796205)}),/INVALID_IMAGE/);
    await asUser('f');await db.query('select public.set_profile_photo(null)');
    await service();await assert.rejects(()=>finalize(),/PHOTO_UNAVAILABLE/);
    await asUser('f');await db.query('select public.set_profile_photo($1)',[path]);
    await asUser('e');await db.query('select public.block_profile($1)',[ids.f]);
    await service();await assert.rejects(()=>prepare(),/PHOTO_UNAVAILABLE/);
    await asUser('e');await db.query('select public.unblock_profile($1)',[ids.f]);
    await db.exec('reset role');assert.equal((await scalar('select count(*)::int as n from public.reports where reporter_id=$1',[ids.e])).n,0);
    await db.query("insert into public.reports(reporter_id,reported_id,reason) select $1,$2,'Quota fixture' from generate_series(1,10)",[ids.e,ids.f]);
    await service();await assert.rejects(()=>prepare(),/REPORT_LIMIT/);
    await db.exec('reset role');await db.query('delete from public.reports where reporter_id=$1',[ids.e]);
    await service();await assert.rejects(()=>prepare(),/REPORT_LIMIT/);
    await db.exec('reset role');
    await db.query("update app_private.report_events set created_at=now()-interval '25 hours' where actor_id=$1",[ids.e]);
    await service();const saved=await finalize();assert.equal(saved.status,'completed');
    assert.deepEqual(await finalize(),saved);
    await assert.rejects(()=>prepare([...args.slice(0,4),'Different reason',digest]),/REPORT_CONFLICT/);
    await db.exec('reset role');
    assert.equal((await scalar('select count(*)::int as n from app_private.report_events where actor_id=$1',[ids.e])).n,1);
    await service();
    await asUser('f');await db.query('select public.set_profile_photo(null)');await db.query('delete from storage.objects where name=$1',[path]);
    await service();assert.deepEqual(await prepare(),saved);
    await db.exec('reset role');await db.query('insert into app_private.moderators(user_id) values($1),($2)',[ids.c,ids.e]);
    await asUser('e');assert.equal((await scalar('select public.moderation_photo_access($1) as allowed',[saved.report_id])).allowed,false);
    await assert.rejects(()=>db.query('select public.moderation_photo_evidence($1)',[saved.report_id]),/REPORT_UNAVAILABLE/);
    await asUser('c');const feed=(await db.query('select * from public.moderation_reports_v3()')).rows.find(r=>r.id===saved.report_id);
    assert.equal(feed.photo_report_id,saved.report_id);assert.equal('base64' in feed,false);
    assert.equal((await scalar('select public.moderation_photo_access($1) as allowed',[saved.report_id])).allowed,true);
    const evidence=(await scalar('select public.moderation_photo_evidence($1) as r',[saved.report_id])).r;
    assert.equal(evidence.base64,bytes.toString('base64'));assert.equal(evidence.sha256,digest);
    await db.query("select public.review_report($1,'escalated','Photo evidence checked')",[saved.report_id]);
    const sanction=(await scalar("select public.suspend_reported_account($1,24,'Internal photo review','Photo violates policy') as id",[saved.report_id])).id;
    await asUser('f');await db.query("select public.submit_sanction_appeal($1,'Please reconsider')",[sanction]);
    await asUser('c');assert.equal((await db.query('select * from public.moderation_appeals_v4()')).rows.find(r=>r.sanction_id===sanction).photo_report_id,saved.report_id);
    await db.exec('reset role');await db.query('delete from auth.users where id=$1',[ids.f]);
    await asUser('c');assert.equal((await scalar('select public.moderation_photo_access($1) as allowed',[saved.report_id])).allowed,false);
    await assert.rejects(()=>db.query('select public.moderation_photo_evidence($1)',[saved.report_id]),/REPORT_UNAVAILABLE/);
    await db.exec('reset role');assert.equal((await scalar('select count(*)::int as n from app_private.report_photo_evidence where report_id=$1',[saved.report_id])).n,0);
    await db.query('delete from app_private.moderators');await db.query('delete from auth.users where id=$1',[ids.e]);delete ids.e;delete ids.f;
    await db.exec('set role anon');await assert.rejects(()=>db.query('select public.moderation_photo_evidence($1)',[saved.report_id]),/permission denied/);
  });
  await check('hidden profile cannot receive or send new likes', async () => {
    await asUser('c');
    await db.query('select public.save_profile($1,$2,$3,$4,false)',['Carol','2000-01-01','Private city','Private interests']);
    await assert.rejects(() => db.query('select public.like_profile($1)',[ids.a]), /PROFILE_UNAVAILABLE/);
    await asUser('a');
    await assert.rejects(() => db.query('select public.like_profile($1)',[ids.c]), /PROFILE_UNAVAILABLE/);
  });
  await check('banned targets disappear from discovery, direct reads and matches', async () => {
    await asUser('a'); await db.query('select public.like_profile($1)',[ids.b]);
    assert.equal((await db.query('select * from public.matches')).rows.length,1);
    await db.exec('reset role');
    await db.query("update auth.users set banned_until=now()+interval '7 days' where id=$1",[ids.b]);
    await asUser('c');
    assert.ok(!(await db.query('select * from public.discover_profiles()')).rows.some(p => p.id === ids.b));
    await asUser('a');
    assert.equal((await db.query('select * from public.profiles where id=$1',[ids.b])).rows.length,0);
    assert.equal((await db.query('select * from public.matches')).rows.length,0);
    await assert.rejects(() => db.query('select public.like_profile($1)',[ids.b]), /PROFILE_UNAVAILABLE/);
    await asUser('b'); await assert.rejects(() => save('Banned'), /AUTH_REQUIRED/);
    await db.exec('reset role');
    await db.query("update auth.users set banned_until=now()-interval '1 second' where id=$1",[ids.b]);
    await asUser('a');
    assert.equal((await db.query('select * from public.matches')).rows.length,1);
  });
  await check('100-like budget survives blocking; repeats do not consume it', async () => {
    ids.e = '00000000-0000-4000-8000-000000000005';
    ids.f = '00000000-0000-4000-8000-000000000006';
    await db.exec('reset role');
    for (const id of [ids.e,ids.f]) await db.query('insert into auth.users(id,email_confirmed_at) values($1,now())',[id]);
    await asUser('e'); await save('Erin');
    await asUser('f'); await save('Finn');
    await asUser('e');
    for (let i=0; i<100; i++) {
      await db.query('select public.like_profile($1)',[ids.f]);
      // An idempotent retry must never spend another unit.
      await db.query('select public.like_profile($1)',[ids.f]);
      await db.query('select public.block_profile($1)',[ids.f]);
      await db.query('select public.unblock_profile($1)',[ids.f]);
    }
    await assert.rejects(() => db.query('select public.like_profile($1)',[ids.f]), /LIKE_LIMIT/);
    assert.equal((await db.query('select * from public.likes')).rows.length,0);
    await assert.rejects(() => db.exec('select * from app_private.like_events'), /permission denied/);
    await assert.rejects(() => db.exec('delete from app_private.like_events'), /permission denied/);
    await db.exec('reset role');
    assert.equal(Number((await scalar('select count(*) as count from app_private.like_events where actor_id=$1',[ids.e])).count),100);
    await db.query("update app_private.like_events set created_at=now()-interval '25 hours' where actor_id=$1",[ids.e]);
    await asUser('e'); await db.query('select public.like_profile($1)',[ids.f]);
    await db.exec('reset role');
    assert.equal(Number((await scalar('select count(*) as count from app_private.like_events where actor_id=$1',[ids.e])).count),1);
    await db.query('delete from auth.users where id in ($1,$2)',[ids.e,ids.f]);
    assert.equal(Number((await scalar('select count(*) as count from app_private.like_events where actor_id=$1',[ids.e])).count),0);
  });
  await check('keyset pages cover tied timestamps without overlap and enforce RLS', async () => {
    const targetIds = Array.from({length:65}, (_,i) => `10000000-0000-4000-8000-${String(i+1).padStart(12,'0')}`);
    await db.exec('reset role');
    for (let i=0; i<targetIds.length; i++) {
      await db.query('insert into auth.users(id,email_confirmed_at) values($1,now())',[targetIds[i]]);
      await db.query("insert into public.profiles(id,display_name,created_at) values($1,$2,'2020-01-01T00:00:00.123456Z')",[targetIds[i],`Page ${i}`]);
      await db.query("insert into public.profile_details(user_id,birth_date,city,interests) values($1,(current_date-case when $2::integer<30 then interval '30 years' else interval '50 years' end)::date,'City','')",[targetIds[i],i]);
      await db.query("insert into public.matches(id,user_low,user_high,created_at) values($1,$2,$3,'2020-01-01T00:00:00.123456Z')",[`20000000-0000-4000-8000-${String(i+1).padStart(12,'0')}`,ids.a,targetIds[i]]);
    }
    await db.query('update public.profiles set discoverable=false where id=$1',[targetIds[0]]);
    await db.query("update auth.users set banned_until=now()+interval '1 day' where id=$1",[targetIds[1]]);
    await asUser('a');
    await db.query('select public.block_profile($1)',[targetIds[2]]);
    await db.query('select public.like_profile($1)',[targetIds[3]]);
    async function pages(fn) {
      const seen=[]; let cursor=[null,null];
      for (let attempt=0; attempt<10; attempt++) {
        const rows=(await db.query(`select *, created_at::text as cursor_time from public.${fn}($1::timestamptz,$2::uuid)`,cursor)).rows;
        assert.ok(rows.length <= 21);
        const visible=rows.slice(0,20); seen.push(...visible);
        if (rows.length <=20) return seen;
        const last=visible.at(-1);
        // PostgreSQL timestamp text is preserved by the client.
        cursor=[last.cursor_time,last.id];
      }
      throw Error('Pagination did not terminate');
    }
    const discover=await pages('discover_page');
    assert.equal(new Set(discover.map(r=>r.id)).size,discover.length);
    assert.deepEqual(new Set(discover.filter(r=>targetIds.includes(r.id)).map(r=>r.id)),new Set(targetIds.slice(4)));
    await db.query('select public.set_discovery_preferences(30,30)');
    const filtered=await pages('discover_page');
    assert.deepEqual(new Set(filtered.filter(r=>targetIds.includes(r.id)).map(r=>r.id)),new Set(targetIds.slice(4,30)));
    await db.query('select public.set_discovery_preferences(18,null)');
    // Delete a seen row and insert a newer row between page requests.
    const initial=(await db.query('select *,created_at::text as cursor_time from public.discover_page()')).rows.slice(0,20);
    const boundary=initial.at(-1);
    await db.exec('reset role');
    await db.query('delete from auth.users where id=$1',[initial[0].id]);
    const newest='10000000-0000-4000-8000-000000000066';
    targetIds.push(newest);
    await db.query('insert into auth.users(id,email_confirmed_at) values($1,now())',[newest]);
    await db.query("insert into public.profiles(id,display_name) values($1,'Newest')",[newest]);
    await db.query("insert into public.profile_details(user_id,birth_date,city,interests) values($1,current_date-interval '30 years','City','')",[newest]);
    await asUser('a');
    const next=(await db.query('select * from public.discover_page($1::timestamptz,$2::uuid)',[boundary.cursor_time,boundary.id])).rows.slice(0,20);
    assert.deepEqual(next.map(r=>r.id),discover.slice(20,40).map(r=>r.id));
    const matches=await pages('matches_page');
    assert.equal(new Set(matches.map(r=>r.id)).size,matches.length);
    assert.equal(matches.filter(r=>targetIds.includes(r.other_id)).length,62);
    assert.equal(matches.find(r=>r.other_id===targetIds[0]).display_name,'Gizli profil');
    assert.ok(!matches.some(r=>r.other_id===targetIds[1] || r.other_id===targetIds[2]));
    await assert.rejects(() => db.query('select * from public.discover_page(now(),null)'), /INVALID_CURSOR/);
    await asUser('c');
    assert.equal((await db.query('select * from public.matches_page()')).rows.length,0);
    await db.exec('reset role');
    await db.query('delete from auth.users where id=any($1::uuid[])',[targetIds]);
  });
  await check('private photos obey ownership, visibility, block and quota policies', async () => {
    const paths=Array.from({length:4},(_,i)=>`${ids.a}/30000000-0000-4000-8000-${String(i+1).padStart(12,'0')}.jpg`);
    await asUser('a');
    await db.query("insert into storage.objects(bucket_id,name) values('profile-photos',$1)",[paths[0]]);
    await db.query('select public.set_profile_photo($1)',[paths[0]]);
    // Current photos cannot be deleted by a delayed cleanup request.
    await db.query('delete from storage.objects where name=$1',[paths[0]]);
    assert.equal((await db.query('select * from storage.objects where name=$1',[paths[0]])).rows.length,1);
    await asUser('b');
    assert.equal((await db.query('select * from storage.objects where name=$1',[paths[0]])).rows.length,1);
    await assert.rejects(() => db.query('select public.set_profile_photo($1)',[paths[0]]), /PHOTO_UNAVAILABLE/);
    await assert.rejects(() => db.query("insert into storage.objects(bucket_id,name) values('profile-photos',$1)",[paths[1]]), /row-level security/);
    await asUser('a');
    await db.query("select public.save_profile('Alice','2000-01-01','Private city','Private interests',false)");
    await asUser('b'); assert.equal((await db.query('select * from storage.objects')).rows.length,0);
    await asUser('a'); await save('Alice');
    await db.query('select public.block_profile($1)',[ids.c]);
    await asUser('c'); assert.equal((await db.query('select * from storage.objects')).rows.length,0);
    await asUser('a'); await db.query('select public.unblock_profile($1)',[ids.c]);
    await db.query("insert into storage.objects(bucket_id,name) values('profile-photos',$1),('profile-photos',$2)",[paths[1],paths[2]]);
    await assert.rejects(() => db.query("insert into storage.objects(bucket_id,name) values('profile-photos',$1)",[paths[3]]), /row-level security/);
    assert.equal((await scalar('select public.set_profile_photo($1) as old',[paths[1]])).old,paths[0]);
    await db.query('delete from storage.objects where name=$1',[paths[0]]);
    assert.equal((await db.query('select * from storage.objects where name=$1',[paths[0]])).rows.length,0);
    await db.query('select public.set_profile_photo(null)');
    await db.exec('delete from storage.objects');
  });
  await check('deletion leases are service-only and prevent photo writes until released', async () => {
    await asUser('a');
    await assert.rejects(() => db.query('select public.begin_account_deletion($1)',[ids.a]), /permission denied/);
    await db.exec('reset role; set role service_role');
    const token=(await scalar('select public.begin_account_deletion($1) as token',[ids.a])).token;
    await assert.rejects(() => db.query('select public.begin_account_deletion($1)',[ids.a]), /DELETE_IN_PROGRESS/);
    await asUser('a'); await assert.rejects(() => save('Alice'), /AUTH_REQUIRED/);
    await assert.rejects(() => db.query("insert into storage.objects(bucket_id,name) values('profile-photos',$1)",[`${ids.a}/30000000-0000-4000-8000-000000000001.jpg`]), /AUTH_REQUIRED/);
    await asUser('b'); assert.equal((await db.query('select * from public.profiles where id=$1',[ids.a])).rows.length,0);
    await db.exec('reset role; set role service_role');
    await db.query('select public.abort_account_deletion($1,$2)',[ids.a,ids.b]);
    await asUser('a'); await assert.rejects(() => save('Alice'), /AUTH_REQUIRED/);
    await db.exec('reset role; set role service_role');
    await db.query('select public.abort_account_deletion($1,$2)',[ids.a,token]);
    await asUser('a'); await save('Alice');
  });
  await check('anonymous role has neither data nor RPC access', async () => {
    await db.exec('reset role; set role anon');
    await assert.rejects(() => db.exec('select * from public.profiles'), /permission denied/);
    await assert.rejects(() => db.query('select public.match_unlocks($1)',[ids.a]), /permission denied/);
    await assert.rejects(() => db.query('select public.get_discovery_preferences()'), /permission denied/);
    await assert.rejects(() => db.query('select public.moderation_access()'), /permission denied/);
    await assert.rejects(() => db.query('select * from public.moderation_reports_v3()'), /permission denied/);
    await assert.rejects(() => db.query('select public.set_discovery_preferences(18,null)'), /permission denied/);
    await assert.rejects(() => db.exec('select * from public.discover_page()'), /permission denied/);
    await assert.rejects(() => db.exec('select * from public.matches_page()'), /permission denied/);
    await assert.rejects(() => db.exec('select * from public.game_rooms'), /permission denied/);
    await assert.rejects(() => db.query('select public.submit_game_input($1,0,array[]::integer[])',[ids.a]), /permission denied/);
    await assert.rejects(() => db.query('select public.messages_page($1)',[ids.a]), /permission denied/);
    await assert.rejects(() => db.query("select public.send_message($1,$2,'Hello')",[ids.a,ids.b]), /permission denied/);
    await assert.rejects(() => db.query('select public.unmatch($1)',[ids.a]), /permission denied/);
    await assert.rejects(() => db.query("select public.game_room_action($1,'read')",[ids.a]), /permission denied/);
    await assert.rejects(() => db.query('select public.like_profile($1)',[ids.a]), /permission denied/);
    await assert.rejects(() => db.query('select public.blocked_profiles()'), /permission denied/);
    await assert.rejects(() => db.query('select public.unblock_profile($1)',[ids.a]), /permission denied/);
    await assert.rejects(() => db.query('select app_private.like_profile($1)',[ids.a]), /permission denied/);
  });
  await check('report quota survives target deletion, expires, rolls back and is private', async () => {
    ids.q='99000000-0000-4000-8000-000000000030';
    ids.t='99000000-0000-4000-8000-000000000031';
    await db.exec('reset role');
    await db.query('insert into auth.users(id,email_confirmed_at) values($1,now()),($2,now())',[ids.q,ids.t]);
    await asUser('q');await save('Quota reporter');
    await asUser('t');await save('Quota target');
    await asUser('q');
    await assert.rejects(()=>db.query("select public.report_profile($1,'x')",[ids.t]),/check constraint/);
    await assert.rejects(()=>db.query('select * from app_private.report_events'),/permission denied/);
    await assert.rejects(()=>db.query('delete from app_private.report_events'),/permission denied/);
    await assert.rejects(()=>db.query('select app_private.record_report_event()'),/permission denied/);
    for(let i=0;i<10;i++) await db.query("select public.report_profile($1,'Quota test reason')",[ids.t]);
    await db.exec('reset role');
    assert.equal((await scalar('select count(*)::int as n from app_private.report_events where actor_id=$1',[ids.q])).n,10);
    await db.query('delete from auth.users where id=$1',[ids.t]);
    assert.equal((await scalar('select count(*)::int as n from public.reports where reporter_id=$1',[ids.q])).n,0);
    await asUser('q');
    await assert.rejects(()=>db.query("select public.report_profile($1,'New target reason')",[ids.a]),/REPORT_LIMIT/);
    await db.exec('reset role');
    await db.query("update app_private.report_events set created_at=now()-interval '25 hours' where actor_id=$1",[ids.q]);
    await asUser('q');
    await db.exec('begin');
    await db.query("select public.report_profile($1,'Rolled back report')",[ids.a]);
    await db.exec('rollback');
    await db.exec('reset role');
    assert.equal((await scalar("select count(*)::int as n from app_private.report_events where actor_id=$1 and created_at>now()-interval '1 day'",[ids.q])).n,0);
    await asUser('q');await db.query("select public.report_profile($1,'New daily report')",[ids.a]);
    await db.exec('reset role');
    assert.equal((await scalar('select count(*)::int as n from app_private.report_events where actor_id=$1',[ids.q])).n,1);
    await db.query('delete from auth.users where id=$1',[ids.q]);
    assert.equal((await scalar('select count(*)::int as n from app_private.report_events where actor_id=$1',[ids.q])).n,0);
    delete ids.q;delete ids.t;
  });
  await check('complete input queues durable work, resists cancel and finalizes after the old deadline', async()=>{
    ids.q='99000000-0000-4000-8000-000000000050';ids.t='99000000-0000-4000-8000-000000000051';
    await db.exec('reset role');
    await db.query('insert into auth.users(id,email_confirmed_at) values($1,now()),($2,now())',[ids.q,ids.t]);
    await asUser('q');await save('Queue player');await asUser('t');await save('Queue opponent');
    await db.exec('reset role');
    const match=(await scalar('insert into public.matches(user_low,user_high) values($1,$2) returning id',[ids.q,ids.t])).id;
    const room=(await scalar("insert into public.game_rooms(match_id,inviter_id,status,ready_low,ready_high,seed,starts_at,ends_at,expires_at) values($1,$2,'running',true,true,42,now()-interval '45 seconds',now(),now()+interval '15 seconds') returning id",[match,ids.q])).id;
    // Use one timestamp for the exact 45-second schedule constraint.
    await db.query("update public.game_rooms set ends_at=starts_at+interval '45 seconds' where id=$1",[room]);
    await db.query(`insert into app_private.game_input_packets(room_id,player_id,sequence,flaps,received_at)
      select r.id,p.id,n,array[]::integer[],r.starts_at+(n+1)*interval '1 second'
      from public.game_rooms r cross join unnest($2::uuid[]) p(id) cross join generate_series(0,44) n
      where r.id=$1 and not(p.id=$3 and n=44)`,[room,[ids.q,ids.t],ids.t]);
    assert.equal((await scalar('select count(*)::int as n from app_private.game_result_jobs where room_id=$1',[room])).n,0);
    await asUser('t');await db.exec('begin');
    await db.query('select public.submit_game_input($1,44,array[]::integer[])',[room]);
    await db.exec('rollback;reset role');
    assert.equal((await scalar('select count(*)::int as n from app_private.game_result_jobs where room_id=$1',[room])).n,0);
    assert.equal((await scalar('select count(*)::int as n from app_private.game_input_packets where room_id=$1',[room])).n,89);
    await asUser('t');await db.query('select public.submit_game_input($1,44,array[]::integer[])',[room]);
    await db.query('select public.submit_game_input($1,44,array[]::integer[])',[room]);
    await assert.rejects(()=>db.query('select * from app_private.game_result_jobs'),/permission denied/);
    await assert.rejects(()=>db.query('select public.prepare_queued_game_result($1,$2)',[room,ids.q]),/permission denied/);
    assert.equal((await scalar("select public.game_room_action($1,'cancel',$2) as r",[match,room])).r.room.status,'awaiting_result');
    await db.exec('reset role');
    assert.equal((await scalar('select count(*)::int as n from app_private.game_result_jobs where room_id=$1',[room])).n,1);
    await db.query("update public.game_rooms set starts_at=starts_at-interval '1 minute',ends_at=ends_at-interval '1 minute',expires_at=expires_at-interval '1 minute' where id=$1",[room]);
    await db.query("update app_private.game_input_packets set received_at=received_at-interval '1 minute' where room_id=$1",[room]);
    await db.query("update app_private.game_result_jobs set not_before=not_before-interval '1 minute',deadline=deadline-interval '1 minute',next_attempt_at=next_attempt_at-interval '1 minute' where room_id=$1",[room]);
    const job=(await db.query('select * from app_private.claim_game_result_dispatches()')).rows.find(j=>j.room_id===room);
    assert.ok(job.delivery_token);
    assert.ok(!(await db.query('select * from app_private.claim_game_result_dispatches()')).rows.some(j=>j.room_id===room));
    await db.exec('set role service_role');
    await assert.rejects(()=>db.query('select public.prepare_queued_game_result($1,$2)',[room,ids.q]),/JOB_UNAVAILABLE/);
    const prepared=(await scalar('select public.prepare_queued_game_result($1,$2) as r',[room,job.delivery_token])).r;
    assert.ok(prepared.nowMs>=prepared.room.endsAtMs+15000);
    const verified=verifyRound(prepared);
    const params=[room,job.delivery_token,...verified.results.map(r=>r.score),...verified.results.map(r=>r.hits)];
    assert.equal((await scalar('select public.finalize_queued_game_result($1,$2,$3,$4,$5,$6) as r',params)).r.status,'completed');
    await assert.rejects(()=>db.query('select public.finalize_queued_game_result($1,$2,$3,$4,$5,$6)',params),/JOB_UNAVAILABLE/);
    await db.exec('reset role');
    assert.equal((await scalar('select count(*)::int as n from app_private.game_results where room_id=$1',[room])).n,1);
    assert.equal((await scalar('select status from app_private.game_result_jobs where room_id=$1',[room])).status,'completed');
    await db.query('delete from auth.users where id in ($1,$2)',[ids.q,ids.t]);delete ids.q;delete ids.t;
  });
  await check('worker dispatch retries rotate capabilities, fail closed and expire overdue jobs', async()=>{
    ids.q='99000000-0000-4000-8000-000000000060';ids.t='99000000-0000-4000-8000-000000000061';
    await db.exec('reset role');
    await db.query('insert into auth.users(id,email_confirmed_at) values($1,now()),($2,now())',[ids.q,ids.t]);
    await asUser('q');await save('Worker player');await asUser('t');await save('Worker opponent');
    await db.exec('reset role');
    const match=(await scalar('insert into public.matches(user_low,user_high) values($1,$2) returning id',[ids.q,ids.t])).id;
    async function makeRoom(){
      const room=(await scalar("insert into public.game_rooms(match_id,inviter_id,status,ready_low,ready_high,seed,starts_at,ends_at,expires_at) values($1,$2,'awaiting_result',true,true,42,now()-interval '1 minute',now()-interval '15 seconds',now()+interval '24 hours') returning id",[match,ids.q])).id;
      await db.query(`insert into app_private.game_input_packets(room_id,player_id,sequence,flaps,received_at)
        select r.id,p.id,n,array[]::integer[],r.starts_at+(n+1)*interval '1 second'
        from public.game_rooms r cross join unnest($2::uuid[]) p(id) cross join generate_series(0,44) n where r.id=$1`,[room,[ids.q,ids.t]]);
      await db.query('select app_private.enqueue_complete_round($1)',[room]);return room;
    }
    const room=await makeRoom();
    assert.equal((await scalar('select app_private.dispatch_game_results() as n')).n,0);
    await db.query("insert into app_private.game_result_worker_config(endpoint,enabled) values('https://test.supabase.co/functions/v1/process-game-result',true)");
    assert.equal((await scalar('select app_private.dispatch_game_results() as n')).n,1);
    const req=(await scalar('select * from net.http_request_queue order by id desc limit 1'));
    assert.equal(req.body.room_id,room);const first=req.headers['x-job-token'];
    assert.equal((await scalar('select app_private.dispatch_game_results() as n')).n,0);
    await db.query("update app_private.game_result_jobs set next_attempt_at=now()-interval '1 second' where room_id=$1",[room]);
    await db.exec('set role service_role');
    await assert.rejects(()=>db.query('select public.prepare_queued_game_result($1,$2)',[room,first]),/JOB_UNAVAILABLE/);
    await db.exec('reset role');
    assert.equal((await scalar('select app_private.dispatch_game_results() as n')).n,1);
    const second=(await scalar('select delivery_token from app_private.game_result_jobs where room_id=$1',[room])).delivery_token;
    assert.notEqual(first,second);
    await db.exec('set role service_role');
    await assert.rejects(()=>db.query('select public.prepare_queued_game_result($1,$2)',[room,first]),/JOB_UNAVAILABLE/);
    await db.exec('reset role');
    await db.query("update auth.users set banned_until=now()+interval '1 hour' where id=$1",[ids.t]);
    await db.exec('set role service_role');
    await assert.rejects(()=>db.query('select public.finalize_queued_game_result($1,$2,1,0,0,0)',[room,second]),/ROOM_UNAVAILABLE/);
    await db.exec('reset role');await db.query('update auth.users set banned_until=null where id=$1',[ids.t]);
    await db.exec('set role service_role');await db.query('select public.fail_queued_game_result($1,$2)',[room,second]);
    await db.exec('reset role');
    assert.equal((await scalar('select status from public.game_rooms where id=$1',[room])).status,'expired');
    assert.equal((await scalar('select count(*)::int as n from app_private.game_results where room_id=$1',[room])).n,0);
    const raced=await makeRoom();
    const racedJob=(await db.query('select * from app_private.claim_game_result_dispatches()')).rows.find(j=>j.room_id===raced);
    await db.exec('set role service_role');
    await db.query('select public.prepare_queued_game_result($1,$2)',[raced,racedJob.delivery_token]);
    await db.query('select public.finalize_game_result($1,$2,0,0,0,0)',[raced,ids.q]);
    await assert.rejects(()=>db.query('select public.finalize_queued_game_result($1,$2,1,0,0,0)',[raced,racedJob.delivery_token]),/JOB_UNAVAILABLE/);
    await db.exec('reset role');
    assert.equal((await scalar('select count(*)::int as n from app_private.game_results where room_id=$1',[raced])).n,1);
    const overdue=await makeRoom();
    await db.query("update app_private.game_result_jobs set deadline=now()-interval '1 second' where room_id=$1",[overdue]);
    assert.equal((await scalar('select app_private.dispatch_game_results() as n')).n,0);
    assert.equal((await scalar('select last_error from app_private.game_result_jobs where room_id=$1',[overdue])).last_error,'deadline_exceeded');
    assert.equal((await scalar('select status from public.game_rooms where id=$1',[overdue])).status,'expired');
    const removed=await makeRoom();
    const delivery=(await db.query('select * from app_private.claim_game_result_dispatches()')).rows.find(j=>j.room_id===removed);
    await asUser('q');await db.query('select public.block_profile($1)',[ids.t]);
    await db.exec('reset role;set role service_role');
    await assert.rejects(()=>db.query('select public.prepare_queued_game_result($1,$2)',[removed,delivery.delivery_token]),/JOB_UNAVAILABLE/);
    await db.exec('reset role');
    assert.equal((await scalar('select count(*)::int as n from app_private.game_result_jobs where room_id=$1',[removed])).n,0);
    await db.query('delete from app_private.game_result_worker_config');
    await db.query('delete from auth.users where id in ($1,$2)',[ids.q,ids.t]);delete ids.q;delete ids.t;
  });
  await check('deleted user cannot use a stale user id', async () => {
    await db.exec('reset role'); await db.query('delete from auth.users where id=$1',[ids.c]);
    await asUser('c'); await assert.rejects(() => save('Carol'), /AUTH_REQUIRED/);
  });
  await check('deleting an auth account cascades its profile and relationship records', async () => {
    await asUser('a'); await db.query('select public.like_profile($1)',[ids.b]);
    assert.equal((await db.query('select * from public.matches')).rows.length,1);
    await db.exec('reset role');
    await db.query('delete from auth.users where id=$1',[ids.b]);
    for (const table of ['likes','matches','blocks','reports','game_rooms','messages']) {
      assert.equal((await db.query(`select * from public.${table}`)).rows.length,0);
    }
    assert.equal((await db.query('select * from app_private.game_input_packets')).rows.length,0);
    assert.equal((await db.query('select * from app_private.game_results')).rows.length,0);
    assert.equal((await db.query('select * from public.profiles')).rows.length,1);
    assert.equal((await db.query('select * from public.profile_details')).rows.length,1);
    await asUser('b');
    await assert.rejects(() => db.query('select * from public.blocked_profiles()'), /AUTH_REQUIRED/);
  });
  await check('profile request identity deduplicates before quota and rejects payload conflicts', async()=>{
    await db.exec('reset role');
    ids.r='99000000-0000-4000-8000-000000000071'; ids.s='99000000-0000-4000-8000-000000000072';
    await db.query('insert into auth.users(id,email_confirmed_at) values($1,now()),($2,now())',[ids.r,ids.s]);
    await asUser('r'); await save('Reporter'); await asUser('s'); await save('Target'); await asUser('r');
    const request='99000000-0000-4000-8000-000000000073';
    const call=(target,reason,key=request)=>db.query('select public.report_profile_once($1,$2,$3) as id',[target,reason,key]);
    const first=(await call(ids.s,'Valid report')).rows[0].id;
    assert.equal((await call(ids.s,'  Valid report  ')).rows[0].id,first);
    await assert.rejects(()=>call(ids.s,'Changed reason'),/REPORT_CONFLICT/);
    await assert.rejects(()=>call(ids.a,'Valid report'),/REPORT_CONFLICT/);
    await assert.rejects(()=>call(ids.s,'Valid report',null),/INVALID_REPORT/);
    await assert.rejects(()=>call(ids.s,'x'),/INVALID_REPORT/);
    for(let i=0;i<9;i++)await db.query("select public.report_profile($1,'Legacy report')",[ids.s]);
    assert.equal((await call(ids.s,'Valid report')).rows[0].id,first);
    await assert.rejects(()=>call(ids.s,'Valid report','99000000-0000-4000-8000-000000000074'),/REPORT_LIMIT/);
    await db.exec('reset role');
    assert.equal((await scalar('select count(*)::int as n from app_private.report_events where actor_id=$1',[ids.r])).n,10);
    assert.equal((await scalar('select count(*)::int as n from public.reports where reporter_id=$1',[ids.r])).n,10);
    await asUser('s');
    assert.equal((await db.query('select * from public.reports where profile_request_id=$1',[request])).rows.length,0);
    const other=(await call(ids.r,'Different actor')).rows[0].id; assert.notEqual(other,first);
    await db.exec('reset role;set role anon');
    await assert.rejects(()=>call(ids.s,'Valid report'),/permission denied/);
    await db.exec('reset role');
    await db.query('delete from auth.users where id in ($1,$2)',[ids.r,ids.s]);
    assert.equal((await scalar('select count(*)::int as n from public.reports where profile_request_id=$1',[request])).n,0);
  });
  await check('every application table has RLS enabled', async () => {
    await db.exec('reset role');
    const rows=(await db.query("select relname,relrowsecurity from pg_class where relnamespace='public'::regnamespace and relkind='r'")).rows;
    assert.equal(rows.length,8); assert.ok(rows.every(r=>r.relrowsecurity));
  });
  console.log(`${passed} database contract checks passed.`);
} finally { await db.close(); }
