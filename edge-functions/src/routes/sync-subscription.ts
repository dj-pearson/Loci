import { Hono } from 'hono';
import { getSupabaseAdmin } from '../middleware/auth.js';
import { createHmac } from 'node:crypto';

const syncSubscription = new Hono();

interface RevenueCatEvent {
  type: string;
  app_user_id: string;
  entitlement_ids?: string[];
  expiration_at_ms?: number;
}

interface RevenueCatWebhook {
  api_version: string;
  event: RevenueCatEvent;
}

const HANDLED_EVENTS = [
  'INITIAL_PURCHASE',
  'RENEWAL',
  'CANCELLATION',
  'EXPIRATION',
  'NON_RENEWING_PURCHASE',
];

function verifySignature(body: string, signature: string | undefined): boolean {
  const secret = process.env.REVENUECAT_WEBHOOK_SECRET;
  if (!secret) {
    console.warn('[webhook] REVENUECAT_WEBHOOK_SECRET not set, skipping signature validation');
    return true;
  }
  if (!signature) return false;

  const expected = createHmac('sha256', secret).update(body).digest('hex');
  return signature === expected;
}

function mapEntitlementsToTier(entitlementIds: string[] | undefined): string {
  if (!entitlementIds?.length) return 'free';
  if (entitlementIds.includes('family')) return 'family';
  if (entitlementIds.includes('premium')) return 'premium';
  return 'free';
}

// POST /api/webhook/revenuecat
syncSubscription.post('/', async (c) => {
  const rawBody = await c.req.text();
  const signature = c.req.header('X-RevenueCat-Signature');

  if (!verifySignature(rawBody, signature)) {
    return c.json({ error: 'Invalid webhook signature' }, 400);
  }

  let payload: RevenueCatWebhook;
  try {
    payload = JSON.parse(rawBody) as RevenueCatWebhook;
  } catch {
    return c.json({ error: 'Invalid JSON payload' }, 400);
  }

  const { event } = payload;

  if (!HANDLED_EVENTS.includes(event.type)) {
    // Acknowledge but don't process unhandled event types
    return c.json({ status: 'ignored', eventType: event.type });
  }

  const appUserId = event.app_user_id;
  if (!appUserId) {
    return c.json({ error: 'Missing app_user_id' }, 400);
  }

  let tier: string;

  if (event.type === 'CANCELLATION' || event.type === 'EXPIRATION') {
    // Check if expiration is in the past
    const expiresAt = event.expiration_at_ms ? new Date(event.expiration_at_ms) : new Date(0);
    if (expiresAt <= new Date()) {
      tier = 'free';
    } else {
      // Still active until expiration
      tier = mapEntitlementsToTier(event.entitlement_ids);
    }
  } else {
    tier = mapEntitlementsToTier(event.entitlement_ids);
  }

  const supabase = getSupabaseAdmin();

  // app_user_id should be the Supabase auth UUID
  const { error } = await supabase
    .from('users')
    .update({
      subscription_tier: tier,
      updated_at: new Date().toISOString(),
    })
    .eq('auth_id', appUserId);

  if (error) {
    console.error('[webhook] Failed to update user tier:', error);
    return c.json({ error: 'Failed to update subscription' }, 500);
  }

  console.log(`[webhook] Updated user ${appUserId} to tier: ${tier} (event: ${event.type})`);
  return c.json({ status: 'ok', tier, eventType: event.type });
});

export default syncSubscription;
