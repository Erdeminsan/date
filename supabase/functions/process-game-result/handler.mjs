import {readJsonBody} from '../_shared/request-body.mjs';
import {verifyRound} from '../_shared/round-verifier.mjs';
const headers={'Content-Type':'application/json','Cache-Control':'no-store'};
const reply=(status,error)=>new Response(JSON.stringify(error?{error}:{status:'completed'}),{status,headers});
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export async function handleQueuedResult(request,createAdmin) {
  if(request.method!=='POST')return reply(405,'METHOD_NOT_ALLOWED');
  const delivery=request.headers.get('x-job-token');
  if(!delivery||!uuid.test(delivery))return reply(401,'JOB_AUTH_REQUIRED');
  let body;
  try {body=await readJsonBody(request,1024);}
  catch(error){return reply(error.status??400,error.code??'INVALID_REQUEST');}
  if(!body||typeof body.room_id!=='string'||!uuid.test(body.room_id))return reply(400,'INVALID_REQUEST');
  try {
    const admin=createAdmin();
    const params={p_room:body.room_id,p_delivery:delivery};
    const prepared=await admin.rpc('prepare_queued_game_result',params);
    if(prepared.error)return reply(409,'JOB_UNAVAILABLE');
    if(prepared.data?.status!=='verify')return reply(503,'RESULT_UNAVAILABLE');
    let verified;
    try {verified=verifyRound(prepared.data);}
    catch {
      const failed=await admin.rpc('fail_queued_game_result',params);
      return reply(failed.error?503:409,failed.error?'RESULT_UNAVAILABLE':'INVALID_ROUND');
    }
    const [low,high]=verified.results;
    const saved=await admin.rpc('finalize_queued_game_result',{...params,
      p_low_score:low.score,p_high_score:high.score,p_low_hits:low.hits,p_high_hits:high.hits});
    if(saved.error||saved.data?.status!=='completed')return reply(503,'RESULT_UNAVAILABLE');
    return reply(200);
  }catch{return reply(503,'RESULT_UNAVAILABLE');}
}
