import { createPrivateKey, createSign } from 'node:crypto';
import http2 from 'node:http2';

/**
 * APNs HTTP/2 provider (US-196).
 *
 * `push-digest.ts` previously called a `sendApnsPush()` that only wrote to
 * console and returned true, so the weekly digest cron reported successful
 * delivery while sending nothing. This module does the real thing:
 *
 * - mints an ES256 provider JWT from the .p8 auth key and caches it,
 * - POSTs to /3/device/<token> over HTTP/2,
 * - reports per-token outcomes so callers can prune dead tokens,
 * - retries only what is worth retrying.
 */

const PRODUCTION_HOST = 'https://api.push.apple.com';
const SANDBOX_HOST = 'https://api.sandbox.push.apple.com';

/** Apple accepts a provider token for one hour; refresh early to avoid races. */
const TOKEN_TTL_SECONDS = 3000; // 50 minutes
const DEFAULT_MAX_ATTEMPTS = 3;
const BASE_BACKOFF_MS = 250;

export interface ApnsConfig {
  keyP8: string;
  keyId: string;
  teamId: string;
  topic: string;
  host: string;
}

export interface ApnsPayload {
  title: string;
  body: string;
  /** Merged into the payload alongside `aps`, for deep-linking on tap. */
  data?: Record<string, unknown>;
  threadId?: string;
  collapseId?: string;
}

export interface ApnsResult {
  ok: boolean;
  /** True when APNs says this token will never work again — stop storing it. */
  invalidToken: boolean;
  /** True when APNs is not configured, so nothing was attempted. */
  skipped: boolean;
  status?: number;
  reason?: string;
}

export interface ApnsRequest {
  host: string;
  path: string;
  headers: Record<string, string>;
  body: string;
}

export interface ApnsResponse {
  status: number;
  body: string;
}

export type ApnsTransport = (request: ApnsRequest) => Promise<ApnsResponse>;

/**
 * `reason` values that mean the device token is permanently dead. Retrying these
 * wastes requests and, worse, leaves a token in the database that will never
 * deliver — so callers clear it instead.
 */
const PERMANENT_TOKEN_FAILURES = new Set([
  'BadDeviceToken',
  'Unregistered',
  'DeviceTokenNotForTopic',
]);

/** Statuses worth another attempt: throttling and Apple-side faults. */
function isRetryable(status: number): boolean {
  return status === 429 || status >= 500;
}

export function readApnsConfig(env: NodeJS.ProcessEnv = process.env): ApnsConfig | null {
  const keyP8 = env.APNS_KEY_P8;
  const keyId = env.APNS_KEY_ID;
  const teamId = env.APNS_TEAM_ID;

  if (!keyP8 || !keyId || !teamId) {
    return null;
  }

  return {
    // GitHub/Coolify secrets can only carry single-line values, so the PEM
    // arrives with literal \n sequences that have to be restored.
    keyP8: keyP8.includes('\\n') ? keyP8.replace(/\\n/g, '\n') : keyP8,
    keyId,
    teamId,
    topic: env.APNS_TOPIC || 'app.lociate.ios',
    host: env.APNS_HOST || (env.NODE_ENV === 'production' ? PRODUCTION_HOST : SANDBOX_HOST),
  };
}

