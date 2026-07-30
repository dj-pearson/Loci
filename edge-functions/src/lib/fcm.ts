import { createSign } from 'node:crypto';

/**
 * Firebase Cloud Messaging HTTP v1 sender (US-197).
 *
 * The legacy FCM server-key API was decommissioned, so this uses HTTP v1, which
 * requires an OAuth2 access token minted from the service-account key rather than
 * a static key.
 *
 * Shaped deliberately like `apns.ts`: same result contract, same invalid-token
 * semantics, same injectable transport — so `dispatchPush` can treat both
 * platforms uniformly instead of special-casing each.
 */

const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

/** Google access tokens last an hour; refresh early to avoid a race. */
const TOKEN_TTL_SECONDS = 3000;
const DEFAULT_MAX_ATTEMPTS = 3;
const BASE_BACKOFF_MS = 250;

export interface FcmConfig {
  projectId: string;
  clientEmail: string;
  privateKey: string;
}

export interface FcmPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
  collapseKey?: string;
}

export interface FcmResult {
  ok: boolean;
  /** True when FCM says this token will never work again — stop storing it. */
  invalidToken: boolean;
  skipped: boolean;
  status?: number;
  reason?: string;
}

export interface FcmRequest {
  url: string;
  headers: Record<string, string>;
  body: string;
}

export interface FcmResponse {
  status: number;
  body: string;
}

export type FcmTransport = (request: FcmRequest) => Promise<FcmResponse>;

/**
 * FCM error codes meaning the registration token is permanently dead. Anything
 * else (QUOTA_EXCEEDED, INTERNAL, UNAVAILABLE) is worth retrying.
 */
const PERMANENT_TOKEN_FAILURES = new Set([
  'UNREGISTERED',
  'INVALID_ARGUMENT',
  'SENDER_ID_MISMATCH',
]);

function isRetryable(status: number): boolean {
  return status === 429 || status >= 500;
}

export function readFcmConfig(env: NodeJS.ProcessEnv = process.env): FcmConfig | null {
  const raw = env.FCM_SERVICE_ACCOUNT_JSON;
  if (!raw) return null;

  try {
    const parsed = JSON.parse(raw) as {
      project_id?: string;
      client_email?: string;
      private_key?: string;
    };
    if (!parsed.project_id || !parsed.client_email || !parsed.private_key) return null;

    return {
      projectId: parsed.project_id,
      clientEmail: parsed.client_email,
      // Single-line secret stores escape the PEM newlines.
      privateKey: parsed.private_key.includes('\\n')
        ? parsed.private_key.replace(/\\n/g, '\n')
        : parsed.private_key,
    };
  } catch {
    console.error('[fcm] FCM_SERVICE_ACCOUNT_JSON is not valid JSON — push disabled');
    return null;
  }
}

function base64url(input: Buffer | string): string {
  return Buffer.from(input)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

interface CachedToken {
  accessToken: string;
  expiresAtSeconds: number;
}

let cachedToken: CachedToken | null = null;

/** Exposed for tests — the cache would otherwise leak across cases. */
export function resetFcmTokenCache(): void {
  cachedToken = null;
}

/** Builds the RS256 JWT assertion Google exchanges for an access token. */
export function createServiceAccountAssertion(config: FcmConfig, nowMs: number): string {
  const nowSeconds = Math.floor(nowMs / 1000);
  const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = base64url(
    JSON.stringify({
      iss: config.clientEmail,
      scope: SCOPE,
      aud: TOKEN_URL,
      iat: nowSeconds,
      exp: nowSeconds + 3600,
    })
  );
  const signingInput = `${header}.${claims}`;

  const signer = createSign('RSA-SHA256');
  signer.update(signingInput);
  return `${signingInput}.${base64url(signer.sign(config.privateKey))}`;
}

export interface SendFcmOptions {
  config?: FcmConfig | null;
  transport?: FcmTransport;
  maxAttempts?: number;
  sleep?: (ms: number) => Promise<void>;
  now?: () => number;
}

const defaultSleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

const fetchTransport: FcmTransport = async (request) => {
  const response = await fetch(request.url, {
    method: 'POST',
    headers: request.headers,
    body: request.body,
  });
  return { status: response.status, body: await response.text() };
};

async function getAccessToken(
  config: FcmConfig,
  transport: FcmTransport,
  now: () => number
): Promise<string> {
  const nowSeconds = Math.floor(now() / 1000);
  if (cachedToken && cachedToken.expiresAtSeconds > nowSeconds) {
    return cachedToken.accessToken;
  }

  const assertion = createServiceAccountAssertion(config, now());
  const response = await transport({
    url: TOKEN_URL,
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }).toString(),
  });

  if (response.status !== 200) {
    throw new Error(`token exchange failed with ${response.status}: ${response.body}`);
  }

  const parsed = JSON.parse(response.body) as { access_token?: string };
  if (!parsed.access_token) throw new Error('token exchange returned no access_token');

  cachedToken = {
    accessToken: parsed.access_token,
    expiresAtSeconds: nowSeconds + TOKEN_TTL_SECONDS,
  };
  return parsed.access_token;
}

function parseReason(body: string): string | undefined {
  if (!body) return undefined;
  try {
    const parsed = JSON.parse(body) as {
      error?: { status?: string; details?: Array<{ errorCode?: string }> };
    };
    // The precise code lives in details[].errorCode; error.status is the coarse one.
    return (
      parsed.error?.details?.find((d) => d.errorCode)?.errorCode ?? parsed.error?.status
    );
  } catch {
    return undefined;
  }
}

export async function sendFcmPush(
  registrationToken: string,
  payload: FcmPayload,
  options: SendFcmOptions = {}
): Promise<FcmResult> {
  const config = options.config === undefined ? readFcmConfig() : options.config;

  if (!config) {
    console.warn('[fcm] FCM_SERVICE_ACCOUNT_JSON not set — skipping Android push');
    return { ok: false, invalidToken: false, skipped: true, reason: 'NotConfigured' };
  }

  if (!registrationToken) {
    return { ok: false, invalidToken: true, skipped: false, reason: 'EmptyToken' };
  }

  const transport = options.transport ?? fetchTransport;
  const maxAttempts = options.maxAttempts ?? DEFAULT_MAX_ATTEMPTS;
  const sleep = options.sleep ?? defaultSleep;
  const now = options.now ?? Date.now;

  // Data-only message: the Android client builds the notification so the channel,
  // deep link, and copy match its local geofence notifications.
  const body = JSON.stringify({
    message: {
      token: registrationToken,
      data: {
        title: payload.title,
        body: payload.body,
        ...(payload.data ?? {}),
      },
      android: {
        priority: 'HIGH',
        ...(payload.collapseKey ? { collapse_key: payload.collapseKey } : {}),
      },
    },
  });

  let last: FcmResponse | undefined;

  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    try {
      const accessToken = await getAccessToken(config, transport, now);
      last = await transport({
        url: `https://fcm.googleapis.com/v1/projects/${config.projectId}/messages:send`,
        headers: {
          authorization: `Bearer ${accessToken}`,
          'content-type': 'application/json',
        },
        body,
      });
    } catch (error) {
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

    if (last.status === 404 || (reason && PERMANENT_TOKEN_FAILURES.has(reason))) {
      return {
        ok: false,
        invalidToken: true,
        skipped: false,
        status: last.status,
        reason: reason ?? 'UNREGISTERED',
      };
    }

    if (!isRetryable(last.status) || attempt === maxAttempts) {
      return { ok: false, invalidToken: false, skipped: false, status: last.status, reason };
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
