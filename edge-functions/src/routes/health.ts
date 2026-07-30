import { Hono } from 'hono';
import { getSupabaseAdmin } from '../middleware/auth.js';
import { getRedisClientForHealthCheck } from '../middleware/rate-limit.js';
import { log } from '../lib/logger.js';

const health = new Hono();

const startTime = Date.now();
const VERSION = process.env.EDGE_FUNCTION_VERSION || '1.0.0';

/** A single dependency probe that hangs must not hang the whole health check. */
const PROBE_TIMEOUT_MS = 3000;

interface ServiceStatus {
  status: 'healthy' | 'unhealthy' | 'skipped';
  latencyMs?: number;
  error?: string;
}

/**
 * US-215: the probes used `String(e)`, which renders a supabase-js error object as
 * the literal "[object Object]" — so the health payload and its log line told an
 * operator nothing about what had actually failed.
 */
function describeError(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (error && typeof error === 'object') {
    const candidate = error as { message?: unknown; error?: unknown; code?: unknown };
    if (typeof candidate.message === 'string') {
      return candidate.code ? `${candidate.message} (${String(candidate.code)})` : candidate.message;
    }
    if (typeof candidate.error === 'string') return candidate.error;
    try {
      return JSON.stringify(error);
    } catch {
      return 'unserializable error';
    }
  }
  return String(error);
}

/**
 * US-215: without a timeout a wedged TCP connection makes /api/health hang until
 * the container healthcheck's own timeout fires, which reads as a total outage
 * rather than one degraded dependency.
 */
async function withTimeout<T>(probe: PromiseLike<T>, label: string): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      probe,
      new Promise<never>((_resolve, reject) => {
        timer = setTimeout(
          () => reject(new Error(`${label} probe timed out after ${PROBE_TIMEOUT_MS}ms`)),
          PROBE_TIMEOUT_MS
        );
      }),
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

// GET /api/health — no authentication required
health.get('/', async (c) => {
  const supabase = getSupabaseAdmin();

  const [database, storage, auth, redis] = await Promise.all([
    checkDatabase(supabase),
    checkStorage(supabase),
    checkAuth(supabase),
    checkRedis(),
  ]);

  const services = { database, storage, auth, redis };

  // `skipped` is not a failure: a single-instance deployment with no Redis is a
  // valid configuration, and reporting it unhealthy would keep the container out
  // of the load balancer forever.
  const unhealthy = Object.entries(services)
    .filter(([, value]) => value.status === 'unhealthy')
    .map(([name]) => name);

  const body = {
    status: unhealthy.length === 0 ? 'ok' : 'degraded',
    version: VERSION,
    nodeVersion: process.version,
    uptime: Math.floor((Date.now() - startTime) / 1000),
    timestamp: new Date().toISOString(),
    services,
  };

  if (unhealthy.length > 0) {
    log.error('health check degraded', {
      unhealthy,
      details: Object.fromEntries(
        unhealthy.map((name) => [name, services[name as keyof typeof services].error])
      ),
    });
  }

  return c.json(body, unhealthy.length === 0 ? 200 : 503);
});

async function checkRedis(): Promise<ServiceStatus> {
  const client = getRedisClientForHealthCheck();
  if (!client) {
    return {
      status: 'skipped',
      error: process.env.REDIS_URL
        ? 'Redis unavailable — rate limiting degraded to in-memory'
        : 'REDIS_URL not configured',
    };
  }

  const start = Date.now();
  try {
    const pong = await withTimeout(client.ping(), 'redis');
    if (pong !== 'PONG') throw new Error(`unexpected PING reply: ${pong}`);
    return { status: 'healthy', latencyMs: Date.now() - start };
  } catch (e) {
    return { status: 'unhealthy', latencyMs: Date.now() - start, error: describeError(e) };
  }
}

async function checkDatabase(supabase: ReturnType<typeof getSupabaseAdmin>): Promise<ServiceStatus> {
  const start = Date.now();
  try {
    const { error } = await withTimeout(
      Promise.resolve(supabase.rpc('health_check_ping')),
      'database'
    );
    // Fallback: if the RPC doesn't exist, try a simple query
    if (error?.message?.includes('function') || error?.message?.includes('not found')) {
      const { error: selectError } = await supabase.from('users').select('id').limit(1);
      if (selectError) throw selectError;
    } else if (error) {
      throw error;
    }
    return { status: 'healthy', latencyMs: Date.now() - start };
  } catch (e) {
    return { status: 'unhealthy', latencyMs: Date.now() - start, error: describeError(e) };
  }
}

async function checkStorage(supabase: ReturnType<typeof getSupabaseAdmin>): Promise<ServiceStatus> {
  const start = Date.now();
  try {
    const { data, error } = await withTimeout(supabase.storage.listBuckets(), 'storage');
    if (error) throw error;
    const hasAudioBucket = data?.some((b) => b.name === 'loci-audio');
    if (!hasAudioBucket) {
      return { status: 'unhealthy', latencyMs: Date.now() - start, error: 'loci-audio bucket not found' };
    }
    return { status: 'healthy', latencyMs: Date.now() - start };
  } catch (e) {
    return { status: 'unhealthy', latencyMs: Date.now() - start, error: describeError(e) };
  }
}

async function checkAuth(supabase: ReturnType<typeof getSupabaseAdmin>): Promise<ServiceStatus> {
  const start = Date.now();
  try {
    // Admin API: list users with limit 1 to verify auth service is responsive
    const { error } = await withTimeout(
      supabase.auth.admin.listUsers({ page: 1, perPage: 1 }),
      'auth'
    );
    if (error) throw error;
    return { status: 'healthy', latencyMs: Date.now() - start };
  } catch (e) {
    return { status: 'unhealthy', latencyMs: Date.now() - start, error: describeError(e) };
  }
}

export default health;
