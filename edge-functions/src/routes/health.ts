import { Hono } from 'hono';
import { getSupabaseAdmin } from '../middleware/auth.js';

const health = new Hono();

const startTime = Date.now();
const VERSION = process.env.EDGE_FUNCTION_VERSION || '1.0.0';

interface ServiceStatus {
  status: 'healthy' | 'unhealthy';
  latencyMs?: number;
  error?: string;
}

// GET /api/health — no authentication required
health.get('/', async (c) => {
  const supabase = getSupabaseAdmin();

  const [database, storage, auth] = await Promise.all([
    checkDatabase(supabase),
    checkStorage(supabase),
    checkAuth(supabase),
  ]);

  const allHealthy = database.status === 'healthy'
    && storage.status === 'healthy'
    && auth.status === 'healthy';

  return c.json({
    status: allHealthy ? 'ok' : 'degraded',
    version: VERSION,
    nodeVersion: process.version,
    uptime: Math.floor((Date.now() - startTime) / 1000),
    timestamp: new Date().toISOString(),
    services: { database, storage, auth },
  }, allHealthy ? 200 : 503);
});

async function checkDatabase(supabase: ReturnType<typeof getSupabaseAdmin>): Promise<ServiceStatus> {
  const start = Date.now();
  try {
    const { error } = await supabase.rpc('health_check_ping');
    // Fallback: if the RPC doesn't exist, try a simple query
    if (error?.message?.includes('function') || error?.message?.includes('not found')) {
      const { error: selectError } = await supabase.from('users').select('id').limit(1);
      if (selectError) throw selectError;
    } else if (error) {
      throw error;
    }
    return { status: 'healthy', latencyMs: Date.now() - start };
  } catch (e) {
    return { status: 'unhealthy', latencyMs: Date.now() - start, error: String(e) };
  }
}

async function checkStorage(supabase: ReturnType<typeof getSupabaseAdmin>): Promise<ServiceStatus> {
  const start = Date.now();
  try {
    const { data, error } = await supabase.storage.listBuckets();
    if (error) throw error;
    const hasAudioBucket = data?.some((b) => b.name === 'loci-audio');
    if (!hasAudioBucket) {
      return { status: 'unhealthy', latencyMs: Date.now() - start, error: 'loci-audio bucket not found' };
    }
    return { status: 'healthy', latencyMs: Date.now() - start };
  } catch (e) {
    return { status: 'unhealthy', latencyMs: Date.now() - start, error: String(e) };
  }
}

async function checkAuth(supabase: ReturnType<typeof getSupabaseAdmin>): Promise<ServiceStatus> {
  const start = Date.now();
  try {
    // Admin API: list users with limit 1 to verify auth service is responsive
    const { error } = await supabase.auth.admin.listUsers({ page: 1, perPage: 1 });
    if (error) throw error;
    return { status: 'healthy', latencyMs: Date.now() - start };
  } catch (e) {
    return { status: 'unhealthy', latencyMs: Date.now() - start, error: String(e) };
  }
}

export default health;
