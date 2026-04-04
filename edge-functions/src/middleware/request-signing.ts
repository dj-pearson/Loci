import { createMiddleware } from 'hono/factory';
import { createHmac } from 'node:crypto';

const MAX_TIMESTAMP_DRIFT_MS = 5 * 60 * 1000; // 5 minutes

/**
 * Middleware that validates HMAC-SHA256 request signatures on sensitive routes.
 *
 * Expected headers:
 * - X-Request-Timestamp: ISO 8601 timestamp
 * - X-Request-Signature: HMAC-SHA256 hex digest of "METHOD\nPATH\nTIMESTAMP\nBODY_SHA256"
 *
 * Skipped if REQUEST_SIGNING_KEY is not configured (development mode).
 */
export const requestSigningMiddleware = createMiddleware(async (c, next) => {
  const signingKey = process.env.REQUEST_SIGNING_KEY;

  // Skip validation if signing key is not configured (dev mode)
  if (!signingKey) {
    await next();
    return;
  }

  const timestamp = c.req.header('x-request-timestamp');
  const signature = c.req.header('x-request-signature');

  if (!timestamp || !signature) {
    return c.json({ error: 'Missing request signature headers' }, 401);
  }

  // Validate timestamp is within acceptable drift
  const requestTime = new Date(timestamp).getTime();
  const now = Date.now();

  if (isNaN(requestTime) || Math.abs(now - requestTime) > MAX_TIMESTAMP_DRIFT_MS) {
    return c.json({ error: 'Request timestamp expired or invalid' }, 401);
  }

  // Reconstruct the signing payload
  const method = c.req.method;
  const path = new URL(c.req.url).pathname;
  const body = await c.req.text();

  const bodyHash = createHmac('sha256', '')
    .update(body || '')
    .digest('hex');

  // For body hash, use plain SHA-256 (not HMAC) to match client
  const { createHash } = await import('node:crypto');
  const actualBodyHash = createHash('sha256')
    .update(body || '')
    .digest('hex');

  const payload = `${method}\n${path}\n${timestamp}\n${actualBodyHash}`;

  const expectedSignature = createHmac('sha256', signingKey)
    .update(payload)
    .digest('hex');

  // Timing-safe comparison
  const { timingSafeEqual } = await import('node:crypto');
  const sigBuffer = Buffer.from(signature, 'hex');
  const expectedBuffer = Buffer.from(expectedSignature, 'hex');

  if (sigBuffer.length !== expectedBuffer.length || !timingSafeEqual(sigBuffer, expectedBuffer)) {
    return c.json({ error: 'Invalid request signature' }, 401);
  }

  await next();
});
