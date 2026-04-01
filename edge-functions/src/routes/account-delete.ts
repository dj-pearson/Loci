import { Hono } from 'hono';
import { authMiddleware, getSupabaseAdmin, type AuthEnv } from '../middleware/auth.js';

const accountDelete = new Hono<AuthEnv>();

accountDelete.use('/*', authMiddleware);

// POST /api/account/delete — cascade delete all user data
accountDelete.post('/delete', async (c) => {
  const userId = c.get('userId');
  const supabase = getSupabaseAdmin();

  try {
    // 1. Delete household memberships
    await supabase
      .from('household_members')
      .delete()
      .eq('user_id', userId);

    // 2. Check if user owns any households — transfer or delete
    const { data: ownedHouseholds } = await supabase
      .from('households')
      .select('id')
      .eq('owner_id', userId);

    for (const household of ownedHouseholds ?? []) {
      // Delete all members of owned households
      await supabase
        .from('household_members')
        .delete()
        .eq('household_id', household.id);

      // Delete the household
      await supabase
        .from('households')
        .delete()
        .eq('id', household.id);
    }

    // 3. Delete all audio files from storage
    const { data: audioFiles } = await supabase.storage
      .from('loci-audio')
      .list(userId);

    if (audioFiles && audioFiles.length > 0) {
      const paths = audioFiles.map((f) => `${userId}/${f.name}`);
      await supabase.storage
        .from('loci-audio')
        .remove(paths);
    }

    // 4. Delete all loci
    await supabase
      .from('loci')
      .delete()
      .eq('user_id', userId);

    // 5. Delete user profile
    await supabase
      .from('users')
      .delete()
      .eq('id', userId);

    // 6. Delete Supabase auth user
    const authId = c.get('user').id;
    await supabase.auth.admin.deleteUser(authId);

    return c.json({ success: true, message: 'Account and all data deleted' });
  } catch (error) {
    console.error('[account-delete] Error:', error);
    return c.json({ error: 'Failed to delete account. Please contact support.' }, 500);
  }
});

export default accountDelete;
