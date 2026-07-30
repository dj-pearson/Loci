-- Migration: 010_fix_rls_recursion
--
-- Fixes an infinite-recursion fault in the 004 policies (US-218, found by the
-- US-207 isolation suite).
--
-- `household_members_select` filtered household_members by a subquery over
-- household_members. Evaluating that subquery re-applies the same policy, so
-- PostgreSQL aborts with:
--
--     ERROR: infinite recursion detected in policy for relation "household_members"
--
-- It is not limited to that one table. `loci_select_shared` and
-- `households_select_member` also subquery household_members, so they trip the
-- same recursion — which means **every authenticated SELECT on public.loci
-- failed**, not just household queries. The core read path of the app did not
-- work against this schema at all.
--
-- The fix is a SECURITY DEFINER helper. It runs as the function owner, so the
-- lookup inside it is not subject to household_members' own policy and the cycle
-- is broken. This is the same shape as the existing `public.current_user_id()`.
--
-- Safe to re-run: functions use CREATE OR REPLACE and policies are dropped first.

-- ============================================================
-- Helper
-- ============================================================

/**
 * Household ids the calling user belongs to.
 *
 * SECURITY DEFINER is load-bearing, not a convenience: without it the body is
 * evaluated under household_members' RLS policy, which is exactly the recursion
 * being fixed. The search_path is pinned so a caller cannot shadow the tables it
 * reads.
 */
CREATE OR REPLACE FUNCTION public.current_user_household_ids()
RETURNS SETOF UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT hm.household_id
    FROM public.household_members hm
    WHERE hm.user_id = public.current_user_id()
$$;

/** Households the calling user owns. Mirrors the helper above for the insert and
 *  delete policies, which would otherwise subquery households under its own
 *  policy. */
CREATE OR REPLACE FUNCTION public.current_user_owned_household_ids()
RETURNS SETOF UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT h.id
    FROM public.households h
    WHERE h.owner_id = public.current_user_id()
$$;

REVOKE ALL ON FUNCTION public.current_user_household_ids() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.current_user_owned_household_ids() FROM PUBLIC;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        GRANT EXECUTE ON FUNCTION public.current_user_household_ids() TO authenticated;
        GRANT EXECUTE ON FUNCTION public.current_user_owned_household_ids() TO authenticated;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
        GRANT EXECUTE ON FUNCTION public.current_user_household_ids() TO service_role;
        GRANT EXECUTE ON FUNCTION public.current_user_owned_household_ids() TO service_role;
    END IF;
END
$$;

-- ============================================================
-- household_members — the recursive policy
-- ============================================================

DROP POLICY IF EXISTS household_members_select ON public.household_members;
CREATE POLICY household_members_select ON public.household_members
    FOR SELECT
    USING (household_id IN (SELECT public.current_user_household_ids()));

DROP POLICY IF EXISTS household_members_insert ON public.household_members;
CREATE POLICY household_members_insert ON public.household_members
    FOR INSERT
    WITH CHECK (household_id IN (SELECT public.current_user_owned_household_ids()));

DROP POLICY IF EXISTS household_members_delete ON public.household_members;
CREATE POLICY household_members_delete ON public.household_members
    FOR DELETE
    USING (
        user_id = public.current_user_id()
        OR household_id IN (SELECT public.current_user_owned_household_ids())
    );

-- ============================================================
-- households — depended on the recursive policy above
-- ============================================================

DROP POLICY IF EXISTS households_select_member ON public.households;
CREATE POLICY households_select_member ON public.households
    FOR SELECT
    USING (id IN (SELECT public.current_user_household_ids()));

-- ============================================================
-- loci — every authenticated SELECT hit the recursion through this policy
-- ============================================================

DROP POLICY IF EXISTS loci_select_shared ON public.loci;
CREATE POLICY loci_select_shared ON public.loci
    FOR SELECT
    USING (
        is_shared = true
        AND household_id IN (SELECT public.current_user_household_ids())
    );

-- ============================================================
-- storage.objects — the shared-audio policy recursed the same way
-- ============================================================

/**
 * User ids of everyone sharing a household with the caller (including the caller).
 *
 * The audio objects are laid out as `<user_id>/<locus_id>.m4a`, so the shared-read
 * policy has to resolve co-members' ids. Doing that inline meant two nested
 * subqueries over household_members under its own policy — the same recursion.
 */
CREATE OR REPLACE FUNCTION public.current_user_household_peer_ids()
RETURNS SETOF UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT DISTINCT hm.user_id
    FROM public.household_members hm
    WHERE hm.household_id IN (
        SELECT hm2.household_id
        FROM public.household_members hm2
        WHERE hm2.user_id = public.current_user_id()
    )
$$;

REVOKE ALL ON FUNCTION public.current_user_household_peer_ids() FROM PUBLIC;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        GRANT EXECUTE ON FUNCTION public.current_user_household_peer_ids() TO authenticated;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
        GRANT EXECUTE ON FUNCTION public.current_user_household_peer_ids() TO service_role;
    END IF;
END
$$;

DROP POLICY IF EXISTS storage_audio_select_shared ON storage.objects;
CREATE POLICY storage_audio_select_shared ON storage.objects
    FOR SELECT
    USING (
        bucket_id = 'loci-audio'
        AND (storage.foldername(name))[1] IN (
            SELECT id::text FROM public.users
            WHERE id IN (SELECT public.current_user_household_peer_ids())
        )
    );
