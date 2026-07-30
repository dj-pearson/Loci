import { randomUUID } from 'node:crypto';
import { createMiddleware } from 'hono/factory';

/**
 * Structured JSON logging (US-215).
 *
 * Request handling previously emitted nothing, and everything else used bare
 * `console.log` with interpolated prose — unqueryable in a log aggregator, and
 * with no way to correlate the lines belonging to one request. Every line is now
 * a single JSON object with a stable shape.
 */

export type LogLevel = 'debug' | 'info' | 'warn' | 'error';

const LEVEL_ORDER: Record<LogLevel, number> = {
  debug: 10,
  info: 20,
  warn: 30,
  error: 40,
};

function minimumLevel(): number {
  const configured = (process.env.LOG_LEVEL ?? 'info').toLowerCase() as LogLevel;
  return LEVEL_ORDER[configured] ?? LEVEL_ORDER.info;
}

/**
 * Keys whose values are never safe to log. Matching is on the key, not the value,
 * because a token's shape is not reliably detectable — and one leaked
 * Authorization header in an aggregator is a credential disclosure.
 */
const REDACTED_KEYS = new Set([
  'authorization',
  'apns_token',
  'apnstoken',
  'cookie',
  'fcm_token',
  'fcmtoken',
  'invite_code',
  'invitecode',
  'password',
  'secret',
  'service_key',
  'signature',
  'token',
  'transcription',
  'x-request-signature',
  'x-revenuecat-signature',
]);

const REDACTED = '[redacted]';

function redact(value: unknown, depth = 0): unknown {
  if (depth > 4 || value === null || typeof value !== 'object') return value;
  if (Array.isArray(value)) return value.map((item) => redact(item, depth + 1));

  const output: Record<string, unknown> = {};
  for (const [key, nested] of Object.entries(value as Record<string, unknown>)) {
    output[key] = REDACTED_KEYS.has(key.toLowerCase())
      ? REDACTED
      : redact(nested, depth + 1);
  }
  return output;
}

export interface LogFields {
  [key: string]: unknown;
}

function emit(level: LogLevel, message: string, fields: LogFields = {}): void {
  if (LEVEL_ORDER[level] < minimumLevel()) return;

  const line = {
    level,
    msg: message,
    time: new Date().toISOString(),
    service: 'lociate-edge',
    ...(redact(fields) as LogFields),
  };

  // stderr for warn/error so a container log driver can split streams.
  const stream = LEVEL_ORDER[level] >= LEVEL_ORDER.warn ? console.error : console.log;
  stream(JSON.stringify(line));
}

export const log = {
  debug: (message: string, fields?: LogFields) => emit('debug', message, fields),
  info: (message: string, fields?: LogFields) => emit('info', message, fields),
  warn: (message: string, fields?: LogFields) => emit('warn', message, fields),
  error: (message: string, fields?: LogFields) => emit('error', message, fields),
};

/** Serializes an unknown thrown value into loggable fields. */
export function errorFields(error: unknown): LogFields {
  if (error instanceof Error) {
    return {
      error: error.message,
      errorName: error.name,
      // Stacks are large; keep them out of info-level noise but present on errors.
      stack: error.stack?.split('\n').slice(0, 8).join('\n'),
    };
  }
  return { error: String(error) };
}

export interface RequestLogEnv {
  Variables: {
    requestId: string;
  };
}

/**
 * Logs one line per request with a correlation id, and echoes that id back in
 * `X-Request-Id` so a user-reported failure can be traced to its log line.
 *
 * Deliberately has no try/catch: Hono resolves a thrown handler error through its
 * own `onError` before control returns here, so `await next()` does not reject and
 * a catch block would be unreachable. The thrown detail is logged by the
 * `app.onError` handler in index.ts; this middleware records the outcome, deriving
 * severity from the resulting status.
 */
export const requestLogger = createMiddleware<RequestLogEnv>(async (c, next) => {
  // Honour an upstream id (Traefik/Kong) so a request keeps one id end to end.
  const requestId = c.req.header('x-request-id') ?? randomUUID();
  c.set('requestId', requestId);
  c.header('X-Request-Id', requestId);

  const startedAt = Date.now();
  const route = new URL(c.req.url).pathname;

  await next();

  const durationMs = Date.now() - startedAt;
  const status = c.res.status;

  // A 5xx is an incident, a 4xx is a client problem, everything else is routine.
  const level: LogLevel = status >= 500 ? 'error' : status >= 400 ? 'warn' : 'info';

  emit(level, 'request', {
    requestId,
    method: c.req.method,
    route,
    status,
    durationMs,
  });
});

/**
 * Wraps a scheduled job so its outcome is always recorded — previously a cron
 * that threw logged nothing and the run simply vanished.
 */
export async function runScheduledJob<T>(
  name: string,
  job: () => Promise<T>,
  options: { onError?: (error: unknown) => void } = {}
): Promise<T | undefined> {
  const startedAt = Date.now();
  log.info('cron started', { job: name });

  try {
    const result = await job();
    log.info('cron completed', {
      job: name,
      durationMs: Date.now() - startedAt,
      ...(result && typeof result === 'object' ? (result as LogFields) : { result }),
    });
    return result;
  } catch (error) {
    log.error('cron failed', {
      job: name,
      durationMs: Date.now() - startedAt,
      ...errorFields(error),
    });
    options.onError?.(error);
    return undefined;
  }
}