function base64url(input: Buffer | string): string {
  return Buffer.from(input)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

interface CachedToken {
  jwt: string;
  expiresAtSeconds: number;
}

let cachedToken: CachedToken | null = null;

/** Exposed for tests — the cache would otherwise leak across cases. */
export function resetApnsTokenCache(): void {
  cachedToken = null;
}

export function createProviderToken(config: ApnsConfig, nowMs: number = Date.now()): string {
  const nowSeconds = Math.floor(nowMs / 1000);

  if (cachedToken && cachedToken.expiresAtSeconds > nowSeconds) {
    return cachedToken.jwt;
  }

  const header = base64url(JSON.stringify({ alg: 'ES256', kid: config.keyId, typ: 'JWT' }));
  const claims = base64url(JSON.stringify({ iss: config.teamId, iat: nowSeconds }));
  const signingInput = `${header}.${claims}`;

  const key = createPrivateKey(config.keyP8);
  const signer = createSign('SHA256');
  signer.update(signingInput);
  // APNs expects a JOSE signature (raw r||s), not the DER encoding Node emits
  // by default. 'ieee-p1363' is exactly that concatenated form.
  const signature = signer.sign({ key, dsaEncoding: 'ieee-p1363' });

  const jwt = `${signingInput}.${base64url(signature)}`;
  cachedToken = { jwt, expiresAtSeconds: nowSeconds + TOKEN_TTL_SECONDS };
  return jwt;
}

function buildBody(payload: ApnsPayload): string {
  return JSON.stringify({
    aps: {
      alert: { title: payload.title, body: payload.body },
      sound: 'default',
      'thread-id': payload.threadId,
    },
    ...payload.data,
  });
}

function parseReason(body: string): string | undefined {
  if (!body) return undefined;
  try {
    const parsed = JSON.parse(body) as { reason?: string };
    return parsed.reason;
  } catch {
    return undefined;
  }
}

/** Real HTTP/2 transport. Kept separate so tests can substitute a fake. */
export const http2Transport: ApnsTransport = (request) =>
  new Promise<ApnsResponse>((resolve, reject) => {
    const session = http2.connect(request.host);
    let settled = false;

    const finish = (fn: () => void) => {
      if (settled) return;
      settled = true;
      session.close();
      fn();
    };

    session.on('error', (error) => finish(() => reject(error)));

    const stream = session.request({
      ':method': 'POST',
      ':path': request.path,
      ...request.headers,
    });

    let status = 0;
    let body = '';

    stream.on('response', (headers) => {
      status = Number(headers[':status'] ?? 0);
    });
    stream.setEncoding('utf8');
    stream.on('data', (chunk: string) => {
      body += chunk;
    });
    stream.on('end', () => finish(() => resolve({ status, body })));
    stream.on('error', (error) => finish(() => reject(error)));

    stream.end(request.body);
  });

export interface SendApnsOptions {
  config?: ApnsConfig | null;
  transport?: ApnsTransport;
  maxAttempts?: number;
  /** Injected so tests do not have to actually wait out the backoff. */
  sleep?: (ms: number) => Promise<void>;
  now?: () => number;
}

const defaultSleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

export async function sendApnsPush(
  deviceToken: string,
  payload: ApnsPayload,
  options: SendApnsOptions = {}
): Promise<ApnsResult> {
  const config = options.config === undefined ? readApnsConfig() : options.config;

  if (!config) {
    // Deliberately a no-op rather than a throw: a self-hosted deployment without
    // APNs credentials should still run the rest of the sidecar.
    console.warn('[apns] APNS_KEY_P8/APNS_KEY_ID/APNS_TEAM_ID not set — skipping push');
    return { ok: false, invalidToken: false, skipped: true, reason: 'NotConfigured' };
  }

  if (!deviceToken) {
    return { ok: false, invalidToken: true, skipped: false, reason: 'EmptyDeviceToken' };
  }

  const transport = options.transport ?? http2Transport;
  const maxAttempts = options.maxAttempts ?? DEFAULT_MAX_ATTEMPTS;
  const sleep = options.sleep ?? defaultSleep;
  const now = options.now ?? Date.now;
  const body = buildBody(payload);

  let last: ApnsResponse | undefined;

  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    const headers: Record<string, string> = {
      authorization: `bearer ${createProviderToken(config, now())}`,
      'apns-topic': config.topic,
      'apns-push-type': 'alert',
      'apns-priority': '10',
      'content-type': 'application/json',
    };
    if (payload.collapseId) {
      headers['apns-collapse-id'] = payload.collapseId;
    }

    try {
      last = await transport({
        host: config.host,
        path: `/3/device/${deviceToken}`,
        headers,
        body,
      });
    } catch (error) {
      // Network/TLS failure — same retry treatment as a 5xx.
      if (attempt === maxAttempts) {
        return {
          ok: false,
          invalidToken: false,
          skipped: false,
          reason: `TransportError: ${String(error)}`,
        };
      }
      await sleep(BASE_BACKOFF_MS * 2 ** (attempt - 1));
      continue;
    }

    if (last.status === 200) {
      return { ok: true, invalidToken: false, skipped: false, status: 200 };
    }

    const reason = parseReason(last.body);

    // 410 Gone always means the token is dead; on 400 it depends on the reason.
    if (last.status === 410 || (reason && PERMANENT_TOKEN_FAILURES.has(reason))) {
      return {
        ok: false,
        invalidToken: true,
        skipped: false,
        status: last.status,
        reason: reason ?? 'Unregistered',
      };
    }

    if (!isRetryable(last.status) || attempt === maxAttempts) {
      return {
        ok: false,
        invalidToken: false,
        skipped: false,
        status: last.status,
        reason,
      };
    }

    await sleep(BASE_BACKOFF_MS * 2 ** (attempt - 1));
  }

  return {
    ok: false,
    invalidToken: false,
    skipped: false,
    status: last?.status,
    reason: parseReason(last?.body ?? ''),
  };
}
