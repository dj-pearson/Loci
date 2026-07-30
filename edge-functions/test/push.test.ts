import { generateKeyPairSync } from 'node:crypto';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { resetApnsTokenCache, type ApnsConfig, type ApnsRequest } from '../src/lib/apns.js';
import { resetFcmTokenCache, type FcmConfig, type FcmRequest } from '../src/lib/fcm.js';
import { dispatchPush, tokenColumnFor } from '../src/lib/push.js';

let apnsConfig: ApnsConfig;
let fcmConfig: FcmConfig;

beforeEach(() => {
  const ec = generateKeyPairSync('ec', {
    namedCurve: 'prime256v1',
    privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
    publicKeyEncoding: { type: 'spki', format: 'pem' },
  }) as unknown as { privateKey: string };
  const rsa = generateKeyPairSync('rsa', {
    modulusLength: 2048,
    privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
    publicKeyEncoding: { type: 'spki', format: 'pem' },
  }) as unknown as { privateKey: string };

  apnsConfig = {
    keyP8: ec.privateKey,
    keyId: 'KEYID12345',
    teamId: 'TEAMID1234',
    topic: 'app.lociate.ios',
    host: 'https://api.sandbox.push.apple.com',
  };
  fcmConfig = {
    projectId: 'lociate-test',
    clientEmail: 'fcm@lociate-test.iam.gserviceaccount.com',
    privateKey: rsa.privateKey,
  };
});

afterEach(() => {
  resetApnsTokenCache();
  resetFcmTokenCache();
  vi.restoreAllMocks();
});

function apnsTransport(status: number, body = '') {
  const seen: ApnsRequest[] = [];
  return {
    seen,
    transport: async (request: ApnsRequest) => {
      seen.push(request);
      return { status, body };
    },
  };
}

function fcmTransport(status: number, body = '{}') {
  const seen: FcmRequest[] = [];
  return {
    seen,
    sends: () => seen.filter((r) => r.url.includes('messages:send')),
    transport: async (request: FcmRequest) => {
      seen.push(request);
      if (request.url.includes('oauth2')) {
        return { status: 200, body: JSON.stringify({ access_token: 'ya29.fake' }) };
      }
      return { status, body };
    },
  };
}

const message = { title: 'Digest', body: '2 loci this week' };
const noSleep = async () => {};

describe('dispatchPush', () => {
  it('reports noTokens when the recipient has neither token', async () => {
    const result = await dispatchPush({ userId: 'u1' }, message);

    expect(result).toEqual({ delivered: [], invalid: [], failed: [], noTokens: true });
  });

  it('sends to iOS only when only an APNs token exists', async () => {
    const apns = apnsTransport(200);
    const fcm = fcmTransport(200);

    const result = await dispatchPush(
      { userId: 'u1', apnsToken: 'ios-token' },
      message,
      { apns: { config: apnsConfig, transport: apns.transport }, fcm: { config: fcmConfig, transport: fcm.transport } }
    );

    expect(result.delivered).toEqual(['ios']);
    expect(apns.seen).toHaveLength(1);
    expect(fcm.sends()).toHaveLength(0);
  });

  it('sends to Android only when only an FCM token exists', async () => {
    // The regression this guards: the digest query filtered on apns_token, so an
    // Android-only user could never receive anything.
    const apns = apnsTransport(200);
    const fcm = fcmTransport(200);

    const result = await dispatchPush(
      { userId: 'u1', fcmToken: 'android-token' },
      message,
      { apns: { config: apnsConfig, transport: apns.transport }, fcm: { config: fcmConfig, transport: fcm.transport } }
    );

    expect(result.delivered).toEqual(['android']);
    expect(fcm.sends()).toHaveLength(1);
    expect(apns.seen).toHaveLength(0);
  });

  it('sends to both platforms for a user with two devices', async () => {
    const apns = apnsTransport(200);
    const fcm = fcmTransport(200);

    const result = await dispatchPush(
      { userId: 'u1', apnsToken: 'ios-token', fcmToken: 'android-token' },
      message,
      { apns: { config: apnsConfig, transport: apns.transport }, fcm: { config: fcmConfig, transport: fcm.transport } }
    );

    expect(result.delivered.sort()).toEqual(['android', 'ios']);
    expect(apns.seen).toHaveLength(1);
    expect(fcm.sends()).toHaveLength(1);
  });

  it('passes the locus id in each platform\'s expected key casing', async () => {
    const apns = apnsTransport(200);
    const fcm = fcmTransport(200);

    await dispatchPush(
      { userId: 'u1', apnsToken: 'ios', fcmToken: 'android' },
      { ...message, locusId: 'locus-42' },
      { apns: { config: apnsConfig, transport: apns.transport }, fcm: { config: fcmConfig, transport: fcm.transport } }
    );

    // iOS reads `locusId`; the Android messaging service reads `locus_id`.
    expect(JSON.parse(apns.seen[0].body).locusId).toBe('locus-42');
    expect(JSON.parse(fcm.sends()[0].body).message.data.locus_id).toBe('locus-42');
  });

  it('marks only the dead platform invalid when the other succeeds', async () => {
    const apns = apnsTransport(410, JSON.stringify({ reason: 'Unregistered' }));
    const fcm = fcmTransport(200);

    const result = await dispatchPush(
      { userId: 'u1', apnsToken: 'dead-ios', fcmToken: 'live-android' },
      message,
      {
        apns: { config: apnsConfig, transport: apns.transport, sleep: noSleep },
        fcm: { config: fcmConfig, transport: fcm.transport },
      }
    );

    expect(result.invalid).toEqual(['ios']);
    expect(result.delivered).toEqual(['android']);
    expect(result.failed).toEqual([]);
  });

  it('separates a transient failure from a dead token', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    const apns = apnsTransport(503);
    const fcm = fcmTransport(200);

    const result = await dispatchPush(
      { userId: 'u1', apnsToken: 'ios', fcmToken: 'android' },
      message,
      {
        apns: { config: apnsConfig, transport: apns.transport, sleep: noSleep, maxAttempts: 1 },
        fcm: { config: fcmConfig, transport: fcm.transport },
      }
    );

    // A 503 must not cause the token to be wiped from the database.
    expect(result.failed).toEqual(['ios']);
    expect(result.invalid).toEqual([]);
    expect(result.delivered).toEqual(['android']);
  });

  it('treats an unconfigured platform as failed rather than invalid', async () => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});

    const result = await dispatchPush(
      { userId: 'u1', apnsToken: 'ios', fcmToken: 'android' },
      message,
      { apns: { config: null }, fcm: { config: null } }
    );

    expect(result.failed.sort()).toEqual(['android', 'ios']);
    // Critically: missing credentials must never wipe a user's tokens.
    expect(result.invalid).toEqual([]);
  });

  it('does not let one platform failing prevent the other from sending', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    const fcm = fcmTransport(200);

    const result = await dispatchPush(
      { userId: 'u1', apnsToken: 'ios', fcmToken: 'android' },
      message,
      {
        apns: {
          config: apnsConfig,
          transport: async () => {
            throw new Error('ECONNRESET');
          },
          sleep: noSleep,
          maxAttempts: 1,
        },
        fcm: { config: fcmConfig, transport: fcm.transport },
      }
    );

    expect(result.delivered).toEqual(['android']);
    expect(result.failed).toEqual(['ios']);
  });
});

describe('tokenColumnFor', () => {
  it('maps each platform to its users column', () => {
    expect(tokenColumnFor('ios')).toBe('apns_token');
    expect(tokenColumnFor('android')).toBe('fcm_token');
  });
});
