import {verifyRound} from '../_shared/round-verifier.mjs';
const headers={'Content-Type':'application/json','Cache-Control':'no-store',
  'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods':'POST, OPTIONS'};
const reply=(status,body)=>new Response(JSON.stringify(body),{status,headers});
export async function handleResult(request,createClients) {
  if(request.method==='OPTIONS') return new Response(null,{status:204,headers});
  if(request.method!=='POST') return reply(405,{error:'METHOD_NOT_ALLOWED'});
  const authorization=request.headers.get('Authorization')??'';
  if(!authorization.startsWith('Bearer ')||authorization.length>8192||!authorization.slice(7).trim()) return reply(401,{error:'AUTH_REQUIRED'});
  let body;
  try {
    const text=await request.text();
    if(text.length>2048) return reply(413,{error:'BODY_TOO_LARGE'});
    body=JSON.parse(text);
  } catch { return reply(400,{error:'INVALID_REQUEST'}); }
  if(!body || typeof body.room_id!=='string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(body.room_id)) return reply(400,{error:'INVALID_REQUEST'});
  try {
    const {auth,admin}=createClients();
    const {data,error}=await auth.auth.getUser(authorization.slice(7).trim());
    const user=data?.user;
    if(error||!user?.id||!user.email_confirmed_at||user.is_anonymous) return reply(401,{error:'AUTH_REQUIRED'});
    const params={p_room:body.room_id,p_actor:user.id};
    const prepared=await admin.rpc('prepare_game_result',params);
    if(prepared.error) return reply(409,{error:'ROUND_UNAVAILABLE'});
    if(prepared.data?.status==='pending'||prepared.data?.status==='completed') return reply(200,prepared.data);
    if(prepared.data?.status!=='verify') return reply(503,{error:'RESULT_UNAVAILABLE'});
    let verified;
    try { verified=verifyRound(prepared.data); }
    catch { return reply(409,{error:'INVALID_ROUND'}); }
    const [low,high]=verified.results;
    const result=await admin.rpc('finalize_game_result',{...params,
      p_low_score:low.score,p_high_score:high.score,p_low_hits:low.hits,p_high_hits:high.hits});
    if(result.error) return reply(409,{error:'ROUND_UNAVAILABLE'});
    if(result.data?.status!=='completed') return reply(503,{error:'RESULT_UNAVAILABLE'});
    return reply(200,result.data);
  } catch { return reply(503,{error:'RESULT_UNAVAILABLE'}); }
}
