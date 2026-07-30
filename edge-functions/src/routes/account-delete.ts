import { Hono } from 'hono';
import { authMiddleware, getSupabaseAdmin, type AuthEnv } from '../middleware/auth.js';

const accountDelete = new Hono<AuthEnv>();

accountDelete.use('/*', authMiddleware);

/** Supabase Storage `list` caps at 100 objects per page unless told otherwise. */
const STORAGE_PAGE_SIZE = 100;

/**
 * US-206: every step used to be a bare `await` with no error check, so a failed
 * delete still returned `{ success: true }`. For an account-deletion endpoint
 * that is the worst possible failure mode — the user is told their data is gone
 * while it is still on disk. Each step now reports, and the handler refuses to
 * claim success unless every step succeeded.
 */
class DeletionFailure extends Error {
  constructor(readonly step: string, message: string) {
    super(`${step}: ${message}`);
  }
}

async function removeAllAudioObjects(
  supabase: ReturnType<typeof getSupabaseAdmin>,
  userId: string
): Promise<number> {
  let removed = 0;
  let offset = 0;

  // Paginate: a user with more than 100 recordings previously kept every object
  // past the first page, because `list()` was called once with default limits.
  for (;;) {
    const { data, error } = await supabase.storage
      .from('loci-audio')
      .list(userId, { limit: STORAGE_PAGE_SIZE, offset });

    if (error) {
      throw new DeletionFailure('storage-list', error.message);
    }
    if (!data?.length) {
      break;
    }

    const paths = data.map((file) => `${userId}/${file.name}`);
    const { error: removeError } = await supabase.storage.from('loci-audio').remove(paths);
    if (removeError) {
      throw new DeletionFailure('storage-remove', removeError.message);
    }

    removed += paths.length;

    // `remove` deletes the objects we just listed, so the next page starts at
    // the same offset. Only advance if the backend returned a short page.
    if (data.length < STORAGE_PAGE_SIZE) {
      break;
    }
  }

  return removed;
}

// POST /api/account/delete — cascade delete all user data.
// Idempotent: deletes are keyed by id, so a repeat call after a successful run
// removes nothing further and still returns success.
accountDelete.post('/delete', async (c) => {
  const userId = c.get('userId');
  const authId = c.get('user').id;
  const supabase = getSupabaseAdmin();

  const check = (step: string, error: { message: string } | null) => {
    if (error) throw new DeletionFailure(step, error.message);
  };

  try {
    // 1. Household memberships this user holds.
    check(
      'household_members',
      (await supabase.from('household_members').delete().eq('user_id', userId)).error
    );

    // 2. Households this user owns, plus every membership under them.
    const { data: ownedHouseholds, error: ownedError } = await supabase
      .from('households')
      .select('id')
      .eq('owner_id', userId);
    check('households-select', ownedError);

    for (const household of ownedHouseholds ?? []) {
      check(
        'owned-household-members',
        (await supabase.from('household_members').delete().eq('household_id', household.id)).error
      );
      check(
        'owned-household',
        (await supabase.from('households').delete().eq('id', household.id)).error
      );
    }

    // 3. Audio objects — all pages of them.
    const audioRemoved = await removeAllAudioObjects(supabase, userId);

    // 4. Loci rows.
    check('loci', (await supabase.from('loci').delete().eq('user_id', userId)).error);

    // 5. User profile row.
    check('users', (await supabase.from('users').delete().eq('id', userId)).error);

    // 6. Supabase auth user. A repeat call finds nothing to delete; treat a
    //    "not found" response as already-done rather than a failure, so the
    //    endpoint stays idempotent.
    const { error: authError } = await supabase.auth.admin.deleteUser(authId);
    if (authError && !/not found|does not exist/i.test(authError.message)) {
      throw new DeletionFailure('auth-user', authError.message);
    }

    return c.json({
      success: true,
      message: 'Account and all data deleted',
      audioObjectsRemoved: audioRemoved,
    });
  } catch (error) {
    if (error instanceof DeletionFailure) {
      console.error(`[account-delete] failed at ${error.step} for user ${userId}: ${error.message}`);
      return c.json(
        {
          error: 'Failed to delete account. Please contact support.',
          failedStep: error.step,
        },
        500
      );
    }
    console.error('[account-delete] Error:', error);
    return c.json({ error: 'Failed to delete account. Please contact support.' }, 500);
  }
});

export default accountDelete;
