import { generateKeyPairSync } from 'node:crypto';
import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  createProviderToken,
  readApnsConfig,
  resetApnsTokenCache,
  sendApnsPush,
  type ApnsConfig,
  type ApnsRequest,
  type ApnsResponse,
} from '../src/lib/apns.js';

function testConfig(): ApnsConfig {
  // A real ES256 key: the signer must actually be able to sign with it, so a
  // fixture string would not exercise the JWT path.
  const { privateKey } = generateKeyPairSync('ec', {
    namedCurve: 'prime256v1',
    privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
    publicKeyEncoding: { type: 'spki', format: 'pem' },
  }) as unknown as { privateKey: string };

  return {
    keyP8: privateKey,
    keyId: 'ABC123DEFG',
    teamId: 'TEAM123456',
    topic: 'app.lociate.ios',
    host: 'https://api.sandbox.push.apple.com',
  };
}

/** Records every request and replays a scripted list of responses. */
function fakeTransport(responses: Array<ApnsResponse | Error>) {
  const requests: ApnsRequest[] = [];
  let index = 0;
  const transport = async (request: ApnsRequest): Promise<ApnsResponse> => {
    requests.push(request);
    const next = responses[Math.min(index, responses.length - 1)];
    index += 1;
    if (next instanceof Error) throw next;
    return next;
  };
  return { transport, requests, attempts: () => requests.length };
}

const noSleep = async () => {};

afterEach(() => {
  resetApnsTokenCache();
  vi.restoreAllMocks();
});

describe('readApnsConfig', () => {
  it('returns null when any credential is missing', () => {
    expect(readApnsConfig({ APNS_KEY_ID: 'k', APNS_TEAM_ID: 't' } as NodeJS.ProcessEnv)).toBeNull();
    expect(readApnsConfig({ APNS_KEY_P8: 'p', APNS_TEAM_ID: 't' } as NodeJS.ProcessEnv)).toBeNull();
    expect(readApnsConfig({} as NodeJS.ProcessEnv)).toBeNull();
  });

  it('restores escaped newlines in a single-line PEM secret', () => {
    const config = readApnsConfig({
      APNS_KEY_P8: '-----BEGIN PRIVATE KEY-----\\nabc\\n-----END PRIVATE KEY-----',
      APNS_KEY_ID: 'k',
      APNS_TEAM_ID: 't',
    } as NodeJS.ProcessEnv);
    expect(config?.keyP8).toBe('-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----');
  });

  it('defaults to the sandbox gateway outside production', () => {
    const base = { APNS_KEY_P8: 'p', APNS_KEY_ID: 'k', APNS_TEAM_ID: 't' };
    expect(readApnsConfig({ ...base } as NodeJS.ProcessEnv)?.host).toContain('sandbox');
    expect(
      readApnsConfig({ ...base, NODE_ENV: 'production' } as NodeJS.ProcessEnv)?.host
    ).toBe('https://api.push.apple.com');
  });
});

describe('createProviderToken', () => {
  it('mints an ES256 JWT with the key id and team id', () => {
    const config = testConfig();
    const jwt = createProviderToken(config, 1_700_000_000_000);
    const [header, claims, signature] = jwt.split('.');

    expect(JSON.parse(Buffer.from(header, 'base64url').toString())).toEqual({
      alg: 'ES256',
      kid: 'ABC123DEFG',
      typ: 'JWT',
    });
    expect(JSON.parse(Buffer.from(claims, 'base64url').toString())).toEqual({
      iss: 'TEAM123456',
      iat: 1_700_000_000,
    });
    // ES256 over P-256 is r||s, 32 bytes each.
    expect(Buffer.from(signature, 'base64url')).toHaveLength(64);
    expect(jwt).not.toContain('=');
  });

  it('reuses a cached token until it nears expiry, then re-mints', () => {
    const config = testConfig();
    const start = 1_700_000_000_000;

    const first = createProviderToken(config, start);
    expect(createProviderToken(config, start + 60_000)).toBe(first);
    // Past the 50-minute refresh horizon.
    expect(createProviderToken(config, start + 3_001_000)).not.toBe(first);
  });
});

