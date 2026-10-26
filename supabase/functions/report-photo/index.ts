import {createClient} from 'npm:@supabase/supabase-js@2.118.0';
import {handlePhotoReport} from './handler.mjs';
Deno.serve((request: Request) => handlePhotoReport(request, () => {
  const url=Deno.env.get('SUPABASE_URL'),anon=Deno.env.get('SUPABASE_ANON_KEY'),service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if(!url||!anon||!service)throw new Error('Configuration unavailable');
  const options={auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}};
  return {auth:createClient(url,anon,options),admin:createClient(url,service,options)};
}));
