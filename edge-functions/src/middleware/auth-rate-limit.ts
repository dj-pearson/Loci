import { createMiddleware } from 'hono/factory';
import type { Context } from 'hono';
import { getSupabaseAdmin } from './auth.js';

// MARK: - Types

interface LoginAttemptRecord {
  email: string;
  ip: string;
  success: boolean;
  userAgent?: string;
  failureReason?: string;
}

interface LockoutStatus {
  is_locked_out: boolean;
  lockout_seconds_remaining: number;
  reason: string | null;
  recent_failures: number;
}

// MARK: - Auth Rate Limit Middleware (US-146)

/**
 * Auth-specific rate limiting middleware that checks the login_attempts
 * table for email and IP-based lockouts before allowing auth attempts.
 *
 * Applied to auth proxy endpoints (sign-in, sign-up).
 * Uses database-backed tracking that survives restarts and works
 * across multiple instances.
 */
export const authRateLimit = createMiddleware(async (c, next) => {
  // Only apply to POST requests (auth attempts)
  if (c.req.method !== 'POST') {
    await next();
    return;
  }

  const ip = extractIP(c);
  let email: string | undefined;

  try {
    // Try to extract email from request body
    const body = await c.req.json();
    email = body?.email?.toLowerCase();
  } catch {
    // Body might not be JSON or might not have email
  }

  if (!email) {
    await next();
    return;
  }

  // Check lockout status
  const supabase = getSupabaseAdmin();
  const { data: lockoutData, error } = await supabase.rpc('check_auth_lockout', {
    p_email: email,
    p_ip: ip,
  });

  if (error) {
    // If lockout check fails, log and allow through (fail-open for availability)
    console.error('[auth-rate-limit] Lockout check failed:', error.message);
    await next();
    return;
  }

  const lockout = lockoutData?.[0] as LockoutStatus | undefined;
  if (lockout?.is_locked_out) {
    const retryAfter = Math.max(1, lockout.lockout_seconds_remaining);
    const minutes = Math.ceil(retryAfter / 60);

    console.warn(
      JSON.stringify({
        event: 'auth_lockout_triggered',
        email: hashEmail(email),
        ip,
        reason: lockout.reason,
        recentFailures: lockout.recent_failures,
        retryAfterSeconds: retryAfter,
      }),
    );

    c.header('Retry-After', String(retryAfter));
    return c.json(
      {
        error: `Too many login attempts. Try again in ${minutes} minute${minutes === 1 ? '' : 's'}.`,
        retryAfter,
      },
      429,
    );
  }

  await next();
});

// MARK: - Attempt Recording

/**
 * Record a login attempt (success or failure) to the database.
 * Call this after authentication completes.
 */
export async function recordLoginAttempt(record: LoginAttemptRecord): Promise<void> {
  const supabase = getSupabaseAdmin();

  const { error } = await supabase.rpc('record_login_attempt', {
    p_email: record.email.toLowerCase(),
    p_ip: record.ip,
    p_success: record.success,
    p_user_agent: record.userAgent ?? null,
    p_failure_reason: record.failureReason ?? null,
  });

  if (error) {
    console.error('[auth-rate-limit] Failed to record attempt:', error.message);
  }

  // Structured logging for monitoring/alerting
  console.log(
    JSON.stringify({
      event: record.success ? 'auth_success' : 'auth_failure',
      email: hashEmail(record.email),
      ip: record.ip,
      failureReason: record.failureReason,
      timestamp: new Date().toISOString(),
    }),
  );
}

// MARK: - Verify Limits Route Handler

/**
 * GET /api/auth/verify-limits?email=xxx
 * Returns lockout status for a given email (used by iOS/Android client pre-check).
 *
 * US-150: Uses consistent response timing to prevent timing-based email enumeration.
 */
export async function verifyLimits(c: Context) {
  const startTime = Date.now();
  const MIN_RESPONSE_TIME_MS = 200; // Consistent timing to prevent enumeration

  const email = c.req.query('email')?.toLowerCase();
  if (!email) {
    await enforceMinResponseTime(startTime, MIN_RESPONSE_TIME_MS);
    return c.json({ error: 'email parameter required' }, 400);
  }

  const ip = extractIP(c);
  const supabase = getSupabaseAdmin();

  const { data, error } = await supabase.rpc('check_auth_lockout', {
    p_email: email,
    p_ip: ip,
  });

  if (error) {
    await enforceMinResponseTime(startTime, MIN_RESPONSE_TIME_MS);
    return c.json({ error: 'Failed to check lockout status' }, 500);
  }

  const lockout = data?.[0] as LockoutStatus | undefined;

  // US-150: Consistent response timing regardless of email existence
  await enforceMinResponseTime(startTime, MIN_RESPONSE_TIME_MS);

  return c.json({
    isLockedOut: lockout?.is_locked_out ?? false,
    retryAfterSeconds: lockout?.lockout_seconds_remaining ?? 0,
    recentFailures: lockout?.recent_failures ?? 0,
  });
}

/**
 * US-150: Enforce minimum response time to prevent timing-based enumeration.
 * Pads the response to a consistent duration so attackers can't determine
 * whether an email exists based on response speed.
 */
async function enforceMinResponseTime(startTime: number, minMs: number): Promise<void> {
  const elapsed = Date.now() - startTime;
  if (elapsed < minMs) {
    await new Promise((resolve) => setTimeout(resolve, minMs - elapsed));
  }
}

// MARK: - Helpers

function extractIP(c: Context): string {
  return (
    c.req.header('x-forwarded-for')?.split(',')[0]?.trim() ||
    c.req.header('x-real-ip') ||
    '0.0.0.0'
  );
}

/** Hash email for logging (don't log plaintext emails). */
function hashEmail(email: string): string {
  // Simple deterministic hash for logging — not cryptographic
  const parts = email.split('@');
  if (parts.length === 2) {
    const localPart = parts[0];
    const masked = localPart.slice(0, 2) + '***';
    return `${masked}@${parts[1]}`;
  }
  return '***';
}
