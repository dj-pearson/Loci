import { Hono } from 'hono';
import { getSupabaseAdmin } from '../middleware/auth.js';
import { sendApnsPush, type SendApnsOptions } from '../lib/apns.js';

const pushDigest = new Hono();

export interface DigestResult {
  sent: number;
  skipped: number;
  /** Tokens APNs rejected as permanently dead, cleared from users.apns_token. */
  invalidated: number;
}

/**
 * US-196: clearing the token is not optional bookkeeping. A dead token left in
 * place is retried on every weekly run forever, and `sent` counts stay inflated.
 */
async function clearApnsToken(
  supabase: ReturnType<typeof getSupabaseAdmin>,
  userId: string
): Promise<void> {
  const { error } = await supabase
    .from('users')
    .update({ apns_token: null })
    .eq('id', userId);
  if (error) {
    console.error(`[push] failed to clear dead apns_token for ${userId}: ${error.message}`);
  }
}

async function generateDigests(
  apnsOptions: SendApnsOptions = {}
): Promise<DigestResult> {
  const supabase = getSupabaseAdmin();
  let sent = 0;
  let skipped = 0;
  let invalidated = 0;

  const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
  const oneWeekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();

  // Get active users with APNs tokens
  const { data: users, error: usersError } = await supabase
    .from('users')
    .select('id, display_name, apns_token')
    .not('apns_token', 'is', null);

  if (usersError || !users?.length) {
    if (usersError) {
      console.error(`[push] failed to load users: ${usersError.message}`);
    }
    return { sent: 0, skipped: 0, invalidated: 0 };
  }

  for (const user of users) {
    if (!user.apns_token) {
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

    const result = await sendApnsPush(
      user.apns_token,
      {
        title,
        body,
        threadId: 'weekly-digest',
        // One digest per user per week — collapse so a retried run replaces
        // rather than stacks notifications.
        collapseId: 'weekly-digest',
      },
      apnsOptions
    );

    if (result.ok) {
      sent++;
      continue;
    }

    if (result.invalidToken) {
      await clearApnsToken(supabase, user.id);
      invalidated++;
      continue;
    }

    if (!result.skipped) {
      console.error(
        `[push] digest delivery failed for ${user.id}: ` +
          `status=${result.status ?? 'n/a'} reason=${result.reason ?? 'unknown'}`
      );
    }
    skipped++;
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
