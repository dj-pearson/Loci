import { generateKeyPairSync } from 'node:crypto';
import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  createServiceAccountAssertion,
  readFcmConfig,
  resetFcmTokenCache,
  sendFcmPush,
  type FcmConfig,
  type FcmRequest,
  type FcmResponse,
} from '../src/lib/fcm.js';

function testConfig(): FcmConfig {
  // A real RSA key: the assertion is actually signed, so a fixture string would
  // not exercise the JWT path.
  const { privateKey } = generateKeyPairSync('rsa', {
    modulusLength: 2048,
    privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
    publicKeyEncoding: { type: 'spki', format: 'pem' },
  }) as unknown as { privateKey: string };

  return {
    projectId: 'lociate-test',
    clientEmail: 'fcm@lociate-test.iam.gserviceaccount.com',
    privateKey,
  };
}

const TOKEN_OK: FcmResponse = {
  status: 200,
  body: JSON.stringify({ access_token: 'ya29.fake', expires_in: 3600 }),
};

/**
 * Replays scripted responses. The first call is always the OAuth2 token exchange,
 * so `sendResponses` describes only the messages:send calls.
 */
function fakeTransport(sendResponses: Array<FcmResponse | Error>) {
  const requests: FcmRequest[] = [];
  let sendIndex = 0;

  const transport = async (request: FcmRequest): Promise<FcmResponse> => {
    requests.push(request);
    if (request.url.includes('oauth2.googleapis.com')) return TOKEN_OK;

    const next = sendResponses[Math.min(sendIndex, sendResponses.length - 1)];
    sendIndex += 1;
    if (next instanceof Error) throw next;
    return next;
  };

  return {
    transport,
    requests,
    sends: () => requests.filter((r) => r.url.includes('messages:send')),
    tokenExchanges: () => requests.filter((r) => r.url.includes('oauth2.googleapis.com')),
  };
}

const noSleep = async () => {};
const payload = { title: 'Digest', body: '2 loci this week' };

afterEach(() => {
  resetFcmTokenCache();
  vi.restoreAllMocks();
});

describe('readFcmConfig', () => {
  it('returns null when the service account JSON is absent', () => {
    expect(readFcmConfig({} as NodeJS.ProcessEnv)).toBeNull();
  });

  it('returns null and logs when the JSON is malformed', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    expect(
      readFcmConfig({ FCM_SERVICE_ACCOUNT_JSON: '{not json' } as NodeJS.ProcessEnv)
    ).toBeNull();
    expect(spy).toHaveBeenCalled();
  });

  it('returns null when a required field is missing', () => {
    expect(
      readFcmConfig({
        FCM_SERVICE_ACCOUNT_JSON: JSON.stringify({ project_id: 'x' }),
      } as NodeJS.ProcessEnv)
    ).toBeNull();
  });

  it('restores escaped newlines in the private key', () => {
    const config = readFcmConfig({
      FCM_SERVICE_ACCOUNT_JSON: JSON.stringify({
        project_id: 'p',
        client_email: 'e@x.com',
        private_key: '-----BEGIN PRIVATE KEY-----\\nabc\\n-----END PRIVATE KEY-----',
      }),
    } as NodeJS.ProcessEnv);

    expect(config?.privateKey).toBe(
      '-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----'
    );
  });
});

describe('createServiceAccountAssertion', () => {
  it('builds an RS256 JWT with the messaging scope and token audience', () => {
    const config = testConfig();
    const [header, claims, signature] = createServiceAccountAssertion(
      config,
      1_700_000_000_000
    ).split('.');

    expect(JSON.parse(Buffer.from(header, 'base64url').toString())).toEqual({
      alg: 'RS256',
      typ: 'JWT',
    });
    const parsed = JSON.parse(Buffer.from(claims, 'base64url').toString());
    expect(parsed).toMatchObject({
      iss: config.clientEmail,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: 1_700_000_000,
      exp: 1_700_003_600,
    });
    // RSA-2048 signature is 256 bytes.
    expect(Buffer.from(signature, 'base64url')).toHaveLength(256);
  });
});

