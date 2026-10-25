import {test} from 'node:test';
import assert from 'node:assert/strict';
import {handleResult} from '../../supabase/functions/finish-round/handler.mjs';
const room='00000000-0000-4000-8000-000000000001';
const owner='verified-user';
function request(body={room_id:room},token='Bearer valid') {return new Request('https://example.test',{method:'POST',headers:{Authorization:token},body:JSON.stringify(body)});}
function fixture({authError=false,prepareError=false,finalError=false,status='verify'}={}) {
  const calls=[]; const start=1800000000000;
  const prepared={status,nowMs:start+45000,room:{id:room,players:[owner,'other'],status:'awaiting_result',seed:42,
    engineVersion:'sky-hop-v1',inputProtocol:'sky-hop-input-v1',startsAtMs:start,endsAtMs:start+45000},
    streams:[owner,'other'].map(playerId=>({roomId:room,playerId,packets:Array.from({length:45},(_,sequence)=>({sequence,
      fromTick:sequence*120,throughTick:(sequence+1)*120,receivedAtMs:start+(sequence+1)*1000,flaps:[]}))}))};
  const factory=()=>({auth:{auth:{getUser:async()=>({data:{user:{id:owner,email_confirmed_at:'yes'}},error:authError})}},
    admin:{rpc:async(name,params)=>{calls.push({name,params});return name==='prepare_game_result'?{data:prepared,error:prepareError}:{data:{status:'completed',winner_id:null},error:finalError};}}});
  return {calls,prepared,factory};
}
test('verified identity and replay scores replace all client claims',async()=>{
  const f=fixture(); const res=await handleResult(request({room_id:room,p_actor:'attacker',score:999,streams:[]}),f.factory);
  assert.equal(res.status,200); assert.equal(f.calls[0].params.p_actor,owner);
  assert.equal(f.calls[1].params.p_low_score,0);assert.equal(f.calls[1].params.p_high_score,0);
  assert.deepEqual(await res.json(),{status:'completed',winner_id:null});
});
test('missing or invalid authentication never reaches result RPCs',async()=>{
  const f=fixture({authError:true});
  assert.equal((await handleResult(request({},''),f.factory)).status,401);
  assert.equal((await handleResult(request(),f.factory)).status,401);assert.equal(f.calls.length,0);
});
test('invalid room/body and oversized body are rejected',async()=>{
  const f=fixture();
  assert.equal((await handleResult(request({room_id:'wrong'}),f.factory)).status,400);
  assert.equal((await handleResult(request({room_id:room,padding:'x'.repeat(2048)}),f.factory)).status,413);
  assert.equal(f.calls.length,0);
});
test('pending and persisted results do not finalize a second time',async()=>{
  for(const status of ['pending','completed']) {
    const f=fixture({status}); f.prepared.streams=undefined; f.prepared.room=undefined;
    assert.equal((await handleResult(request(),f.factory)).status,200);assert.equal(f.calls.length,1);
  }
});
test('invalid trusted stream does not produce a result',async()=>{
  const f=fixture();f.prepared.streams[0].packets.pop();
  assert.equal((await handleResult(request(),f.factory)).status,409);assert.equal(f.calls.length,1);
});
test('membership and finalization race failures expose no private data',async()=>{
  for(const opts of [{prepareError:true},{finalError:true}]) {
    const f=fixture(opts); const res=await handleResult(request(),f.factory);
    assert.equal(res.status,409);assert.deepEqual(await res.json(),{error:'ROUND_UNAVAILABLE'});
  }
});
test('internal failures are redacted',async()=>{
  const res=await handleResult(request(),()=>{throw new Error('secret');});
  assert.equal(res.status,503);assert.deepEqual(await res.json(),{error:'RESULT_UNAVAILABLE'});
});
