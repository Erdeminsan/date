import {test} from 'node:test';
import assert from 'node:assert/strict';
import {handleQueuedResult} from '../../supabase/functions/process-game-result/handler.mjs';
const room='00000000-0000-4000-8000-000000000001',token='00000000-0000-4000-8000-000000000002';
const request=(body={room_id:room},key=token)=>new Request('https://example.test',{method:'POST',
  headers:{'x-job-token':key},body:JSON.stringify(body)});
function fixture({denied=false,invalid=false,saveError=false,throwError=false}={}) {
  const calls=[];const start=1800000000000;
  const payload={status:'verify',nowMs:start+120000,resultDeadlineMs:start+86445000,
    room:{id:room,players:['a','b'],status:'awaiting_result',seed:42,engineVersion:'sky-hop-v1',
      inputProtocol:'sky-hop-input-v1',startsAtMs:start,endsAtMs:start+45000},
    streams:['a','b'].map(playerId=>({roomId:room,playerId,packets:Array.from({length:45},(_,sequence)=>({
      sequence,fromTick:sequence*120,throughTick:(sequence+1)*120,flaps:[],
      receivedAtMs:start+(sequence+1)*1000}))}))};
  if(invalid)payload.streams[0].packets.pop();
  return {calls,create:()=>({rpc:async(name,params)=>{
    calls.push({name,params});if(throwError)throw Error('secret');
    if(name==='prepare_queued_game_result')return {data:payload,error:denied};
    return {data:{status:'completed'},error:saveError};
  }})};
}
test('worker uses scoped delivery token and trusted replay, not body scores or actor',async()=>{
  const f=fixture();const r=await handleQueuedResult(request({room_id:room,actor:'attacker',low_score:999}),f.create);
  assert.equal(r.status,200);assert.deepEqual(await r.json(),{status:'completed'});
  assert.deepEqual(f.calls[0].params,{p_room:room,p_delivery:token});
  assert.equal(f.calls[1].params.p_low_score,0);assert.equal(f.calls[1].params.p_high_score,0);
  assert.equal('p_actor' in f.calls[1].params,false);
});
test('missing or malformed capability and oversized body never create admin',async()=>{
  let calls=0;const factory=()=>{calls++;throw Error('unexpected');};
  assert.equal((await handleQueuedResult(request({},''),factory)).status,401);
  assert.equal((await handleQueuedResult(request({room_id:room,pad:'a'.repeat(1024)}),factory)).status,413);
  assert.equal((await handleQueuedResult(request({room_id:'invalid'}),factory)).status,400);
  assert.equal(calls,0);
});
test('invalid, expired or rotated delivery is rejected without replay/finalization',async()=>{
  const f=fixture({denied:true});assert.equal((await handleQueuedResult(request(),f.create)).status,409);
  assert.equal(f.calls.length,1);
});
test('invalid trusted stream is terminally failed without awarding a score',async()=>{
  const f=fixture({invalid:true});assert.equal((await handleQueuedResult(request(),f.create)).status,409);
  assert.deepEqual(f.calls.map(c=>c.name),['prepare_queued_game_result','fail_queued_game_result']);
});
test('transport or finalize failures remain retryable and redact internals',async()=>{
  for(const config of [{saveError:true},{throwError:true}]) {
    const f=fixture(config);const r=await handleQueuedResult(request(),f.create);
    assert.equal(r.status,503);assert.deepEqual(await r.json(),{error:'RESULT_UNAVAILABLE'});
    assert.ok(!f.calls.some(c=>c.name==='fail_queued_game_result'));
  }
});
