import { createHash, createHmac } from 'node:crypto';
import { Hono } from 'hono';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { requestSigningMiddleware } from '../src/middleware/request-signing.js';

const KEY = 'shared-signing-key';

/**
 * Mirrors the canonical string the iOS `RequestSigningService` and the Android
 * `RequestSigningInterceptor` build: METHOD\nPATH\nTIMESTAMP\nSHA256(BODY).
 * If this helper and the middleware ever disagree, signed requests from real
 * clients start failing — which is exactly what these tests guard.
 */
function signRequest(
  method: string,
  path: string,
  timestamp: string,
  body: string,
  key = KEY
): string {
  const bodyHash = createHash('sha256').update(body).digest('hex');
  const payload = `${method}\n${path}\n${timestamp}\n${bodyHash}`;
  return createHmac('sha256', key).update(payload).digest('hex');
}

function app() {
  const instance = new Hono();
  instance.use('/protected/*', requestSigningMiddleware);
  instance.post('/protected/thing', (c) => c.json({ ok: true }));
  return instance;
}

async function send(
  headers: Record<string, string>,
  body = JSON.stringify({ hello: 'world' })
) {
  return app().request('/protected/thing', {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...headers },
    body,
  });
}

beforeEach(() => {
  process.env.REQUEST_SIGNING_KEY = KEY;
});

afterEach(() => {
  delete process.env.REQUEST_SIGNING_KEY;
});

describe('requestSigningMiddleware', () => {
  it('accepts a correctly signed request', async () => {
    const timestamp = new Date().toISOString();
    const body = JSON.stringify({ hello: 'world' });

    const response = await send(
      {
        'x-request-timestamp': timestamp,
        'x-request-signature': signRequest('POST', '/protected/thing', timestamp, body),
      },
      body
    );

    expect(response.status).toBe(200);
  });

  it('rejects a request with no signature headers', async () => {
    const response = await send({});

    expect(response.status).toBe(401);
    await expect(response.json()).resolves.toMatchObject({
      error: 'Missing request signature headers',
    });
  });

  it('rejects a signature computed over a different body', async () => {
    const timestamp = new Date().toISOString();
    const signature = signRequest('POST', '/protected/thing', timestamp, '{"hello":"world"}');

    const response = await send(
      { 'x-request-timestamp': timestamp, 'x-request-signature': signature },
      '{"hello":"tampered"}'
    );

    expect(response.status).toBe(401);
    await expect(response.json()).resolves.toMatchObject({ error: 'Invalid request signature' });
  });

  it('rejects a signature computed over a different path', async () => {
    const timestamp = new Date().toISOString();
    const body = JSON.stringify({ hello: 'world' });
    const signature = signRequest('POST', '/protected/other', timestamp, body);

    const response = await send(
      { 'x-request-timestamp': timestamp, 'x-request-signature': signature },
      body
    );

    expect(response.status).toBe(401);
  });

  it('rejects a signature made with the wrong key', async () => {
    const timestamp = new Date().toISOString();
    const body = JSON.stringify({ hello: 'world' });
    const signature = signRequest('POST', '/protected/thing', timestamp, body, 'other-key');

    const response = await send(
      { 'x-request-timestamp': timestamp, 'x-request-signature': signature },
      body
    );

    expect(response.status).toBe(401);
  });

  it('rejects a timestamp beyond the allowed clock skew', async () => {
    const stale = new Date(Date.now() - 10 * 60 * 1000).toISOString();
    const body = JSON.stringify({ hello: 'world' });

    const response = await send(
      {
        'x-request-timestamp': stale,
        'x-request-signature': signRequest('POST', '/protected/thing', stale, body),
      },
      body
    );

    expect(response.status).toBe(401);
    await expect(response.json()).resolves.toMatchObject({
      error: 'Request timestamp expired or invalid',
    });
  });

  it('rejects a future-dated timestamp beyond the allowed skew', async () => {
    const future = new Date(Date.now() + 10 * 60 * 1000).toISOString();
    const body = JSON.stringify({ hello: 'world' });

    const response = await send(
      {
        'x-request-timestamp': future,
        'x-request-signature': signRequest('POST', '/protected/thing', future, body),
      },
      body
    );

    expect(response.status).toBe(401);
  });

  it('rejects an unparseable timestamp', async () => {
    const response = await send({
      'x-request-timestamp': 'not-a-date',
      'x-request-signature': 'a'.repeat(64),
    });

    expect(response.status).toBe(401);
  });

  it('rejects a malformed-hex signature without throwing a 500', async () => {
    // timingSafeEqual throws on a length mismatch, so the length guard must run
    // first or a hostile client turns a 401 into a 500.
    const timestamp = new Date().toISOString();

    const response = await send({
      'x-request-timestamp': timestamp,
      'x-request-signature': 'zz',
    });

    expect(response.status).toBe(401);
  });

  it('skips validation entirely when no signing key is configured', async () => {
    delete process.env.REQUEST_SIGNING_KEY;

    const response = await send({});

    expect(response.status).toBe(200);
  });
});
