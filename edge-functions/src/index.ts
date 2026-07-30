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
import {
  errorFields,
  log,
  requestLogger,
  runScheduledJob,
  type RequestLogEnv,
} from './lib/logger.js';
import { captureError, initCrashReporting } from './lib/crash-reporting.js';

// US-199: before the app is constructed, so a fault during setup is reported too.
initCrashReporting();

const app = new Hono<RequestLogEnv>();

// US-215: structured request logging first, so every downstream line — including
// rejections from the rate limiter and the signing middleware — carries the same
// correlation id.
app.use('*', requestLogger);

// US-215: an unhandled route error previously returned Hono's default 500 with no
// log line at all, so a recurring fault was invisible.
app.onError((error, c) => {
  const route = new URL(c.req.url).pathname;
  log.error('unhandled route error', {
    requestId: c.get('requestId'),
    route,
    method: c.req.method,
    ...errorFields(error),
  });
  // US-199: a recurring 500 should page someone, not wait to be noticed in logs.
  captureError(error, { requestId: c.get('requestId'), route, method: c.req.method });
  return c.json({ error: 'Internal server error' }, 500);
});

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
  await runScheduledJob('analyze-loci', () => processUserClusters(), {
    onError: (error) => captureError(error, { job: 'analyze-loci' }),
  });
});

// Cron: weekly digest every Sunday at 10 AM
cron.schedule('0 10 * * 0', async () => {
  await runScheduledJob('push-digest', () => generateDigests(), {
    onError: (error) => captureError(error, { job: 'push-digest' }),
  });
});

// US-146: Cron: daily cleanup of old login attempts at 3 AM
cron.schedule('0 3 * * *', async () => {
  await runScheduledJob('cleanup-login-attempts', async () => {
    const { getSupabaseAdmin } = await import('./middleware/auth.js');
    const supabase = getSupabaseAdmin();
    const { data, error } = await supabase.rpc('cleanup_login_attempts', {
      p_retention_days: 30,
    });
    // Throwing rather than logging makes runScheduledJob record it as a failed
    // run instead of a successful one with an error buried in the message.
    if (error) throw new Error(error.message);
    return { recordsDeleted: data };
  }, {
    onError: (error) => captureError(error, { job: 'cleanup-login-attempts' }),
  });
});

// Health check — no auth required, rate-limited to 10 req/min per IP
app.use('/api/health/*', rateLimitHealth);
app.route('/api/health', health);

const port = parseInt(process.env.PORT || '3000', 10);

log.info('starting', {
  port,
  nodeVersion: process.version,
  version: process.env.EDGE_FUNCTION_VERSION ?? '1.0.0',
  redisConfigured: Boolean(process.env.REDIS_URL),
  apnsConfigured: Boolean(process.env.APNS_KEY_P8),
  fcmConfigured: Boolean(process.env.FCM_SERVICE_ACCOUNT_JSON),
  errorReportingConfigured: Boolean(process.env.SENTRY_DSN),
});

// US-215: an unhandled rejection or uncaught exception would otherwise kill the
// process with only Node's default stderr dump, losing the structured context.
process.on('unhandledRejection', (reason) => {
  log.error('unhandled rejection', errorFields(reason));
  captureError(reason, { kind: 'unhandledRejection' });
});
process.on('uncaughtException', (error) => {
  log.error('uncaught exception', errorFields(error));
  captureError(error, { kind: 'uncaughtException' });
  // Re-raise: a process in an unknown state should be replaced by the orchestrator,
  // not left running.
  process.exit(1);
});

serve({ fetch: app.fetch, port });

export default app;
