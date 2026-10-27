// Bound bytes while reading, not after buffering an untrusted request.
// The deadline covers the whole body, including a stalled chunked upload.
export class BodyReadError extends Error {
  constructor(status, code) { super(code); this.status = status; this.code = code; }
}
export async function readJsonBody(request, maxBytes, timeoutMs = 5000) {
  const reader = request.body?.getReader();
  if (!reader) throw new BodyReadError(400, 'INVALID_REQUEST');
  let timer;
  const deadline = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new BodyReadError(408, 'REQUEST_TIMEOUT')), timeoutMs);
  });
  const cancel = () => { reader.cancel().catch(() => {}); };
  try {
    const chunks = [];
    let length = 0;
    while (true) {
      const {done, value} = await Promise.race([reader.read(), deadline]);
      if (done) break;
      length += value.byteLength;
      if (length > maxBytes) throw new BodyReadError(413, 'BODY_TOO_LARGE');
      chunks.push(value);
    }
    const bytes = new Uint8Array(length);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    return JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes));
  } catch (error) {
    cancel();
    if (error instanceof BodyReadError) throw error;
    throw new BodyReadError(400, 'INVALID_REQUEST');
  } finally {
    clearTimeout(timer);
    reader.releaseLock();
  }
}
