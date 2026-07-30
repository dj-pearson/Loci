import { createHmac } from 'node:crypto';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createSupabaseFake } from './helpers/supabase-fake.js';

const fake = createSupabaseFake();

vi.mock('../src/middleware/auth.js', () => ({
  getSupabaseAdmin: () => fake.client,
  authMiddleware: async (_c: unknown, next: () => Promise<void>) => next(),
}));

const SECRET = 'test-webhook-secret';

async function loadRoute() {
  vi.resetModules();
  const mod = await import('../src/routes/sync-subscription.js');
  return mod.default;
}

function sign(body: string, secret = SECRET): string {
  return createHmac('sha256', secret).update(body).digest('hex');
}

function webhook(overrides: Record<string, unknown> = {}): string {
  return JSON.stringify({
    api_version: '1.0',
    event: {
      type: 'INITIAL_PURCHASE',
      app_user_id: 'auth-uuid-1',
      entitlement_ids: ['premium'],
      event_timestamp_ms: Date.now(),
      ...overrides,
    },
  });
}

async function post(body: string, signature?: string) {
  const route = await loadRoute();
  return route.request('/', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(signature ? { 'X-RevenueCat-Signature': signature } : {}),
    },
    body,
  });
}

beforeEach(() => {
  process.env.REVENUECAT_WEBHOOK_SECRET = SECRET;
  fake.ops.length = 0;
});

afterEach(() => {
  delete process.env.REVENUECAT_WEBHOOK_SECRET;
  vi.restoreAllMocks();
});

describe('POST /api/webhook/revenuecat — signature verification', () => {
  it('accepts a correctly signed body', async () => {
    const body = webhook();
    const response = await post(body, sign(body));

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({ status: 'ok', tier: 'premium' });
  });

  it('rejects a body tampered with after signing', async () => {
    const original = webhook({ entitlement_ids: ['premium'] });
    const signature = sign(original);
    const tampered = original.replace('"premium"', '"family"');

    const response = await post(tampered, signature);

    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toMatchObject({ error: 'Invalid webhook signature' });
    // Critically: no tier was written.
    expect(fake.opsFor('users', 'update')).toHaveLength(0);
  });

  it('rejects a request with no signature header', async () => {
    const body = webhook();
    const response = await post(body);

    expect(response.status).toBe(400);
    expect(fake.opsFor('users', 'update')).toHaveLength(0);
  });

  it('rejects every request when the secret is not configured', async () => {
    delete process.env.REVENUECAT_WEBHOOK_SECRET;
    vi.spyOn(console, 'error').mockImplementation(() => {});

    const body = webhook();
    // Even a signature that would be valid under some other secret must fail.
    const response = await post(body, sign(body, 'some-other-secret'));

    expect(response.status).toBe(400);
    expect(fake.opsFor('users', 'update')).toHaveLength(0);
  });

  it('rejects a signature of the wrong length without throwing', async () => {
    // timingSafeEqual throws on length mismatch, so the length guard has to run
    // first — otherwise this is a 500 instead of a clean 400.
    const body = webhook();
    const response = await post(body, 'deadbeef');

    expect(response.status).toBe(400);
  });

  it('rejects a hex-shaped signature of the right length but wrong value', async () => {
    const body = webhook();
    const response = await post(body, 'a'.repeat(64));

    expect(response.status).toBe(400);
  });
});

describe('POST /api/webhook/revenuecat — replay protection', () => {
  it('rejects an event older than the replay window', async () => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    const body = webhook({ event_timestamp_ms: Date.now() - 10 * 60 * 1000 });

    const response = await post(body, sign(body));

    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toMatchObject({
      error: 'Webhook event too old (possible replay)',
    });
  });

  it('rejects a future-dated event', async () => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    const body = webhook({ event_timestamp_ms: Date.now() + 10 * 60 * 1000 });

    const response = await post(body, sign(body));

    expect(response.status).toBe(400);
  });
});

describe('POST /api/webhook/revenuecat — tier mapping', () => {
  it.each([
    [['family'], 'family'],
    [['premium'], 'premium'],
    [['premium', 'family'], 'family'],
    [[], 'free'],
  ])('maps entitlements %j to tier %s', async (entitlements, expected) => {
    const body = webhook({ entitlement_ids: entitlements });
    const response = await post(body, sign(body));

    await expect(response.json()).resolves.toMatchObject({ tier: expected });
    const update = fake.opsFor('users', 'update').at(-1);
    expect(update?.payload).toMatchObject({ subscription_tier: expected });
    expect(update?.filters).toEqual([['auth_id', 'auth-uuid-1']]);
  });

  it('downgrades to free when a cancellation has already expired', async () => {
    const body = webhook({
      type: 'CANCELLATION',
      entitlement_ids: ['premium'],
      expiration_at_ms: Date.now() - 1000,
    });

    await expect((await post(body, sign(body))).json()).resolves.toMatchObject({ tier: 'free' });
  });

  it('keeps the paid tier until a cancellation actually expires', async () => {
    const body = webhook({
      type: 'CANCELLATION',
      entitlement_ids: ['premium'],
      expiration_at_ms: Date.now() + 24 * 60 * 60 * 1000,
    });

    await expect((await post(body, sign(body))).json()).resolves.toMatchObject({ tier: 'premium' });
  });

  it('acknowledges but ignores unhandled event types', async () => {
    const body = webhook({ type: 'TEST' });
    const response = await post(body, sign(body));

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({ status: 'ignored' });
    expect(fake.opsFor('users', 'update')).toHaveLength(0);
  });

  it('rejects malformed JSON that carries a valid signature', async () => {
    const body = '{not json';
    const response = await post(body, sign(body));

    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toMatchObject({ error: 'Invalid JSON payload' });
  });
});
