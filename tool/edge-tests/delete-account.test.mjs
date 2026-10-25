import test from 'node:test';
import assert from 'node:assert/strict';
import { handleDelete } from '../../supabase/functions/delete-account/handler.mjs';

const user = { id: 'owner-id', email: 'owner@example.test', email_confirmed_at: '2026-01-01', is_anonymous: false };
function fixture(options = {}) {
  const calls = [];
  return { calls, clients: () => ({
    photos: {
      prepare: async id => { calls.push(['prepare',id]); if (options.lockFailure) throw Error('lock'); return 'lease'; },
      cleanup: async id => { calls.push(['cleanup',id]); if (options.cleanupFailure) throw Error('cleanup'); },
      restore: async (id,token) => { calls.push(['restore',id,token]); },
    },
    auth: { auth: {
      getUser: async token => { calls.push(['verify', token]); return { data: { user: options.user ?? user }, error: options.invalidToken }; },
      signInWithPassword: async args => { calls.push(['reauth', args.email]); return { data: { user: { id: options.otherId ?? user.id }, session: { access_token: 'reauth-token' } }, error: options.wrongPassword }; },
    } },
    admin: { auth: { admin: {
      signOut: async (token, scope) => { calls.push(['revoke', token, scope]); return { error: options.revokeFailure }; },
      deleteUser: async (id, soft) => { calls.push(['delete', id, soft]); return { error: options.deleteFailure }; },
    } } },
  }) };
}
const request = (body = { confirmation: 'DELETE', password: 'secret' }, auth = 'Bearer valid') => new Request('https://example.test/delete-account', {
  method: 'POST', headers: { Authorization: auth, 'Content-Type': 'application/json' }, body: JSON.stringify(body),
});
test('missing bearer is rejected without calling auth', async () => {
  const f=fixture(); assert.equal((await handleDelete(request(undefined,''),f.clients)).status,401); assert.equal(f.calls.length,0);
});
test('explicit confirmation is required', async () => {
  const f=fixture(); assert.equal((await handleDelete(request({password:'secret'}),f.clients)).status,400); assert.equal(f.calls.length,0);
});
test('invalid JWT never deletes', async () => {
  const f=fixture({invalidToken:true}); assert.equal((await handleDelete(request(),f.clients)).status,401); assert.deepEqual(f.calls.map(x=>x[0]),['verify']);
});
test('wrong password never revokes or deletes', async () => {
  const f=fixture({wrongPassword:true}); assert.equal((await handleDelete(request(),f.clients)).status,403); assert.deepEqual(f.calls.map(x=>x[0]),['verify','reauth']);
});
test('reauth must identify the same user', async () => {
  const f=fixture({otherId:'someone-else'}); assert.equal((await handleDelete(request(),f.clients)).status,403); assert.ok(!f.calls.some(x=>x[0]==='delete'));
});
test('deletes only the verified owner, ignoring client-supplied target', async () => {
  const f=fixture(); const res=await handleDelete(request({confirmation:'DELETE',password:'secret',user_id:'victim',email:'victim@example.test'}),f.clients);
  assert.equal(res.status,200); assert.deepEqual(f.calls,[['verify','valid'],['reauth',user.email],['prepare',user.id],['revoke','reauth-token','global'],['cleanup',user.id],['delete',user.id,false]]);
});
test('failed session revocation prevents deletion', async () => {
  const f=fixture({revokeFailure:true}); assert.equal((await handleDelete(request(),f.clients)).status,503); assert.ok(!f.calls.some(x=>x[0]==='delete'));
});
test('failed deletion is not reported as success', async () => {
  const f=fixture({deleteFailure:true}); const res=await handleDelete(request(),f.clients); assert.equal(res.status,503); assert.equal((await res.json()).error,'DELETE_FAILED');
});
test('malformed body does not create clients', async () => {
  const f=fixture(); const req=new Request('https://example.test',{method:'POST',headers:{Authorization:'Bearer valid'},body:'not-json'});
  assert.equal((await handleDelete(req,f.clients)).status,400); assert.equal(f.calls.length,0);
});
test('unexpected service errors are redacted', async () => {
  const res=await handleDelete(request(),()=>{throw new Error('secret-service-role');});
  assert.equal(res.status,503); assert.ok(!(await res.text()).includes('secret-service-role'));
});

test('photo cleanup failure preserves the account and releases its deletion lease', async () => {
  const f=fixture({cleanupFailure:true});
  assert.equal((await handleDelete(request(),f.clients)).status,503);
  assert.ok(!f.calls.some(x=>x[0]==='delete'));
  assert.deepEqual(f.calls.at(-1),['restore',user.id,'lease']);
});
test('another deletion in progress cannot revoke or delete', async () => {
  const f=fixture({lockFailure:true});
  assert.equal((await handleDelete(request(),f.clients)).status,503);
  assert.ok(!f.calls.some(x=>['revoke','cleanup','delete','restore'].includes(x[0])));
});
