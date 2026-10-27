import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readJsonBody} from '../../supabase/functions/_shared/request-body.mjs';
import {handleResult} from '../../supabase/functions/finish-round/handler.mjs';
import {handleDelete} from '../../supabase/functions/delete-account/handler.mjs';
import {handlePhotoReport} from '../../supabase/functions/report-photo/handler.mjs';
const encode=s=>new TextEncoder().encode(s);
function streamed(chunks,{stall=false,fail=false}={}) {
  let cancelled=false;
  const stream=new ReadableStream({
    pull(controller) {
      if(chunks.length) controller.enqueue(chunks.shift());
      else if(fail) controller.error(Error('private stream error'));
      else if(!stall) controller.close();
    },
    cancel(){cancelled=true;},
  });
  return {request:new Request('https://example.test',{method:'POST',duplex:'half',
    headers:{Authorization:'Bearer valid','Content-Length':'1'},body:stream}),cancelled:()=>cancelled};
}
test('exact byte limit accepts fragmented UTF-8 including split characters',async()=>{
  const bytes=encode('{"text":"ş🙂"}');
  const f=streamed([...bytes].map(b=>new Uint8Array([b])));
  assert.deepEqual(await readJsonBody(f.request,bytes.length),{text:'ş🙂'});
});
test('oversized chunked body cancels without waiting for stream end or trusting length',async()=>{
  const f=streamed([encode(' '.repeat(11))],{stall:true});
  await assert.rejects(()=>readJsonBody(f.request,10),e=>e.status===413);
  assert.equal(f.cancelled(),true);
});
test('body deadline cancels a stalled stream',async()=>{
  const f=streamed([],{stall:true});
  await assert.rejects(()=>readJsonBody(f.request,100,10),e=>e.status===408);
  assert.equal(f.cancelled(),true);
});
test('malformed UTF-8, JSON, empty and failed streams are redacted',async()=>{
  for(const f of [streamed([new Uint8Array([255])]),streamed([encode('{')]),
    streamed([]),streamed([],{fail:true})]) {
    await assert.rejects(()=>readJsonBody(f.request,100),e=>e.status===400&&e.code==='INVALID_REQUEST');
  }
});
for(const [name,handler,limit] of [['result',handleResult,2048],['delete',handleDelete,4096],['photo',handlePhotoReport,8192]]) {
  test(name+' rejects byte-heavy JSON before auth/client creation',async()=>{
    let calls=0;
    const body=JSON.stringify({padding:'ş'.repeat(Math.floor(limit*0.6))});
    assert.ok(body.length<limit);
    const f=streamed([encode(body)],{stall:true});
    const response=await handler(f.request,()=>{calls++;throw Error('must not run');});
    assert.equal(response.status,413);
    assert.deepEqual(await response.json(),{error:'BODY_TOO_LARGE'});
    assert.equal(calls,0);assert.equal(f.cancelled(),true);
  });
}
