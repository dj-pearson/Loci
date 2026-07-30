import { afterEach, describe, expect, it, vi } from 'vitest';

interface HealthFakeOptions {
  databaseError?: string;
  storageBuckets?: Array<{ name: string }> | null;
  storageError?: string;
  authError?: string;
}

interface HealthBody {
  status: string;
  services: Record<string, { status: string; error?: string }>;
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

vi.mock('../src/middleware/auth.js', () => ({
  getSupabaseAdmin: () => fake,
  authMiddleware: async (_c: unknown, next: () => Promise<void>) => next(),
}));

async function get(options: HealthFakeOptions = {}) {
  fake = healthFake(options);
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

  it('does not leak connection strings or secrets in the payload', async () => {
    const serialized = await (await get()).text();

    expect(serialized).not.toMatch(/postgres:\/\//);
    expect(serialized).not.toMatch(/service_role/i);
    expect(serialized).not.toMatch(/SUPABASE_/);
  });
});
