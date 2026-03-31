import { Hono } from 'hono';
import { getSupabaseAdmin } from '../middleware/auth.js';
import { createHmac, timingSafeEqual } from 'node:crypto';

const syncSubscription = new Hono();

/** Maximum age (in ms) for webhook events — reject replays older than this. */
const WEBHOOK_MAX_AGE_MS = 5 * 60 * 1000; // 5 minutes

interface RevenueCatEvent {
  type: string;
  app_user_id: string;
  entitlement_ids?: string[];
  expiration_at_ms?: number;
  event_timestamp_ms?: number;
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
    console.error('[webhook] REVENUECAT_WEBHOOK_SECRET not set, rejecting webhook');
    return false;
  }
  if (!signature) return false;

  const expected = createHmac('sha256', secret).update(body).digest('hex');

  // Use timing-safe comparison to prevent timing attacks
  if (expected.length !== signature.length) return false;
  return timingSafeEqual(Buffer.from(expected, 'hex'), Buffer.from(signature, 'hex'));
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

  // Replay protection: reject events with timestamps older than 5 minutes
  if (event.event_timestamp_ms != null) {
    const eventAge = Date.now() - event.event_timestamp_ms;
    if (eventAge > WEBHOOK_MAX_AGE_MS) {
      console.warn(
        `[webhook] Rejecting stale event: type=${event.type} age=${Math.round(eventAge / 1000)}s`,
      );
      return c.json({ error: 'Webhook event too old (possible replay)' }, 400);
    }
    if (eventAge < -WEBHOOK_MAX_AGE_MS) {
      console.warn(
        `[webhook] Rejecting future-dated event: type=${event.type} drift=${Math.round(-eventAge / 1000)}s`,
      );
      return c.json({ error: 'Webhook event timestamp in the future' }, 400);
    }
  }

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