describe('sendApnsPush', () => {
  const payload = { title: 'Digest', body: '2 loci this week' };

  it('no-ops without crashing when APNs is not configured', async () => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    const { transport, attempts } = fakeTransport([{ status: 200, body: '' }]);

    const result = await sendApnsPush('abc', payload, { config: null, transport });

    expect(result).toMatchObject({ ok: false, skipped: true, invalidToken: false });
    expect(attempts()).toBe(0);
  });

  it('rejects an empty device token without calling APNs', async () => {
    const { transport, attempts } = fakeTransport([{ status: 200, body: '' }]);
    const result = await sendApnsPush('', payload, { config: testConfig(), transport });

    expect(result).toMatchObject({ ok: false, invalidToken: true, reason: 'EmptyDeviceToken' });
    expect(attempts()).toBe(0);
  });

  it('posts to /3/device/<token> with the required APNs headers', async () => {
    const { transport, requests } = fakeTransport([{ status: 200, body: '' }]);
    const result = await sendApnsPush('DEVICETOKEN', payload, {
      config: testConfig(),
      transport,
    });

    expect(result).toMatchObject({ ok: true, status: 200, invalidToken: false });
    expect(requests[0].path).toBe('/3/device/DEVICETOKEN');
    expect(requests[0].host).toBe('https://api.sandbox.push.apple.com');
    expect(requests[0].headers['apns-topic']).toBe('app.lociate.ios');
    expect(requests[0].headers['apns-push-type']).toBe('alert');
    expect(requests[0].headers.authorization).toMatch(/^bearer ey/);

    const body = JSON.parse(requests[0].body);
    expect(body.aps.alert).toEqual({ title: 'Digest', body: '2 loci this week' });
  });

  it('sets apns-collapse-id only when a collapse id is supplied', async () => {
    const config = testConfig();
    const withCollapse = fakeTransport([{ status: 200, body: '' }]);
    await sendApnsPush('T', { ...payload, collapseId: 'weekly' }, {
      config,
      transport: withCollapse.transport,
    });
    expect(withCollapse.requests[0].headers['apns-collapse-id']).toBe('weekly');

    const without = fakeTransport([{ status: 200, body: '' }]);
    await sendApnsPush('T', payload, { config, transport: without.transport });
    expect(without.requests[0].headers['apns-collapse-id']).toBeUndefined();
  });

  it('flags the token as dead on 410 Unregistered and does not retry', async () => {
    const { transport, attempts } = fakeTransport([
      { status: 410, body: JSON.stringify({ reason: 'Unregistered' }) },
    ]);

    const result = await sendApnsPush('DEAD', payload, {
      config: testConfig(),
      transport,
      sleep: noSleep,
    });

    expect(result).toMatchObject({ ok: false, invalidToken: true, reason: 'Unregistered' });
    expect(attempts()).toBe(1);
  });

  it('flags the token as dead on 400 BadDeviceToken', async () => {
    const { transport, attempts } = fakeTransport([
      { status: 400, body: JSON.stringify({ reason: 'BadDeviceToken' }) },
    ]);

    const result = await sendApnsPush('SANDBOXTOKEN', payload, {
      config: testConfig(),
      transport,
      sleep: noSleep,
    });

    expect(result).toMatchObject({ ok: false, invalidToken: true, reason: 'BadDeviceToken' });
    expect(attempts()).toBe(1);
  });

  it('does not flag the token as dead for a non-token 400', async () => {
    const { transport } = fakeTransport([
      { status: 400, body: JSON.stringify({ reason: 'BadTopic' }) },
    ]);

    const result = await sendApnsPush('T', payload, {
      config: testConfig(),
      transport,
      sleep: noSleep,
    });

    expect(result).toMatchObject({ ok: false, invalidToken: false, reason: 'BadTopic' });
  });

  it('retries a 429 and succeeds on a later attempt', async () => {
    const { transport, attempts } = fakeTransport([
      { status: 429, body: JSON.stringify({ reason: 'TooManyRequests' }) },
      { status: 200, body: '' },
    ]);

    const result = await sendApnsPush('T', payload, {
      config: testConfig(),
      transport,
      sleep: noSleep,
    });

    expect(result.ok).toBe(true);
    expect(attempts()).toBe(2);
  });

  it('gives up after the attempt cap on repeated 503s', async () => {
    const { transport, attempts } = fakeTransport([
      { status: 503, body: JSON.stringify({ reason: 'ServiceUnavailable' }) },
    ]);

    const result = await sendApnsPush('T', payload, {
      config: testConfig(),
      transport,
      sleep: noSleep,
      maxAttempts: 3,
    });

    expect(result).toMatchObject({ ok: false, invalidToken: false, status: 503 });
    expect(attempts()).toBe(3);
  });

  it('retries transport errors and reports them once exhausted', async () => {
    const { transport, attempts } = fakeTransport([new Error('ECONNRESET')]);

    const result = await sendApnsPush('T', payload, {
      config: testConfig(),
      transport,
      sleep: noSleep,
      maxAttempts: 2,
    });

    expect(result.ok).toBe(false);
    expect(result.invalidToken).toBe(false);
    expect(result.reason).toContain('TransportError');
    expect(attempts()).toBe(2);
  });

  it('backs off exponentially between retries', async () => {
    const delays: number[] = [];
    const { transport } = fakeTransport([{ status: 500, body: '' }]);

    await sendApnsPush('T', payload, {
      config: testConfig(),
      transport,
      maxAttempts: 4,
      sleep: async (ms) => {
        delays.push(ms);
      },
    });

    expect(delays).toEqual([250, 500, 1000]);
  });
});
