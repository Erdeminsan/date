import { PGlite } from '@electric-sql/pglite';
import { readFile, readdir } from 'node:fs/promises';
import assert from 'node:assert/strict';

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
    await db.exec(await readFile(new URL(file, migrationDir), 'utf8'));
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
  await check('unmatching removes the pair and rooms, preserves quotas and ignores stale IDs', async () => {
    await asUser('a'); const match=(await scalar('select id from public.matches')).id;
    const room=(await scalar("select public.game_room_action($1,'invite') as r",[match])).r.room.id;
    await db.exec('reset role');
    const budget=(await scalar('select count(*)::int as n from app_private.like_events where actor_id=$1',[ids.a])).n;
    const invites=(await scalar('select count(*)::int as n from app_private.game_invite_events where user_id=$1',[ids.a])).n;
    await asUser('c'); await db.query('select public.unmatch($1)',[match]);
    await asUser('a'); assert.equal((await db.query('select id from public.matches')).rows.length,1);
    await db.query('select public.unmatch($1)',[match]);
    assert.equal((await db.query('select id from public.matches')).rows.length,0);
    assert.equal((await db.query('select id from public.game_rooms')).rows.length,0);
    assert.equal((await db.query('select * from public.likes')).rows.length,0);
    await assert.rejects(()=>db.query("select public.game_room_action($1,'accept',$2)",[match,room]),/ROOM_UNAVAILABLE/);
    await db.query('select public.unmatch($1)',[match]);
    await db.exec('reset role');
    assert.equal((await scalar('select count(*)::int as n from app_private.like_events where actor_id=$1',[ids.a])).n,budget);
    assert.equal((await scalar('select count(*)::int as n from app_private.game_invite_events where user_id=$1',[ids.a])).n,invites);
    await asUser('a'); assert.equal((await scalar('select public.like_profile($1) as id',[ids.b])).id,null);
    await asUser('b'); const fresh=(await scalar('select public.like_profile($1) as id',[ids.a])).id;
    assert.notEqual(fresh,match);
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
    // Delete a seen row and insert a newer row between page requests.
    const initial=(await db.query('select *,created_at::text as cursor_time from public.discover_page()')).rows.slice(0,20);
    const boundary=initial.at(-1);
    await db.exec('reset role');
    await db.query('delete from auth.users where id=$1',[initial[0].id]);
    const newest='10000000-0000-4000-8000-000000000066';
    targetIds.push(newest);
    await db.query('insert into auth.users(id,email_confirmed_at) values($1,now())',[newest]);
    await db.query("insert into public.profiles(id,display_name) values($1,'Newest')",[newest]);
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
    await assert.rejects(() => db.exec('select * from public.discover_page()'), /permission denied/);
    await assert.rejects(() => db.exec('select * from public.matches_page()'), /permission denied/);
    await assert.rejects(() => db.exec('select * from public.game_rooms'), /permission denied/);
    await assert.rejects(() => db.query('select public.unmatch($1)',[ids.a]), /permission denied/);
    await assert.rejects(() => db.query("select public.game_room_action($1,'read')",[ids.a]), /permission denied/);
    await assert.rejects(() => db.query('select public.like_profile($1)',[ids.a]), /permission denied/);
    await assert.rejects(() => db.query('select public.blocked_profiles()'), /permission denied/);
    await assert.rejects(() => db.query('select public.unblock_profile($1)',[ids.a]), /permission denied/);
    await assert.rejects(() => db.query('select app_private.like_profile($1)',[ids.a]), /permission denied/);
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
    for (const table of ['likes','matches','blocks','reports','game_rooms']) {
      assert.equal((await db.query(`select * from public.${table}`)).rows.length,0);
    }
    assert.equal((await db.query('select * from public.profiles')).rows.length,1);
    assert.equal((await db.query('select * from public.profile_details')).rows.length,1);
    await asUser('b');
    await assert.rejects(() => db.query('select * from public.blocked_profiles()'), /AUTH_REQUIRED/);
  });
  await check('every application table has RLS enabled', async () => {
    await db.exec('reset role');
    const rows=(await db.query("select relname,relrowsecurity from pg_class where relnamespace='public'::regnamespace and relkind='r'")).rows;
    assert.equal(rows.length,7); assert.ok(rows.every(r=>r.relrowsecurity));
  });
  console.log(`${passed} database contract checks passed.`);
} finally { await db.close(); }
