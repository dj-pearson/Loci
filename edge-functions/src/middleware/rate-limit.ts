import { createMiddleware } from 'hono/factory';
import type { Context } from 'hono';
import Redis from 'ioredis';

// MARK: - Types

interface RateLimitEntry {
  count: number;
  resetAt: number;
}

interface RateLimitOptions {
  /** Maximum requests allowed in the window. */
  max: number;
  /** Window duration in milliseconds. */
  windowMs: number;
  /** Key extractor function. Defaults to user ID from auth, falls back to IP. */
  keyExtractor?: (c: Context) => string;
  /** Endpoint identifier for Redis key namespacing. */
  endpoint?: string;
}

interface RateLimitStore {
  /** Increment the counter for a key. Returns { count, resetAt }. */
  increment(key: string, windowMs: number): Promise<RateLimitEntry>;
}

// MARK: - In-Memory Store

class InMemoryStore implements RateLimitStore {
  private store = new Map<string, RateLimitEntry>();
  private cleanupTimer: ReturnType<typeof setInterval>;

  constructor() {
    // Periodic cleanup of expired entries (every 5 minutes)
    this.cleanupTimer = setInterval(() => {
      const now = Date.now();
      for (const [key, entry] of this.store) {
        if (now >= entry.resetAt) {
          this.store.delete(key);
        }
      }
    }, 5 * 60 * 1000);
  }

  async increment(key: string, windowMs: number): Promise<RateLimitEntry> {
    const now = Date.now();
    let entry = this.store.get(key);

    if (!entry || now >= entry.resetAt) {
      entry = { count: 1, resetAt: now + windowMs };
      this.store.set(key, entry);
    } else {
      entry.count++;
    }

    return entry;
  }
}

// MARK: - Redis Store

class RedisStore implements RateLimitStore {
  private client: Redis;

  constructor(client: Redis) {
    this.client = client;
  }

  async increment(key: string, windowMs: number): Promise<RateLimitEntry> {
    const ttlSeconds = Math.ceil(windowMs / 1000);

    // Use INCR + conditional EXPIRE for atomic counter with TTL.
    // If the key is new (count === 1), set the expiry.
    const count = await this.client.incr(key);

    if (count === 1) {
      await this.client.expire(key, ttlSeconds);
    }

    // Get the remaining TTL to compute resetAt
    const ttl = await this.client.ttl(key);
    // ttl can be -1 (no expiry) or -2 (key gone); handle gracefully
    const resetAt =
      ttl > 0 ? Date.now() + ttl * 1000 : Date.now() + windowMs;

    return { count, resetAt };
  }
}

// MARK: - Store Factory

let sharedRedisClient: Redis | null = null;
let redisConnectionFailed = false;
let activeStore: RateLimitStore | null = null;

function getStore(): RateLimitStore {
  if (activeStore) return activeStore;

  const redisUrl = process.env.REDIS_URL;

  if (!redisUrl || redisConnectionFailed) {
    if (!redisUrl) {
      console.warn(
        '[rate-limit] REDIS_URL not set — using in-memory rate limiting',
      );
    }
    activeStore = new InMemoryStore();
    return activeStore;
  }

  try {
    sharedRedisClient = new Redis(redisUrl, {
      maxRetriesPerRequest: 1,
      retryStrategy(times) {
        // Stop retrying after 3 attempts and fall back to in-memory
        if (times > 3) {
          return null;
        }
        return Math.min(times * 200, 1000);
      },
      lazyConnect: false,
      enableOfflineQueue: false,
    });

    sharedRedisClient.on('error', (err) => {
      console.warn(
        `[rate-limit] Redis connection error, falling back to in-memory store: ${err.message}`,
      );
      redisConnectionFailed = true;
      sharedRedisClient = null;
      activeStore = new InMemoryStore();
    });

    activeStore = new RedisStore(sharedRedisClient);
    return activeStore;
  } catch (err) {
    console.warn(
      `[rate-limit] Failed to connect to Redis, falling back to in-memory store: ${err instanceof Error ? err.message : String(err)}`,
    );
    redisConnectionFailed = true;
    activeStore = new InMemoryStore();
    return activeStore;
  }
}

// MARK: - Fallback-Aware Increment

const fallbackStore = new InMemoryStore();

