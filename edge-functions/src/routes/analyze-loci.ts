import { Hono } from 'hono';
import { getSupabaseAdmin } from '../middleware/auth.js';

const analyzeLoci = new Hono();

interface LocusCluster {
  user_id: string;
  centroid_lon: number;
  centroid_lat: number;
  loci_count: number;
  location_name: string | null;
  transcriptions: string[];
  loci_ids: string[];
}

async function callClaudeHaiku(transcriptions: string[], locationName: string | null): Promise<string> {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    throw new Error('Missing ANTHROPIC_API_KEY');
  }

  const locationContext = locationName ? ` near "${locationName}"` : '';
  const prompt = `You are summarizing voice notes left at a location${locationContext}. Create a brief, useful summary (1-2 sentences) that captures the key information across these notes:\n\n${transcriptions.map((t, i) => `Note ${i + 1}: ${t}`).join('\n')}\n\nSummary:`;

  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 150,
      messages: [{ role: 'user', content: prompt }],
    }),
  });

  if (!response.ok) {
    const errText = await response.text();
    throw new Error(`Anthropic API error ${response.status}: ${errText}`);
  }

  const data = await response.json() as { content: Array<{ text: string }> };
  return data.content[0]?.text ?? 'Summary unavailable.';
}

async function processUserClusters(): Promise<{ processed: number; errors: number }> {
  const supabase = getSupabaseAdmin();
  let processed = 0;
  let errors = 0;

  // Get premium/family users
  const { data: users, error: usersError } = await supabase
    .from('users')
    .select('id')
    .in('subscription_tier', ['premium', 'family']);

  if (usersError || !users?.length) {
    return { processed: 0, errors: 0 };
  }

  for (const user of users) {
    try {
      // Find clusters: locations with 3+ loci within 50m of each other
      const { data: clusters, error: clusterError } = await supabase.rpc('loci_clusters', {
        p_user_id: user.id,
        p_min_count: 3,
        p_cluster_radius: 50,
      });

      if (clusterError || !clusters?.length) continue;

      for (const cluster of clusters as LocusCluster[]) {
        try {
          const summary = await callClaudeHaiku(
            cluster.transcriptions,
            cluster.location_name
          );

          // Upsert summary locus at cluster centroid
          const { error: upsertError } = await supabase
            .from('loci')
            .insert({
              user_id: user.id,
              location: `SRID=4326;POINT(${cluster.centroid_lon} ${cluster.centroid_lat})`,
              location_name: cluster.location_name ?? 'Summary',
              transcription: summary,
              category: 'general',
              is_shared: false,
              created_by_name: 'AI Summary',
            });

          if (upsertError) {
            errors++;
          } else {
            processed++;
          }
        } catch {
          errors++;
          // Rate limit: back off on failure
          await new Promise((r) => setTimeout(r, 2000));
        }
      }
    } catch {
      errors++;
    }
  }

  return { processed, errors };
}

// Manual trigger endpoint (for testing)
analyzeLoci.post('/run', async (c) => {
  const result = await processUserClusters();
  return c.json(result);
});

export { processUserClusters };
export default analyzeLoci;
