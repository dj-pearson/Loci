import { afterEach, describe, expect, it, vi } from 'vitest';

interface HealthFakeOptions {
  databaseError?: string;
  storageBuckets?: Array<{ name: string }> | null;
  storageError?: string;
  authError?: string;
  /** null = Redis not configured / already failed over. */
  redis?: { pingReply?: string; pingError?: string } | null;
}

interface HealthBody {
  status: string;
  services: Record<string, { status: string; error?: string; latencyMs?: number }>;
}

function healthFake(options: HealthFakeOptions = {}) {
  return {
    rpc: async () => ({
      data: null,
      error: options.databaseError ? { message: options.databaseError } : null,
    }),
    from: () => ({
      select: () => ({
        limit: async () => ({
          data: [],
          error: options.databaseError ? { message: options.databaseError } : null,
        }),
      }),
    }),
    storage: {
      listBuckets: async () => ({
        data: options.storageBuckets ?? [{ name: 'loci-audio' }],
        error: options.storageError ? { message: options.storageError } : null,
      }),
    },
    auth: {
      admin: {
        listUsers: async () => ({
          data: { users: [] },
          error: options.authError ? { message: options.authError } : null,
        }),
      },
    },
  };
}

let fake: ReturnType<typeof healthFake>;
let redisOptions: HealthFakeOptions['redis'] = { pingReply: 'PONG' };

vi.mock('../src/middleware/auth.js', () => ({
  getSupabaseAdmin: () => fake,
  authMiddleware: async (_c: unknown, next: () => Promise<void>) => next(),
}));

// US-215: the Redis probe reads the shared client through rate-limit's accessor.
// Stubbing it here keeps the health tests off a real Redis instance.
vi.mock('../src/middleware/rate-limit.js', () => ({
  getRedisClientForHealthCheck: () =>
    redisOptions === null
      ? null
      : {
          ping: async () => {
            if (redisOptions?.pingError) throw new Error(redisOptions.pingError);
            return redisOptions?.pingReply ?? 'PONG';
          },
        },
}));

async function get(options: HealthFakeOptions = {}) {
  fake = healthFake(options);
  redisOptions = 'redis' in options ? options.redis : { pingReply: 'PONG' };
  vi.resetModules();
  const route = (await import('../src/routes/health.js')).default;
  return route.request('/');
}

afterEach(() => {
  vi.resetModules();
  vi.restoreAllMocks();
});

describe('GET /api/health', () => {
  it('reports ok with per-dependency status when everything is healthy', async () => {
    const response = await get();

    expect(response.status).toBe(200);
    const body = (await response.json()) as HealthBody;
    expect(body).toMatchObject({ status: 'ok' });
    expect(body.services.database.status).toBe('healthy');
    expect(body.services.storage.status).toBe('healthy');
    expect(body.services.auth.status).toBe('healthy');
    expect(body.services.redis.status).toBe('healthy');
  });

  it('returns 503 degraded when the database check fails', async () => {
    const response = await get({ databaseError: 'connection refused' });

    expect(response.status).toBe(503);
    const body = (await response.json()) as HealthBody;
    expect(body.status).toBe('degraded');
    expect(body.services.database.status).toBe('unhealthy');
  });

  it('returns 503 when the audio bucket is missing', async () => {
    // A deployment where 005_storage_bucket.sql never ran looks healthy to a
    // naive check but cannot store a single recording.
    const response = await get({ storageBuckets: [{ name: 'something-else' }] });

    expect(response.status).toBe(503);
    const body = (await response.json()) as HealthBody;
    expect(body.services.storage.error).toContain('loci-audio');
  });

  it('returns 503 when the auth service is unreachable', async () => {
    const response = await get({ authError: 'gotrue unavailable' });

    expect(response.status).toBe(503);
    const body = (await response.json()) as HealthBody;
    expect(body.services.auth.status).toBe('unhealthy');
  });

  it('reports redis unhealthy when PING fails', async () => {
    // Redis backs auth rate-limit persistence, so losing it silently degrades
    // brute-force protection to per-instance in-memory counters.
    const response = await get({ redis: { pingError: 'ECONNREFUSED' } });

    expect(response.status).toBe(503);
    const body = (await response.json()) as HealthBody;
    expect(body.services.redis.status).toBe('unhealthy');
    expect(body.services.redis.error).toContain('ECONNREFUSED');
  });

  it('reports redis unhealthy on an unexpected PING reply', async () => {
    const response = await get({ redis: { pingReply: 'WAT' } });

    expect(response.status).toBe(503);
    const body = (await response.json()) as HealthBody;
    expect(body.services.redis.status).toBe('unhealthy');
  });

  it('treats an unconfigured redis as skipped, not unhealthy', async () => {
    // A single-instance deployment with no Redis is a valid configuration.
    // Reporting it unhealthy would keep the container out of the load balancer
    // forever.
    const response = await get({ redis: null });

    expect(response.status).toBe(200);
    const body = (await response.json()) as HealthBody;
    expect(body.status).toBe('ok');
    expect(body.services.redis.status).toBe('skipped');
  });

  it('names every unhealthy dependency rather than only the first', async () => {
    const response = await get({
      databaseError: 'connection refused',
      authError: 'gotrue down',
    });

    const body = (await response.json()) as HealthBody;
    expect(body.services.database.status).toBe('unhealthy');
    expect(body.services.auth.status).toBe('unhealthy');
    expect(body.services.storage.status).toBe('healthy');
  });

  it('surfaces the real error message, not "[object Object]"', async () => {
    // supabase-js returns error objects, and String() on one yields
    // "[object Object]" — which told an operator nothing.
    const response = await get({ databaseError: 'connection refused' });

    const body = (await response.json()) as HealthBody;
    expect(body.services.database.error).toContain('connection refused');
    expect(body.services.database.error).not.toContain('[object Object]');
  });

  it('reports a latency figure for each probed dependency', async () => {
    const body = (await (await get()).json()) as HealthBody;

    for (const name of ['database', 'storage', 'auth', 'redis']) {
      expect(typeof body.services[name].latencyMs).toBe('number');
    }
  });

  it('does not leak connection strings or secrets in the payload', async () => {
    const serialized = await (await get()).text();

    expect(serialized).not.toMatch(/postgres:\/\//);
    expect(serialized).not.toMatch(/service_role/i);
    expect(serialized).not.toMatch(/SUPABASE_/);
  });
});