describe('sendFcmPush', () => {
  it('no-ops without crashing when FCM is not configured', async () => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    const { transport, requests } = fakeTransport([{ status: 200, body: '{}' }]);

    const result = await sendFcmPush('tok', payload, { config: null, transport });

    expect(result).toMatchObject({ ok: false, skipped: true, invalidToken: false });
    expect(requests).toHaveLength(0);
  });

  it('rejects an empty token without contacting FCM', async () => {
    const { transport, requests } = fakeTransport([{ status: 200, body: '{}' }]);
    const result = await sendFcmPush('', payload, { config: testConfig(), transport });

    expect(result).toMatchObject({ ok: false, invalidToken: true, reason: 'EmptyToken' });
    expect(requests).toHaveLength(0);
  });

  it('posts a data-only message to the v1 send endpoint', async () => {
    const { transport, sends } = fakeTransport([{ status: 200, body: '{}' }]);

    const result = await sendFcmPush('DEVICE', payload, {
      config: testConfig(),
      transport,
    });

    expect(result).toMatchObject({ ok: true, status: 200 });
    const send = sends()[0];
    expect(send.url).toBe(
      'https://fcm.googleapis.com/v1/projects/lociate-test/messages:send'
    );
    expect(send.headers.authorization).toBe('Bearer ya29.fake');

    const body = JSON.parse(send.body);
    expect(body.message.token).toBe('DEVICE');
    expect(body.message.android.priority).toBe('HIGH');
    // Data-only: the Android client builds the notification so channel, deep link,
    // and copy match its local geofence notifications.
    expect(body.message.notification).toBeUndefined();
    expect(body.message.data).toMatchObject({ title: 'Digest', body: '2 loci this week' });
  });

  it('passes locus_id through in snake_case for the Android client', async () => {
    const { transport, sends } = fakeTransport([{ status: 200, body: '{}' }]);

    await sendFcmPush('DEVICE', { ...payload, data: { locus_id: 'abc' } }, {
      config: testConfig(),
      transport,
    });

    expect(JSON.parse(sends()[0].body).message.data.locus_id).toBe('abc');
  });

  it('reuses the access token across sends rather than re-exchanging', async () => {
    const config = testConfig();
    const { transport, tokenExchanges } = fakeTransport([{ status: 200, body: '{}' }]);

    await sendFcmPush('A', payload, { config, transport });
    await sendFcmPush('B', payload, { config, transport });

    expect(tokenExchanges()).toHaveLength(1);
  });

  it('re-exchanges the token once it nears expiry', async () => {
    const config = testConfig();
    const { transport, tokenExchanges } = fakeTransport([{ status: 200, body: '{}' }]);
    let clock = 1_700_000_000_000;

    await sendFcmPush('A', payload, { config, transport, now: () => clock });
    clock += 3_001_000; // past the 50-minute refresh horizon
    await sendFcmPush('B', payload, { config, transport, now: () => clock });

    expect(tokenExchanges()).toHaveLength(2);
  });

  it('flags the token dead on UNREGISTERED without retrying', async () => {
    const { transport, sends } = fakeTransport([
      {
        status: 404,
        body: JSON.stringify({
          error: { status: 'NOT_FOUND', details: [{ errorCode: 'UNREGISTERED' }] },
        }),
      },
    ]);

    const result = await sendFcmPush('DEAD', payload, {
      config: testConfig(),
      transport,
      sleep: noSleep,
    });

    expect(result).toMatchObject({ ok: false, invalidToken: true, reason: 'UNREGISTERED' });
    expect(sends()).toHaveLength(1);
  });

  it('flags the token dead on SENDER_ID_MISMATCH', async () => {
    const { transport } = fakeTransport([
      {
        status: 403,
        body: JSON.stringify({
          error: { status: 'PERMISSION_DENIED', details: [{ errorCode: 'SENDER_ID_MISMATCH' }] },
        }),
      },
    ]);

    const result = await sendFcmPush('X', payload, {
      config: testConfig(),
      transport,
      sleep: noSleep,
    });

    expect(result.invalidToken).toBe(true);
  });

  it('does not flag the token dead for a transient quota error', async () => {
    const { transport, sends } = fakeTransport([
      {
        status: 429,
        body: JSON.stringify({
          error: { status: 'RESOURCE_EXHAUSTED', details: [{ errorCode: 'QUOTA_EXCEEDED' }] },
        }),
      },
      { status: 200, body: '{}' },
    ]);

    const result = await sendFcmPush('X', payload, {
      config: testConfig(),
      transport,
      sleep: noSleep,
    });

    expect(result.ok).toBe(true);
    expect(result.invalidToken).toBe(false);
    expect(sends()).toHaveLength(2);
  });

  it('gives up after the attempt cap on repeated 503s', async () => {
    const { transport, sends } = fakeTransport([{ status: 503, body: '{}' }]);

    const result = await sendFcmPush('X', payload, {
      config: testConfig(),
      transport,
      sleep: noSleep,
      maxAttempts: 3,
    });

    expect(result).toMatchObject({ ok: false, invalidToken: false, status: 503 });
    expect(sends()).toHaveLength(3);
  });

  it('backs off exponentially between retries', async () => {
    const delays: number[] = [];
    const { transport } = fakeTransport([{ status: 500, body: '{}' }]);

    await sendFcmPush('X', payload, {
      config: testConfig(),
      transport,
      maxAttempts: 4,
      sleep: async (ms) => {
        delays.push(ms);
      },
    });

    expect(delays).toEqual([250, 500, 1000]);
  });

  it('reports a failed token exchange as a transport error, not a dead token', async () => {
    // A misconfigured service account must not cause every user's token to be
    // wiped from the database.
    const transport = async (request: FcmRequest): Promise<FcmResponse> =>
      request.url.includes('oauth2')
        ? { status: 400, body: JSON.stringify({ error: 'invalid_grant' }) }
        : { status: 200, body: '{}' };

    const result = await sendFcmPush('X', payload, {
      config: testConfig(),
      transport,
      sleep: noSleep,
      maxAttempts: 2,
    });

    expect(result.ok).toBe(false);
    expect(result.invalidToken).toBe(false);
    expect(result.reason).toContain('TransportError');
  });
});
