import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {verifyRound, INPUT_PROTOCOL} from '../../supabase/functions/_shared/round-verifier.mjs';
const vectors = JSON.parse(readFileSync(new URL('../game-tests/vectors.json', import.meta.url)));
const winner = vectors.find(v => v.checkpoints.at(-1).score > 0);
function fixture() {
  const startsAtMs = 1800000000000;
  return {
    nowMs: startsAtMs + 45000,
    room: {id:'room-a', players:['a','b'], status:'awaiting_result', seed:winner.seed,
      engineVersion:'sky-hop-v1', inputProtocol:INPUT_PROTOCOL,
      startsAtMs, endsAtMs:startsAtMs + 45000},
    streams: ['a','b'].map(playerId => ({roomId:'room-a', playerId,
      packets:Array.from({length:45}, (_,sequence) => ({sequence,
        fromTick:sequence*120, throughTick:(sequence+1)*120,
        receivedAtMs:startsAtMs+(sequence+1)*1000,
        flaps:playerId === 'a' ? winner.inputs.filter(t=>t>=sequence*120 && t<(sequence+1)*120) : []}))}))
  };
}
function reject(change, message) {
  const f=fixture(); change(f); assert.throws(()=>verifyRound(f), message);
}
test('replays trusted streams, ignores claimed scores and leaves input unchanged',()=>{
  const f=fixture(); f.streams[1].score=999999;
  const before=structuredClone(f); const result=verifyRound(f);
  assert.equal(result.winnerId,'a');
  assert.equal(result.results[0].score,winner.checkpoints.at(-1).score);
  assert.equal(result.results[0].hits,winner.checkpoints.at(-1).hits);
  assert.deepEqual(f,before); assert.deepEqual(verifyRound(f),result);
});
test('equal scores have no winner and stream ordering does not assign ownership',()=>{
  const f=fixture(); f.streams[1].packets=structuredClone(f.streams[0].packets);
  f.streams.reverse(); assert.equal(verifyRound(f).winnerId,null);
});
test('requires both distinct participants in the same room',()=>{
  reject(f=>f.streams.pop(),/streams/);
  reject(f=>f.streams[1].playerId='a',/player stream/);
  reject(f=>f.streams[1].playerId='intruder',/player stream/);
  reject(f=>f.streams[1].roomId='old-room',/stream room/);
  reject(f=>f.room.players[1]='a',/players/);
});
test('rejects incomplete, excessive, reordered and overlapping packets',()=>{
  reject(f=>f.streams[0].packets.pop(),/incomplete/);
  reject(f=>f.streams[0].packets.push(f.streams[0].packets[0]),/incomplete/);
  reject(f=>f.streams[0].packets.reverse(),/sequence/);
  reject(f=>f.streams[0].packets[1].fromTick=119,/sequence/);
  reject(f=>f.streams[0].packets[1].throughTick=241,/sequence/);
});
test('rejects invalid and duplicate taps or taps from another interval',()=>{
  for(const flaps of [[-1],[120],[1,1],[2,1],[0.5],[NaN],null,Array(121).fill(0)])
    reject(f=>f.streams[0].packets[0].flaps=flaps,/input/);
});
test('accepts receipt tolerance boundaries and rejects either side',()=>{
  const f=fixture(); f.streams[0].packets[0].receivedAtMs=f.room.startsAtMs+750;
  verifyRound(f);
  reject(f=>f.streams[0].packets[0].receivedAtMs=f.room.startsAtMs+749,/window/);
  const delayed=fixture(); delayed.nowMs+=4000;
  for(const s of delayed.streams) for(const p of s.packets) p.receivedAtMs+=4000;
  verifyRound(delayed);
  reject(f=>{f.nowMs+=4001;for(const s of f.streams)for(const p of s.packets)p.receivedAtMs+=4001;},/window/);
});
test('cannot submit a complete history at the end of a round',()=>{
  reject(f=>{for(const s of f.streams)for(const p of s.packets)p.receivedAtMs=f.nowMs;},/window/);
});
test('rejects decreasing, future and noninteger server receipt times',()=>{
  reject(f=>f.streams[0].packets[1].receivedAtMs=f.room.startsAtMs+999,/order/);
  reject(f=>f.streams[0].packets[44].receivedAtMs=f.nowMs+1,/order/);
  reject(f=>f.streams[0].packets[0].receivedAtMs=NaN,/order/);
});
test('requires a finished, unexpired result window and awaiting_result state',()=>{
  reject(f=>f.nowMs--,/result window/);
  reject(f=>f.nowMs+=15000,/result window/);
  for(const status of ['running','countdown','cancelled','expired','completed'])
    reject(f=>f.room.status=status,/room status/);
});
test('fails closed for incompatible versions, seeds and schedule',()=>{
  reject(f=>f.room.engineVersion='sky-hop-v2',/engine version/);
  reject(f=>f.room.inputProtocol='unknown',/input protocol/);
  reject(f=>f.room.seed=-1,/seed/);
  reject(f=>f.room.endsAtMs++,/schedule/);
});
test('every golden vector produces the same score and hits through packet validation',()=>{
  for(const v of vectors) {
    const f=fixture(); f.room.seed=v.seed;
    for(const s of f.streams)for(const p of s.packets)
      p.flaps=v.inputs.filter(t=>t>=p.fromTick && t<p.throughTick);
    const r=verifyRound(f); assert.equal(r.winnerId,null);
    for(const actual of r.results) {
      assert.equal(actual.score,v.checkpoints.at(-1).score);
      assert.equal(actual.hits,v.checkpoints.at(-1).hits);
    }
  }
});
