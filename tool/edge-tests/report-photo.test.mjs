import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {handlePhotoReport} from '../../supabase/functions/report-photo/handler.mjs';
const actor='00000000-0000-4000-8000-000000000001',target='00000000-0000-4000-8000-000000000002';
const object='00000000-0000-4000-8000-000000000003',nonce='00000000-0000-4000-8000-000000000004';
const bytes=Buffer.from('ffd8ffffd9','hex'),digest=createHash('sha256').update(bytes).digest('hex');
const body={target_id:target,path:`${target}/${nonce}.jpg`,request_id:nonce,reason:'Photo violation',sha256:digest};
const request=(input=body,token='Bearer verified')=>new Request('https://example.test',{method:'POST',headers:{Authorization:token},body:JSON.stringify(input)});
function fixture(options={}){
  const calls=[],downloads=[];
  const factory=()=>({auth:{auth:{getUser:async(token)=>{calls.push({token});return {data:{user:{id:actor,email_confirmed_at:'yes',...options.user}},error:options.authError};}}},admin:{
    rpc:async(name,params)=>{calls.push({name,params});return name==='prepare_photo_report'
      ?{data:{status:options.completed?'completed':'capture',report_id:object,source_path:'server/source.jpg',source_object_id:object},error:options.prepareError}
      :{data:{status:'completed',report_id:object},error:options.finalError};},
    storage:{from:(bucket)=>{assert.equal(bucket,'profile-photos');return {download:async(path)=>{downloads.push(path);if(options.throwDownload)throw new Error('SECRET');return {data:options.blob??new Blob([bytes],{type:'image/jpeg'}),error:options.downloadError};}};}}
  }});
  return {calls,downloads,factory};
}
test('photo report verifies user, downloads server path and ignores forged actor/image claims',async()=>{
  const f=fixture();const response=await handlePhotoReport(request({...body,p_actor:target,base64:'forged',source_path:'https://evil.test'}),f.factory);
  assert.equal(response.status,200);assert.deepEqual(f.downloads,['server/source.jpg']);
  const calls=f.calls.filter(c=>c.name);assert.equal(calls[0].params.p_actor,actor);
  assert.equal(calls[1].params.p_base64,bytes.toString('base64'));assert.equal(calls[1].params.p_source_object,object);
  assert.deepEqual(await response.json(),{status:'completed',report_id:object});
});
test('missing, invalid, anonymous or unconfirmed auth never accesses photo data',async()=>{
  for(const options of [{authError:true},{user:{is_anonymous:true}},{user:{email_confirmed_at:null}}]){
    const f=fixture(options);assert.equal((await handlePhotoReport(request(),f.factory)).status,401);assert.equal(f.downloads.length,0);assert.ok(!f.calls.some(c=>c.name));
  }
  const f=fixture();assert.equal((await handlePhotoReport(request(body,''),f.factory)).status,401);assert.equal(f.calls.length,0);
});
test('invalid or oversized request is rejected before privileged clients',async()=>{
  for(const bad of [{...body,sha256:'bad'},{...body,request_id:'bad'},{...body,reason:'x'},null]){
    const f=fixture();assert.equal((await handlePhotoReport(request(bad),f.factory)).status,400);assert.equal(f.calls.length,0);
  }
  const f=fixture();assert.equal((await handlePhotoReport(request({...body,extra:'x'.repeat(9000)}),f.factory)).status,413);assert.equal(f.calls.length,0);
});
test('completed retry avoids source download after photo removal',async()=>{
  const f=fixture({completed:true});assert.equal((await handlePhotoReport(request(),f.factory)).status,200);assert.equal(f.downloads.length,0);assert.equal(f.calls.filter(c=>c.name).length,1);
});
test('changed preview digest prevents evidence finalization',async()=>{
  const f=fixture();const response=await handlePhotoReport(request({...body,sha256:'0'.repeat(64)}),f.factory);
  assert.equal(response.status,409);assert.equal((await response.json()).error,'PHOTO_CHANGED');assert.equal(f.calls.filter(c=>c.name).length,1);
});
test('oversized or non-JPEG storage object cannot become evidence',async()=>{
  for(const blob of [{size:2097153,arrayBuffer:()=>{throw new Error('must not read');}},new Blob(['not a JPEG'])]){
    const f=fixture({blob});assert.equal((await handlePhotoReport(request(),f.factory)).status,409);assert.equal(f.calls.filter(c=>c.name).length,1);
  }
});
test('quota rejection prevents storage download',async()=>{
  const f=fixture({prepareError:{message:'REPORT_LIMIT'}});assert.equal((await handlePhotoReport(request(),f.factory)).status,429);assert.equal(f.downloads.length,0);
});
test('source version change at finalize is surfaced without claiming success',async()=>{
  const f=fixture({finalError:{message:'PHOTO_CHANGED'}});const response=await handlePhotoReport(request(),f.factory);
  assert.equal(response.status,409);assert.equal((await response.json()).error,'PHOTO_CHANGED');
});
test('storage and database failures redact sensitive errors',async()=>{
  for(const options of [{throwDownload:true},{prepareError:{message:'SECRET'}},{finalError:{message:'SECRET'}}]){
    const f=fixture(options),response=await handlePhotoReport(request(),f.factory);
    assert.ok(response.status>=400);assert.ok(!(await response.text()).includes('SECRET'));
  }
});
test('method and preflight handling do not initialize clients',async()=>{
  const f=fixture();assert.equal((await handlePhotoReport(new Request('https://example.test',{method:'GET'}),f.factory)).status,405);
  assert.equal((await handlePhotoReport(new Request('https://example.test',{method:'OPTIONS'}),f.factory)).status,204);assert.equal(f.calls.length,0);
});