async function safeIncrement(
  store: RateLimitStore,
  key: string,
  windowMs: number,
): Promise<RateLimitEntry> {
  try {
    return await store.increment(key, windowMs);
  } catch (err) {
    // Redis operation failed at runtime — degrade to in-memory for this request
    console.warn(
      `[rate-limit] Redis operation failed, using in-memory fallback: ${err instanceof Error ? err.message : String(err)}`,
    );
    return fallbackStore.increment(key, windowMs);
  }
}

// MARK: - Key Extractors

function defaultKeyExtractor(c: Context): string {
  // Prefer authenticated user ID, fall back to IP
  const userId = c.get('userId') as string | undefined;
  if (userId) return `user:${userId}`;

  const ip =
    c.req.header('x-forwarded-for')?.split(',')[0]?.trim() ||
    c.req.header('x-real-ip') ||
    'unknown';
  return `ip:${ip}`;
}

function ipKeyExtractor(c: Context): string {
  const ip =
    c.req.header('x-forwarded-for')?.split(',')[0]?.trim() ||
    c.req.header('x-real-ip') ||
    'unknown';
  return `ip:${ip}`;
}

// MARK: - Middleware Factory

function createRateLimiter(options: RateLimitOptions) {
  const {
    max,
    windowMs,
    keyExtractor = defaultKeyExtractor,
    endpoint = 'default',
  } = options;

  return createMiddleware(async (c, next) => {
    const store = getStore();
    const userKey = keyExtractor(c);
    const redisKey = `ratelimit:${endpoint}:${userKey}`;

    const entry = await safeIncrement(store, redisKey, windowMs);

    // Set rate limit headers
    const remaining = Math.max(0, max - entry.count);
    const resetSeconds = Math.ceil((entry.resetAt - Date.now()) / 1000);

    c.header('X-RateLimit-Limit', String(max));
    c.header('X-RateLimit-Remaining', String(remaining));
    c.header('X-RateLimit-Reset', String(Math.ceil(entry.resetAt / 1000)));

    if (entry.count > max) {
      c.header('Retry-After', String(resetSeconds));
      return c.json(
        {
          error: 'Too Many Requests',
          retryAfter: resetSeconds,
        },
        429,
      );
    }

    await next();
  });
}

// MARK: - Pre-configured Middlewares

/** Default rate limit: 60 requests per minute per user. */
export const rateLimitDefault = createRateLimiter({
  max: 60,
  windowMs: 60 * 1000,
  endpoint: 'default',
});

/** Invite validation: 5 attempts per minute per IP (brute force prevention). */
export const rateLimitInvite = createRateLimiter({
  max: 5,
  windowMs: 60 * 1000,
  keyExtractor: ipKeyExtractor,
  endpoint: 'invite',
});

/** Webhook endpoint: 100 requests per minute (RevenueCat volume). */
export const rateLimitWebhook = createRateLimiter({
  max: 100,
  windowMs: 60 * 1000,
  keyExtractor: ipKeyExtractor,
  endpoint: 'webhook',
});

/** Health check: 10 requests per minute per IP. */
export const rateLimitHealth = createRateLimiter({
  max: 10,
  windowMs: 60 * 1000,
  keyExtractor: ipKeyExtractor,
  endpoint: 'health',
});

/** Auth endpoints: 5 attempts per 15 minutes per IP (US-146, in-memory fallback). */
export const rateLimitAuth = createRateLimiter({
  max: 5,
  windowMs: 15 * 60 * 1000,
  keyExtractor: ipKeyExtractor,
  endpoint: 'auth',
});

export { createRateLimiter };

/**
 * US-215: exposed so `/api/health` can report Redis status. The health endpoint
 * previously checked database, storage, and auth but not Redis — yet Redis backs
 * auth rate-limit persistence, so losing it silently degrades brute-force
 * protection to per-instance in-memory counters.
 *
 * Returns null when Redis is not configured or has already failed over, which the
 * health route reports as `skipped` rather than `unhealthy`: an intentional
 * single-instance deployment with no Redis is a valid configuration.
 */
export function getRedisClientForHealthCheck(): Redis | null {
  if (!process.env.REDIS_URL || redisConnectionFailed) return null;
  // Ensure the shared client exists; getStore() is the only thing that creates it.
  getStore();
  return sharedRedisClient;
}
