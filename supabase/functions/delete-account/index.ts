import { createClient } from 'npm:@supabase/supabase-js@2.118.0';
import { handleDelete } from './handler.mjs';

Deno.serve((request: Request) => handleDelete(request, () => {
  const url = Deno.env.get('SUPABASE_URL');
  const anon = Deno.env.get('SUPABASE_ANON_KEY');
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anon || !service) throw new Error('Configuration unavailable');
  const options = { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } };
  return { auth: createClient(url, anon, options), admin: createClient(url, service, options) };
}));
