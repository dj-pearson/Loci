import { Hono } from 'hono';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * `ioredis` is imported at module load. Stubbing it keeps these tests on the
 * in-memory store, which is also the production fallback path — so this covers
 * the behaviour a deployment gets when Redis is down.
 */
vi.mock('ioredis', () => ({
  default: class {
    on() {}
    async incr() {
      throw new Error('redis unavailable');
    }
    async expire() {}
    async ttl() {
      return -1;
    }
  },
}));

async function loadLimiters() {
  vi.resetModules();
  return import('../src/middleware/rate-limit.js');
}

function appWith(middleware: Parameters<Hono['use']>[1]) {
  const app = new Hono();
  app.use('/x', middleware);
  app.get('/x', (c) => c.json({ ok: true }));
  return app;
}

async function hit(app: Hono, ip = '203.0.113.7') {
  return app.request('/x', { headers: { 'x-forwarded-for': ip } });
}

beforeEach(() => {
  delete process.env.REDIS_URL;
  vi.spyOn(console, 'warn').mockImplementation(() => {});
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe('rate limiting', () => {
  it('allows requests up to the limit and sets the standard headers', async () => {
    const { createRateLimiter } = await loadLimiters();
    const app = appWith(createRateLimiter({ max: 3, windowMs: 60_000, endpoint: 'test-allow' }));

    const first = await hit(app);
    expect(first.status).toBe(200);
    expect(first.headers.get('X-RateLimit-Limit')).toBe('3');
    expect(first.headers.get('X-RateLimit-Remaining')).toBe('2');
    expect(first.headers.get('X-RateLimit-Reset')).toBeTruthy();

    expect((await hit(app)).status).toBe(200);
    expect((await hit(app)).headers.get('X-RateLimit-Remaining')).toBe('0');
  });

  it('returns 429 with Retry-After once the limit is exceeded', async () => {
    const { createRateLimiter } = await loadLimiters();
    const app = appWith(createRateLimiter({ max: 2, windowMs: 60_000, endpoint: 'test-429' }));

    await hit(app);
    await hit(app);
    const blocked = await hit(app);

    expect(blocked.status).toBe(429);
    expect(Number(blocked.headers.get('Retry-After'))).toBeGreaterThan(0);
    await expect(blocked.json()).resolves.toMatchObject({ error: 'Too Many Requests' });
  });

  it('counts per IP, so one client cannot exhaust another', async () => {
    const { createRateLimiter } = await loadLimiters();
    const app = appWith(createRateLimiter({ max: 1, windowMs: 60_000, endpoint: 'test-per-ip' }));

    expect((await hit(app, '198.51.100.1')).status).toBe(200);
    expect((await hit(app, '198.51.100.1')).status).toBe(429);
    // A different client starts with a clean budget.
    expect((await hit(app, '198.51.100.2')).status).toBe(200);
  });

  it('takes the first entry of a multi-hop x-forwarded-for header', async () => {
    const { createRateLimiter } = await loadLimiters();
    const app = appWith(createRateLimiter({ max: 1, windowMs: 60_000, endpoint: 'test-xff' }));

    await app.request('/x', { headers: { 'x-forwarded-for': '198.51.100.9, 10.0.0.1' } });
    const second = await app.request('/x', {
      headers: { 'x-forwarded-for': '198.51.100.9, 10.0.0.2' },
    });

    // Same real client despite a different proxy hop.
    expect(second.status).toBe(429);
  });

  it('resets the budget after the window elapses', async () => {
    const { createRateLimiter } = await loadLimiters();
    const app = appWith(createRateLimiter({ max: 1, windowMs: 20, endpoint: 'test-window' }));

    expect((await hit(app)).status).toBe(200);
    expect((await hit(app)).status).toBe(429);

    await new Promise((resolve) => setTimeout(resolve, 30));
    expect((await hit(app)).status).toBe(200);
  });

  it('degrades to in-memory counting when the Redis store throws', async () => {
    // REDIS_URL is set, but the stubbed client fails every incr. Requests must
    // still be counted rather than erroring or passing through unlimited.
    process.env.REDIS_URL = 'redis://localhost:6379';
    const { createRateLimiter } = await loadLimiters();
    const app = appWith(createRateLimiter({ max: 1, windowMs: 60_000, endpoint: 'test-fallback' }));

    expect((await hit(app)).status).toBe(200);
    expect((await hit(app)).status).toBe(429);
  });

  it('configures the documented limits for each endpoint class', async () => {
    const limiters = await loadLimiters();
    const cases: Array<[keyof typeof limiters, string]> = [
      ['rateLimitDefault', '60'],
      ['rateLimitInvite', '5'],
      ['rateLimitWebhook', '100'],
      ['rateLimitHealth', '10'],
      ['rateLimitAuth', '5'],
    ];

    for (const [name, expected] of cases) {
      const app = appWith(limiters[name] as Parameters<Hono['use']>[1]);
      const response = await hit(app, `192.0.2.${cases.findIndex(([n]) => n === name) + 1}`);
      expect(response.headers.get('X-RateLimit-Limit'), name as string).toBe(expected);
    }
  });
});
