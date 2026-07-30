import { Hono } from 'hono';
import { getSupabaseAdmin } from '../middleware/auth.js';
import { dispatchPush, tokenColumnFor, type DispatchOptions } from '../lib/push.js';
import { log } from '../lib/logger.js';

const pushDigest = new Hono();

export interface DigestResult {
  sent: number;
  skipped: number;
  /** Tokens the platform rejected as permanently dead, now cleared. */
  invalidated: number;
}

/**
 * US-196/US-197: clearing a dead token is not optional bookkeeping. Left in place
 * it is retried on every weekly run forever, and `sent` counts stay inflated.
 */
async function clearToken(
  supabase: ReturnType<typeof getSupabaseAdmin>,
  userId: string,
  platform: 'ios' | 'android'
): Promise<void> {
  const column = tokenColumnFor(platform);
  const { error } = await supabase
    .from('users')
    .update({ [column]: null })
    .eq('id', userId);
  if (error) {
    log.error('failed to clear dead push token', { userId, column, error: error.message });
  }
}

async function generateDigests(
  pushOptions: DispatchOptions = {}
): Promise<DigestResult> {
  const supabase = getSupabaseAdmin();
  let sent = 0;
  let skipped = 0;
  let invalidated = 0;

  const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
  const oneWeekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();

  // US-197: select both token columns and filter in code. A `.not('apns_token',
  // 'is', null)` filter excluded every Android-only user, so they could never have
  // received a digest even once FCM existed.
  const { data: users, error: usersError } = await supabase
    .from('users')
    .select('id, display_name, apns_token, fcm_token');

  if (usersError || !users?.length) {
    if (usersError) {
      log.error('failed to load users for digest', { error: usersError.message });
    }
    return { sent: 0, skipped: 0, invalidated: 0 };
  }

  for (const user of users) {
    if (!user.apns_token && !user.fcm_token) {
      skipped++;
      continue;
    }

    // Check if user has been active in last 30 days
    const { count: recentActivity } = await supabase
      .from('loci')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', user.id)
      .gte('created_at', thirtyDaysAgo);

    if (!recentActivity || recentActivity === 0) {
      skipped++;
      continue;
    }

    // Count loci created this week
    const { count: weeklyCount } = await supabase
      .from('loci')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', user.id)
      .gte('created_at', oneWeekAgo);

    // Get total loci count
    const { count: totalCount } = await supabase
      .from('loci')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', user.id)
      .eq('is_archived', false);

    // Get most visited location (most loci at same location_name)
    const { data: topLocation } = await supabase
      .from('loci')
      .select('location_name')
      .eq('user_id', user.id)
      .eq('is_archived', false)
      .not('location_name', 'is', null)
      .order('created_at', { ascending: false })
      .limit(50);

    let mostVisited: string | null = null;
    if (topLocation?.length) {
      const counts = new Map<string, number>();
      for (const l of topLocation) {
        if (l.location_name) {
          counts.set(l.location_name, (counts.get(l.location_name) ?? 0) + 1);
        }
      }
      let maxCount = 0;
      for (const [name, count] of counts) {
        if (count > maxCount) {
          maxCount = count;
          mostVisited = name;
        }
      }
    }

    // Build summary text
    const weekly = weeklyCount ?? 0;
    const total = totalCount ?? 0;
    let body = `You created ${weekly} ${weekly === 1 ? 'locus' : 'loci'} this week.`;
    if (mostVisited) {
      body += ` Most visited: ${mostVisited}.`;
    }
    body += ` Total: ${total} loci.`;

    const title = `Your Weekly Loci Digest`;

    const outcome = await dispatchPush(
      {
        userId: user.id,
        apnsToken: user.apns_token,
        fcmToken: user.fcm_token,
      },
      {
        title,
        body,
        threadId: 'weekly-digest',
        // One digest per user per week — collapse so a retried run replaces
        // rather than stacks notifications.
        collapseId: 'weekly-digest',
      },
      pushOptions
    );

    // Clear every dead token, even when another platform succeeded — a user with
    // two devices should not keep a stale token on one of them.
    for (const platform of outcome.invalid) {
      await clearToken(supabase, user.id, platform);
      invalidated++;
    }

    // Delivered to at least one device counts as sent.
    if (outcome.delivered.length > 0) {
      sent++;
    } else if (outcome.invalid.length === 0) {
      skipped++;
    }
  }

  return { sent, skipped, invalidated };
}

// Manual trigger endpoint
pushDigest.post('/run', async (c) => {
  const result = await generateDigests();
  return c.json(result);
});

export { generateDigests };
export default pushDigest;
