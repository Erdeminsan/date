const headers={'Content-Type':'application/json','Cache-Control':'no-store','Access-Control-Allow-Origin':'*',
  'Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS'};
const reply=(status,body)=>new Response(JSON.stringify(body),{status,headers});
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const dbFailure=(error)=>reply(error?.message==='REPORT_LIMIT'?429:409,{error:['REPORT_LIMIT','REPORT_CONFLICT','PHOTO_CHANGED'].includes(error?.message)?error.message:'PHOTO_UNAVAILABLE'});
export async function handlePhotoReport(request,createClients){
  if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
  if(request.method!=='POST')return reply(405,{error:'METHOD_NOT_ALLOWED'});
  const authHeader=request.headers.get('Authorization')??'';
  if(!authHeader.startsWith('Bearer ')||authHeader.length>8192||!authHeader.slice(7).trim())return reply(401,{error:'AUTH_REQUIRED'});
  let body;
  try{
    const reader=request.body?.getReader();let length=0;const chunks=[];
    if(!reader)return reply(400,{error:'INVALID_REQUEST'});
    while(true){const {done,value}=await reader.read();if(done)break;length+=value.length;
      if(length>8192){await reader.cancel();return reply(413,{error:'BODY_TOO_LARGE'});}chunks.push(value);}
    const raw=new Uint8Array(length);let offset=0;for(const chunk of chunks){raw.set(chunk,offset);offset+=chunk.length;}
    body=JSON.parse(new TextDecoder().decode(raw));
  }
  catch{return reply(400,{error:'INVALID_REQUEST'});}
  if(!body||!uuid.test(body.target_id??'')||!uuid.test(body.request_id??'')||typeof body.path!=='string'||body.path.length>200||
    typeof body.reason!=='string'||[...body.reason.trim()].length<5||[...body.reason.trim()].length>1000||
    typeof body.sha256!=='string'||!/^[0-9a-f]{64}$/.test(body.sha256))return reply(400,{error:'INVALID_REQUEST'});
  try{
    const {auth,admin}=createClients();
    const verified=await auth.auth.getUser(authHeader.slice(7).trim());const user=verified.data?.user;
    if(verified.error||!user?.id||!user.email_confirmed_at||user.is_anonymous)return reply(401,{error:'AUTH_REQUIRED'});
    const params={p_actor:user.id,p_target:body.target_id,p_path:body.path,p_request:body.request_id,p_reason:body.reason.trim(),p_sha256:body.sha256};
    const prepared=await admin.rpc('prepare_photo_report',params);
    if(prepared.error)return dbFailure(prepared.error);
    if(prepared.data?.status==='completed')return reply(200,prepared.data);
    if(prepared.data?.status!=='capture'||typeof prepared.data.source_path!=='string'||!uuid.test(prepared.data.source_object_id??''))return reply(503,{error:'PHOTO_UNAVAILABLE'});
    // Fixed private bucket and server-derived path: never fetch a caller-supplied URL.
    const downloaded=await admin.storage.from('profile-photos').download(prepared.data.source_path);
    const blob=downloaded.data;
    if(downloaded.error||!blob||blob.size<5||blob.size>2097152)return reply(409,{error:'PHOTO_CHANGED'});
    const bytes=new Uint8Array(await blob.arrayBuffer());
    if(bytes[0]!==255||bytes[1]!==216||bytes[2]!==255||bytes.at(-2)!==255||bytes.at(-1)!==217)return reply(409,{error:'PHOTO_CHANGED'});
    const digest=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),b=>b.toString(16).padStart(2,'0')).join('');
    if(digest!==body.sha256)return reply(409,{error:'PHOTO_CHANGED'});
    let binary='';for(let i=0;i<bytes.length;i+=8192)binary+=String.fromCharCode(...bytes.subarray(i,i+8192));
    const saved=await admin.rpc('finalize_photo_report',{...params,p_source_object:prepared.data.source_object_id,p_base64:btoa(binary)});
    if(saved.error)return dbFailure(saved.error);
    if(saved.data?.status!=='completed')return reply(503,{error:'PHOTO_UNAVAILABLE'});
    return reply(200,saved.data);
  }catch{return reply(503,{error:'PHOTO_UNAVAILABLE'});}
}
