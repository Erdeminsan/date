import {createClient} from 'npm:@supabase/supabase-js@2.118.0';
import {handleQueuedResult} from './handler.mjs';
Deno.serve((request: Request)=>handleQueuedResult(request,()=>{
  const url=Deno.env.get('SUPABASE_URL');
  const key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if(!url||!key)throw new Error('Configuration unavailable');
  return createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
}));
