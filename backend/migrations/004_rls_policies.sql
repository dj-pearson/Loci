-- Migration: 004_rls_policies
-- Comprehensive RLS policies for all tables.
-- Note: RLS is already enabled on all tables in prior migrations.
-- Note: users table already has select/update own row policies from 001.

-- Helper: get the current user's internal ID from their auth ID
CREATE OR REPLACE FUNCTION public.current_user_id()
RETURNS UUID AS $$
    SELECT id FROM public.users WHERE auth_id = auth.uid()
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- ============================================================
-- LOCI POLICIES
-- ============================================================

-- Personal loci: full CRUD on own loci
CREATE POLICY loci_select_own ON public.loci
    FOR SELECT
    USING (user_id = public.current_user_id());

CREATE POLICY loci_insert_own ON public.loci
    FOR INSERT
    WITH CHECK (user_id = public.current_user_id());

CREATE POLICY loci_update_own ON public.loci
    FOR UPDATE
    USING (user_id = public.current_user_id())
    WITH CHECK (user_id = public.current_user_id());

CREATE POLICY loci_delete_own ON public.loci
    FOR DELETE
    USING (user_id = public.current_user_id());

-- Shared loci: read-only for household members
CREATE POLICY loci_select_shared ON public.loci
    FOR SELECT
    USING (
        is_shared = true
        AND household_id IN (
            SELECT household_id FROM public.household_members
            WHERE user_id = public.current_user_id()
        )
    );

-- ============================================================
-- HOUSEHOLDS POLICIES
-- ============================================================

-- Members can view their own households
CREATE POLICY households_select_member ON public.households
    FOR SELECT
    USING (
        id IN (
            SELECT household_id FROM public.household_members
            WHERE user_id = public.current_user_id()
        )
    );

-- Only the owner can update the household
CREATE POLICY households_update_owner ON public.households
    FOR UPDATE
    USING (owner_id = public.current_user_id())
    WITH CHECK (owner_id = public.current_user_id());

-- Only authenticated users can create households (they become owner)
CREATE POLICY households_insert ON public.households
    FOR INSERT
    WITH CHECK (owner_id = public.current_user_id());

-- Only the owner can delete the household
CREATE POLICY households_delete_owner ON public.households
    FOR DELETE
    USING (owner_id = public.current_user_id());

-- ============================================================
-- HOUSEHOLD_MEMBERS POLICIES
-- ============================================================

-- Members can see other members in their households
CREATE POLICY household_members_select ON public.household_members
    FOR SELECT
    USING (
        household_id IN (
            SELECT household_id FROM public.household_members
            WHERE user_id = public.current_user_id()
        )
    );

-- Household owner can add members
CREATE POLICY household_members_insert ON public.household_members
    FOR INSERT
    WITH CHECK (
        household_id IN (
            SELECT id FROM public.households
            WHERE owner_id = public.current_user_id()
        )
    );

-- Household owner can remove members; members can remove themselves
CREATE POLICY household_members_delete ON public.household_members
    FOR DELETE
    USING (
        user_id = public.current_user_id()
        OR household_id IN (
            SELECT id FROM public.households
            WHERE owner_id = public.current_user_id()
        )
    );
