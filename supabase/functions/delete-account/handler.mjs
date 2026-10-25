const headers = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Cache-Control': 'no-store',
};
const reply = (status, error) => new Response(JSON.stringify(error ? { error } : { deleted: true }), { status, headers });

// Dependencies are per request. Never accept a user id or email from the body.
export async function handleDelete(request, createClients) {
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers });
  if (request.method !== 'POST') return reply(405, 'METHOD_NOT_ALLOWED');
  const authorization = request.headers.get('Authorization') ?? '';
  if (!authorization.startsWith('Bearer ') || authorization.length > 8192) return reply(401, 'AUTH_REQUIRED');
  const token = authorization.slice(7).trim();
  if (!token) return reply(401, 'AUTH_REQUIRED');
  let body;
  try {
    const text = await request.text();
    if (text.length > 4096) return reply(413, 'BODY_TOO_LARGE');
    body = JSON.parse(text);
  } catch { return reply(400, 'INVALID_REQUEST'); }
  if (!body || body.confirmation !== 'DELETE' || typeof body.password !== 'string' || body.password.length < 1 || body.password.length > 256) {
    return reply(400, 'CONFIRMATION_REQUIRED');
  }
  try {
    const { auth, admin } = createClients();
    const verified = await auth.auth.getUser(token);
    const user = verified.data?.user;
    if (verified.error || !user || !user.email || !user.email_confirmed_at || user.is_anonymous) return reply(401, 'AUTH_REQUIRED');
    const reauth = await auth.auth.signInWithPassword({ email: user.email, password: body.password });
    const newToken = reauth.data?.session?.access_token;
    if (reauth.error || reauth.data?.user?.id !== user.id || !newToken) return reply(403, 'PASSWORD_INVALID');
    // Revoke refresh sessions before deletion. Database actor() also rejects a
    // removed auth.users row, so outstanding access JWTs cannot access app data.
    const revoked = await admin.auth.admin.signOut(newToken, 'global');
    if (revoked.error) return reply(503, 'SESSION_REVOCATION_FAILED');
    const deleted = await admin.auth.admin.deleteUser(user.id, false);
    if (deleted.error) return reply(503, 'DELETE_FAILED');
    return reply(200);
  } catch {
    // Never echo password, JWT, SDK errors, or service credentials.
    return reply(503, 'SERVICE_UNAVAILABLE');
  }
}
