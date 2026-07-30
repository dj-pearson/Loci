import { afterEach, describe, expect, it, vi } from 'vitest';
import { createSupabaseFake, type FakeOptions } from './helpers/supabase-fake.js';

const USER_ID = 'internal-user-1';
const AUTH_ID = 'auth-uuid-1';

/**
 * Builds the route with a fresh fake. The auth middleware is stubbed to inject
 * the ids the handler reads, so these tests exercise the deletion cascade rather
 * than token validation (covered separately).
 */
async function buildRoute(options: FakeOptions = {}) {
  const fake = createSupabaseFake(options);
  vi.resetModules();
  vi.doMock('../src/middleware/auth.js', () => ({
    getSupabaseAdmin: () => fake.client,
    authMiddleware: async (c: { set: (k: string, v: unknown) => void }, next: () => Promise<void>) => {
      c.set('userId', USER_ID);
      c.set('user', { id: AUTH_ID, email: 'a@b.c' });
      await next();
    },
  }));
  const route = (await import('../src/routes/account-delete.js')).default;
  return { route, fake };
}

afterEach(() => {
  vi.resetModules();
  vi.restoreAllMocks();
});

describe('POST /api/account/delete', () => {
  it('deletes memberships, owned households, audio, loci, profile, and auth user', async () => {
    const { route, fake } = await buildRoute({
      selectData: { households: [{ id: 'hh-1' }, { id: 'hh-2' }] },
      storagePages: [[{ name: 'a.m4a' }, { name: 'b.m4a' }]],
    });

    const response = await route.request('/delete', { method: 'POST' });

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      success: true,
      audioObjectsRemoved: 2,
    });

    // Own memberships, then one membership sweep per owned household.
    const memberDeletes = fake.opsFor('household_members', 'delete');
    expect(memberDeletes[0].filters).toEqual([['user_id', USER_ID]]);
    expect(memberDeletes.map((o) => o.filters)).toEqual([
      [['user_id', USER_ID]],
      [['household_id', 'hh-1']],
      [['household_id', 'hh-2']],
    ]);

    expect(fake.opsFor('households', 'delete').map((o) => o.filters)).toEqual([
      [['id', 'hh-1']],
      [['id', 'hh-2']],
    ]);
    expect(fake.opsFor('loci', 'delete')[0].filters).toEqual([['user_id', USER_ID]]);
    expect(fake.opsFor('users', 'delete')[0].filters).toEqual([['id', USER_ID]]);
    expect(fake.client.auth.admin.deleteUser).toHaveBeenCalledWith(AUTH_ID);

    expect(
      fake.storageOps.filter((o) => o.op === 'remove').flatMap((o) => o.arg as string[])
    ).toEqual([`${USER_ID}/a.m4a`, `${USER_ID}/b.m4a`]);
  });

  it('removes audio beyond the first storage page', async () => {
    // A single unpaginated list() call capped at 100, so recordings past the
    // first page used to survive account deletion entirely.
    const firstPage = Array.from({ length: 100 }, (_, i) => ({ name: `f${i}.m4a` }));
    const { route, fake } = await buildRoute({
      storagePages: [firstPage, [{ name: 'tail.m4a' }]],
    });

    const response = await route.request('/delete', { method: 'POST' });

    await expect(response.json()).resolves.toMatchObject({ audioObjectsRemoved: 101 });
    expect(fake.storageOps.filter((o) => o.op === 'list')).toHaveLength(2);
    expect(fake.storageOps.filter((o) => o.op === 'remove')).toHaveLength(2);
  });

  it('is idempotent — a repeat call with nothing left still succeeds', async () => {
    const { route, fake } = await buildRoute({ storagePages: [[]] });

    const first = await route.request('/delete', { method: 'POST' });
    expect(first.status).toBe(200);

    const second = await route.request('/delete', { method: 'POST' });
    expect(second.status).toBe(200);
    await expect(second.json()).resolves.toMatchObject({ audioObjectsRemoved: 0 });
    expect(fake.storageOps.filter((o) => o.op === 'remove')).toHaveLength(0);
  });

  it('treats an already-deleted auth user as success, not failure', async () => {
    const { route } = await buildRoute({
      storagePages: [[]],
      deleteUserError: 'User not found',
    });

    const response = await route.request('/delete', { method: 'POST' });

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({ success: true });
  });

  it('does not report success when a row delete fails', async () => {
    // The old handler awaited each delete without checking `error`, so a failed
    // step still returned success — telling a user their data was erased when
    // it was not.
    vi.spyOn(console, 'error').mockImplementation(() => {});
    const { route } = await buildRoute({
      storagePages: [[]],
      errors: { 'loci.delete': 'permission denied for table loci' },
    });

    const response = await route.request('/delete', { method: 'POST' });

    expect(response.status).toBe(500);
    await expect(response.json()).resolves.toMatchObject({ failedStep: 'loci' });
  });

  it('does not report success when audio removal fails', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    const { route } = await buildRoute({
      storagePages: [[{ name: 'a.m4a' }]],
      storageRemoveError: 'bucket not found',
    });

    const response = await route.request('/delete', { method: 'POST' });

    expect(response.status).toBe(500);
    await expect(response.json()).resolves.toMatchObject({ failedStep: 'storage-remove' });
  });

  it('stops before deleting the profile when the auth user delete fails', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    const { route } = await buildRoute({
      storagePages: [[]],
      deleteUserError: 'internal error',
    });

    const response = await route.request('/delete', { method: 'POST' });

    expect(response.status).toBe(500);
    await expect(response.json()).resolves.toMatchObject({ failedStep: 'auth-user' });
  });
});
