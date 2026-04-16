import { Hono } from 'hono';
import { serve } from '@hono/node-server';
import cron from 'node-cron';
import { rateLimitDefault, rateLimitInvite, rateLimitWebhook, rateLimitHealth } from './middleware/rate-limit.js';
import { authRateLimit } from './middleware/auth-rate-limit.js';
import householdInvite from './routes/household-invite.js';
import contextualSelect from './routes/contextual-select.js';
import analyzeLoci, { processUserClusters } from './routes/analyze-loci.js';
import syncSubscription from './routes/sync-subscription.js';
import pushDigest, { generateDigests } from './routes/push-digest.js';
import health from './routes/health.js';
import accountDelete from './routes/account-delete.js';
import authVerify from './routes/auth-verify.js';
import { requestSigningMiddleware } from './middleware/request-signing.js';

const app = new Hono();

// Global rate limiting (60 req/min per user)
app.use('/api/*', rateLimitDefault);

// Per-route rate limit overrides (applied before the global default via route-level middleware)
app.use('/api/household/invite/*', rateLimitInvite);
app.use('/api/webhook/revenuecat/*', rateLimitWebhook);

// US-146: Auth-specific rate limiting (DB-backed, per-email + per-IP)
app.use('/api/auth/*', authRateLimit);

// US-152: Request signing validation on sensitive mutation routes
app.use('/api/account/*', requestSigningMiddleware);

// Routes
app.route('/api/household/invite', householdInvite);
app.route('/api/loci/contextual-select', contextualSelect);
app.route('/api/loci/analyze', analyzeLoci);
app.route('/api/webhook/revenuecat', syncSubscription);
app.route('/api/digest', pushDigest);
app.route('/api/account', accountDelete);
app.route('/api/auth', authVerify);

// Cron: nightly AI analysis at 2 AM
cron.schedule('0 2 * * *', async () => {
  console.log('[cron] Starting nightly loci analysis...');
  const result = await processUserClusters();
  console.log(`[cron] Analysis complete: ${result.processed} processed, ${result.errors} errors`);
});

// Cron: weekly digest every Sunday at 10 AM
cron.schedule('0 10 * * 0', async () => {
  console.log('[cron] Starting weekly push digest...');
  const result = await generateDigests();
  console.log(`[cron] Digest complete: ${result.sent} sent, ${result.skipped} skipped`);
});

// US-146: Cron: daily cleanup of old login attempts at 3 AM
cron.schedule('0 3 * * *', async () => {
  console.log('[cron] Cleaning up old login attempts...');
  try {
    const { getSupabaseAdmin } = await import('./middleware/auth.js');
    const supabase = getSupabaseAdmin();
    const { data, error } = await supabase.rpc('cleanup_login_attempts', { p_retention_days: 30 });
    console.log(`[cron] Login attempts cleanup complete: ${error ? 'error: ' + error.message : data + ' records deleted'}`);
  } catch (err) {
    console.error('[cron] Login attempts cleanup failed:', err);
  }
});

// Health check — no auth required, rate-limited to 10 req/min per IP
app.use('/api/health/*', rateLimitHealth);
app.route('/api/health', health);

const port = parseInt(process.env.PORT || '3000', 10);

console.log(`Lociate edge functions starting on port ${port}`);

serve({ fetch: app.fetch, port });

export default app;
