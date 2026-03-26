import { Hono } from 'hono';
import { serve } from '@hono/node-server';
import cron from 'node-cron';
import householdInvite from './routes/household-invite.js';
import contextualSelect from './routes/contextual-select.js';
import analyzeLoci, { processUserClusters } from './routes/analyze-loci.js';
import syncSubscription from './routes/sync-subscription.js';
import pushDigest, { generateDigests } from './routes/push-digest.js';

const app = new Hono();

// Routes
app.route('/api/household/invite', householdInvite);
app.route('/api/loci/contextual-select', contextualSelect);
app.route('/api/loci/analyze', analyzeLoci);
app.route('/api/webhook/revenuecat', syncSubscription);
app.route('/api/digest', pushDigest);

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

// Health check
app.get('/health', (c) => {
  return c.json({
    status: 'ok',
    service: 'loci-edge-functions',
    timestamp: new Date().toISOString(),
  });
});

const port = parseInt(process.env.PORT || '3000', 10);

console.log(`Loci edge functions starting on port ${port}`);

serve({ fetch: app.fetch, port });

export default app;
