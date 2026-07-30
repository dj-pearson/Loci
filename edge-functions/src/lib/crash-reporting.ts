import * as Sentry from '@sentry/node';
import { log } from './logger.js';

/**
 * Error reporting for the edge sidecar (US-199).
 *
 * Structured logs (US-215) tell you what happened once you go looking. This tells
 * you to go looking — a recurring 500 or a failing nightly cron previously stayed
 * invisible until someone read the container logs by hand.
 *
 * An empty `SENTRY_DSN` disables reporting entirely, so a self-hosted deployment
 * needs no Sentry account.
 */

let initialized = false;

/**
 * Payload keys that must never leave the server. The digest and analyze routes
 * handle transcriptions and coordinates, and the auth routes handle tokens.
 */
const SENSITIVE_KEYS = new Set([
  'apns_token',
  'authorization',
  'cookie',
  'email',
  'fcm_token',
  'invite_code',
  'latitude',
  'location_name',
  'longitude',
  'password',
  'private_key',
  'service_key',
  'signature',
  'token',
  'transcription',
]);

const REDACTED = '[redacted]';
const COORDINATE_PATTERN = /-?\d{1,3}\.\d{4,}/g;
const EMAIL_PATTERN = /[\w.+-]+@[\w-]+\.[\w.]+/g;

/** Strips coordinates and emails from free text such as an exception message. */
export function scrubText(text: string): string {
  return text.replace(EMAIL_PATTERN, REDACTED).replace(COORDINATE_PATTERN, REDACTED);
}

export function scrubObject(value: unknown, depth = 0): unknown {
  if (depth > 4 || value === null) return value;
  if (typeof value === 'string') return scrubText(value);
  if (typeof value !== 'object') return value;
  if (Array.isArray(value)) return value.map((item) => scrubObject(item, depth + 1));

  const output: Record<string, unknown> = {};
  for (const [key, nested] of Object.entries(value as Record<string, unknown>)) {
    output[key] = SENSITIVE_KEYS.has(key.toLowerCase())
      ? REDACTED
      : scrubObject(nested, depth + 1);
  }
  return output;
}

export function initCrashReporting(): void {
  const dsn = process.env.SENTRY_DSN;
  if (!dsn) {
    log.info('SENTRY_DSN not set — error reporting disabled');
    return;
  }

  Sentry.init({
    dsn,
    release: process.env.EDGE_FUNCTION_VERSION ?? '1.0.0',
    environment: process.env.NODE_ENV ?? 'development',
    // Errors are what matter here; traces would multiply payload for little gain.
    tracesSampleRate: 0,
    // Sentry would otherwise attach request headers, cookies, and the client IP.
    sendDefaultPii: false,
    beforeSend(event) {
      if (event.message) event.message = scrubText(event.message);

      for (const exception of event.exception?.values ?? []) {
        if (exception.value) exception.value = scrubText(exception.value);
      }

      if (event.extra) event.extra = scrubObject(event.extra) as typeof event.extra;
      if (event.request) {
        // Never ship a request body or query string: both can carry a transcription.
        delete event.request.data;
        delete event.request.cookies;
        delete event.request.headers;
        delete event.request.query_string;
      }
      return event;
    },
    beforeBreadcrumb(breadcrumb) {
      if (breadcrumb.message) breadcrumb.message = scrubText(breadcrumb.message);
      if (breadcrumb.data) {
        breadcrumb.data = scrubObject(breadcrumb.data) as typeof breadcrumb.data;
      }
      return breadcrumb;
    },
  });

  initialized = true;
  log.info('error reporting initialized');
}

/** Reports an error. No-ops cleanly when Sentry is not configured. */
export function captureError(error: unknown, context: Record<string, unknown> = {}): void {
  if (!initialized) return;
  Sentry.withScope((scope) => {
    scope.setExtras(scrubObject(context) as Record<string, unknown>);
    Sentry.captureException(error);
  });
}

/** Whether reporting is active — exposed so /api/health can report configuration. */
export function isCrashReportingEnabled(): boolean {
  return initialized;
}

/** Test seam: resets module state between cases. */
export function resetCrashReportingForTests(): void {
  initialized = false;
}
