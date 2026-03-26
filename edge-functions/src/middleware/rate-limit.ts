import { createMiddleware } from 'hono/factory';
import type { Context } from 'hono';

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
}

// MARK: - In-Memory Store

const store = new Map<string, RateLimitEntry>();

// Periodic cleanup of expired entries (every 5 minutes)
setInterval(() => {
  const now = Date.now();
  for (const [key, entry] of store) {
    if (now >= entry.resetAt) {
      store.delete(key);
    }
  }
}, 5 * 60 * 1000);

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
  const { max, windowMs, keyExtractor = defaultKeyExtractor } = options;

  return createMiddleware(async (c, next) => {
    const key = keyExtractor(c);
    const now = Date.now();

    let entry = store.get(key);

    if (!entry || now >= entry.resetAt) {
      // New window
      entry = { count: 1, resetAt: now + windowMs };
      store.set(key, entry);
    } else {
      entry.count++;
    }

    // Set rate limit headers
    const remaining = Math.max(0, max - entry.count);
    const resetSeconds = Math.ceil((entry.resetAt - now) / 1000);

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
});

/** Invite validation: 5 attempts per minute per IP (brute force prevention). */
export const rateLimitInvite = createRateLimiter({
  max: 5,
  windowMs: 60 * 1000,
  keyExtractor: ipKeyExtractor,
});

/** Webhook endpoint: 100 requests per minute (RevenueCat volume). */
export const rateLimitWebhook = createRateLimiter({
  max: 100,
  windowMs: 60 * 1000,
  keyExtractor: ipKeyExtractor,
});

export { createRateLimiter };
