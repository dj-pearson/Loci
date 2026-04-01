import { Hono } from 'hono';
import { authMiddleware, getSupabaseAdmin, type AuthEnv } from '../middleware/auth.js';
import { isValidUUID, isValidInviteCode } from '../middleware/validate.js';

const householdInvite = new Hono<AuthEnv>();

householdInvite.use('/*', authMiddleware);

const MAX_HOUSEHOLD_MEMBERS = 6;
const INVITE_CODE_LENGTH = 6;
const INVITE_EXPIRY_HOURS = 48;

function generateInviteCode(): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no I/O/0/1 to avoid confusion
  let code = '';
  for (let i = 0; i < INVITE_CODE_LENGTH; i++) {
    code += chars[Math.floor(Math.random() * chars.length)];
  }
  return code;
}

// POST /api/household/invite/generate
householdInvite.post('/generate', async (c) => {
  const userId = c.get('userId');
  const { householdId } = await c.req.json<{ householdId: string }>();

  if (!isValidUUID(householdId)) {
    return c.json({ error: 'householdId must be a valid UUID' }, 400);
  }

  const supabase = getSupabaseAdmin();

  // Verify caller is the household owner
  const { data: household, error: hError } = await supabase
    .from('households')
    .select('id, owner_id')
    .eq('id', householdId)
    .single();

  if (hError || !household) {
    return c.json({ error: 'Household not found' }, 404);
  }

  if (household.owner_id !== userId) {
    return c.json({ error: 'Only the household owner can generate invite codes' }, 403);
  }

  const code = generateInviteCode();
  const expiresAt = new Date(Date.now() + INVITE_EXPIRY_HOURS * 60 * 60 * 1000).toISOString();

  const { error: updateError } = await supabase
    .from('households')
    .update({ invite_code: code, invite_expires_at: expiresAt })
    .eq('id', householdId);

  if (updateError) {
    return c.json({ error: 'Failed to generate invite code' }, 500);
  }

  return c.json({ code, expiresAt });
});

// POST /api/household/invite/validate
householdInvite.post('/validate', async (c) => {
  const { code } = await c.req.json<{ code: string }>();

  if (!isValidInviteCode(code)) {
    return c.json({ error: 'Invalid invite code format' }, 400);
  }

  const supabase = getSupabaseAdmin();

  const { data: household, error } = await supabase
    .from('households')
    .select('id, name, invite_code, invite_expires_at')
    .eq('invite_code', code.toUpperCase())
    .single();

  if (error || !household) {
    return c.json({ error: 'Invalid invite code' }, 404);
  }

  if (new Date(household.invite_expires_at) < new Date()) {
    return c.json({ error: 'Invite code has expired' }, 410);
  }

  // Check member count
  const { count } = await supabase
    .from('household_members')
    .select('id', { count: 'exact', head: true })
    .eq('household_id', household.id);

  if ((count ?? 0) >= MAX_HOUSEHOLD_MEMBERS) {
    return c.json({ error: 'Household is full (maximum 6 members)' }, 409);
  }

  return c.json({
    valid: true,
    householdId: household.id,
    householdName: household.name,
    memberCount: count ?? 0,
  });
});

// POST /api/household/invite/accept
householdInvite.post('/accept', async (c) => {
  const userId = c.get('userId');
  const { code } = await c.req.json<{ code: string }>();

  if (!isValidInviteCode(code)) {
    return c.json({ error: 'Invalid invite code format' }, 400);
  }

  const supabase = getSupabaseAdmin();

  // Validate the code
  const { data: household, error: hError } = await supabase
    .from('households')
    .select('id, name, invite_code, invite_expires_at')
    .eq('invite_code', code.toUpperCase())
    .single();

  if (hError || !household) {
    return c.json({ error: 'Invalid invite code' }, 404);
  }

  if (new Date(household.invite_expires_at) < new Date()) {
    return c.json({ error: 'Invite code has expired' }, 410);
  }

  // Check member count
  const { count } = await supabase
    .from('household_members')
    .select('id', { count: 'exact', head: true })
    .eq('household_id', household.id);

  if ((count ?? 0) >= MAX_HOUSEHOLD_MEMBERS) {
    return c.json({ error: 'Household is full (maximum 6 members)' }, 409);
  }

  // Check if already a member
  const { data: existing } = await supabase
    .from('household_members')
    .select('id')
    .eq('household_id', household.id)
    .eq('user_id', userId)
    .single();

  if (existing) {
    return c.json({ error: 'You are already a member of this household' }, 409);
  }

  // Get user's display name
  const { data: user } = await supabase
    .from('users')
    .select('display_name')
    .eq('id', userId)
    .single();

  // Add user to household
  const { error: insertError } = await supabase
    .from('household_members')
    .insert({
      household_id: household.id,
      user_id: userId,
      display_name: user?.display_name ?? 'Member',
      role: 'member',
    });

  if (insertError) {
    return c.json({ error: 'Failed to join household' }, 500);
  }

  return c.json({
    householdId: household.id,
    householdName: household.name,
    role: 'member',
  });
});

// POST /api/household/invite/regenerate
householdInvite.post('/regenerate', async (c) => {
  const userId = c.get('userId');
  const { householdId } = await c.req.json<{ householdId: string }>();

  if (!isValidUUID(householdId)) {
    return c.json({ error: 'householdId must be a valid UUID' }, 400);
  }

  const supabase = getSupabaseAdmin();

  // Verify caller is owner
  const { data: household, error: hError } = await supabase
    .from('households')
    .select('id, owner_id')
    .eq('id', householdId)
    .single();

  if (hError || !household) {
    return c.json({ error: 'Household not found' }, 404);
  }

  if (household.owner_id !== userId) {
    return c.json({ error: 'Only the household owner can regenerate invite codes' }, 403);
  }

  const code = generateInviteCode();
  const expiresAt = new Date(Date.now() + INVITE_EXPIRY_HOURS * 60 * 60 * 1000).toISOString();

  const { error: updateError } = await supabase
    .from('households')
    .update({ invite_code: code, invite_expires_at: expiresAt })
    .eq('id', householdId);

  if (updateError) {
    return c.json({ error: 'Failed to regenerate invite code' }, 500);
  }

  return c.json({ code, expiresAt });
});

export default householdInvite;
