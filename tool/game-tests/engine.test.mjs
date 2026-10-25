import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {GameEngine,replay} from './engine.mjs';
const vectors=JSON.parse(readFileSync(new URL('./vectors.json',import.meta.url)));
for(const vector of vectors) test(`replay ${vector.seed} ${vector.mode}`,()=>{
  assert.deepEqual(replay(vector.seed,vector.inputs),vector.checkpoints.at(-1));
  const e=new GameEngine(vector.seed), inputs=new Set(vector.inputs);
  for(const expected of vector.checkpoints){
    while(e.tick<expected.tick)e.step(inputs.has(e.tick));
    assert.deepEqual(e.snapshot(),expected);
  }
  const end=e.snapshot();e.step(true);assert.deepEqual(e.snapshot(),end);
});
test('one tick has the specified integer gravity and LCG state',()=>{
  const e=new GameEngine(0);e.step();
  assert.equal(e.y,500093);assert.equal(e.random,1013904223);assert.equal(e.gates[0].x,1097500);
  const f=new GameEngine(0);f.step(true);assert.equal(f.y,495261);
});
test('reject malformed, unordered, duplicate and out-of-range inputs',()=>{
  for(const inputs of [null,[-1],[5400],[1,1],[2,1],[1.5],Array(5401).fill(0)]) assert.throws(()=>replay(0,inputs),RangeError);
  for(const seed of [-1,4294967296,NaN,1.5])assert.throws(()=>new GameEngine(seed),RangeError);
});
test('fixtures include real scored gates',()=>assert.ok(vectors.some(v=>v.checkpoints.at(-1).score>0)));
