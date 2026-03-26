import { Hono } from 'hono';
import { authMiddleware, getSupabaseAdmin, type AuthEnv } from '../middleware/auth.js';

const contextualSelect = new Hono<AuthEnv>();

contextualSelect.use('/*', authMiddleware);

interface Locus {
  id: string;
  transcription: string;
  category: string;
  location_name: string | null;
  created_at: string;
  is_shared: boolean;
  created_by_name: string | null;
  distance_meters: number;
}

// Time-of-day category relevance weights
const TIME_CATEGORY_WEIGHTS: Record<string, number[]> = {
  // [morning 6-11, lunch 11-14, afternoon 14-17, evening 17-21, night 21-6]
  food:     [0.6, 1.0, 0.4, 0.9, 0.2],
  shopping: [0.3, 0.7, 0.8, 0.5, 0.1],
  parking:  [0.8, 0.7, 0.7, 0.4, 0.1],
  health:   [0.7, 0.6, 0.6, 0.3, 0.1],
  travel:   [0.8, 0.6, 0.6, 0.5, 0.3],
  home:     [0.7, 0.3, 0.3, 0.8, 0.9],
  outdoor:  [0.6, 0.7, 0.8, 0.5, 0.1],
  general:  [0.5, 0.5, 0.5, 0.5, 0.5],
  tip:      [0.5, 0.5, 0.5, 0.5, 0.5],
  warning:  [0.8, 0.8, 0.8, 0.8, 0.8], // warnings always relevant
};

function getTimeSlot(hour: number): number {
  if (hour >= 6 && hour < 11) return 0;   // morning
  if (hour >= 11 && hour < 14) return 1;  // lunch
  if (hour >= 14 && hour < 17) return 2;  // afternoon
  if (hour >= 17 && hour < 21) return 3;  // evening
  return 4;                                // night
}

function getTimeCategoryWeight(category: string, hour: number): number {
  const slot = getTimeSlot(hour);
  const weights = TIME_CATEGORY_WEIGHTS[category] ?? TIME_CATEGORY_WEIGHTS['general'];
  return weights[slot];
}

function calculateRecencyScore(createdAt: string): number {
  const ageMs = Date.now() - new Date(createdAt).getTime();
  const ageDays = ageMs / (1000 * 60 * 60 * 24);
  // Exponential decay: score ~1.0 for today, ~0.5 at 7 days, ~0.1 at 30 days
  return Math.exp(-ageDays / 10);
}

// POST /api/loci/contextual-select
contextualSelect.post('/', async (c) => {
  const { lat, lon } = await c.req.json<{ lat: number; lon: number }>();
  const userId = c.get('userId');

  if (lat == null || lon == null) {
    return c.json({ error: 'lat and lon are required' }, 400);
  }

  const supabase = getSupabaseAdmin();

  // Query loci within 100m using PostGIS ST_DWithin
  const { data: loci, error } = await supabase.rpc('nearby_loci', {
    p_user_id: userId,
    p_lat: lat,
    p_lon: lon,
    p_radius_meters: 100,
  });

  if (error) {
    // If the RPC doesn't exist yet, fall back to a raw query
    const { data: fallbackLoci, error: fbError } = await supabase
      .from('loci')
      .select('id, transcription, category, location_name, created_at, is_shared, created_by_name')
      .eq('user_id', userId)
      .eq('is_archived', false);

    if (fbError || !fallbackLoci?.length) {
      return c.json({ locus: null, explanation: 'No nearby loci found' });
    }

    // Can't do distance calc without PostGIS RPC, return most recent
    const sorted = fallbackLoci.sort(
      (a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
    );
    return c.json({
      locus: sorted[0],
      explanation: `Most recent note: "${sorted[0].location_name ?? sorted[0].category}"`,
    });
  }

  if (!loci?.length) {
    return c.json({ locus: null, explanation: 'No nearby loci found' });
  }

  // Score each locus
  const hour = new Date().getHours();
  const scored = (loci as Locus[]).map((locus) => {
    const recencyScore = calculateRecencyScore(locus.created_at);
    const timeScore = getTimeCategoryWeight(locus.category, hour);
    // Visit frequency approximated by inverse distance (closer = visited more)
    const proximityScore = Math.max(0, 1 - (locus.distance_meters ?? 0) / 100);

    // Weighted: recency 40%, time-of-day 30%, proximity 30%
    const total = recencyScore * 0.4 + timeScore * 0.3 + proximityScore * 0.3;

    return { locus, score: total, recencyScore, timeScore, proximityScore };
  });

  scored.sort((a, b) => b.score - a.score);
  const winner = scored[0];

  const timeLabel = ['morning', 'lunchtime', 'afternoon', 'evening', 'nighttime'][getTimeSlot(hour)];
  const explanation = `Selected "${winner.locus.location_name ?? winner.locus.category}" — relevant ${winner.locus.category} note for ${timeLabel}`;

  return c.json({
    locus: winner.locus,
    explanation,
    score: winner.score,
  });
});

export default contextualSelect;
