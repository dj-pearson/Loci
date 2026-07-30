-- US-207: automated proof that one household cannot reach another's data.
--
-- Voice notes are the most private thing this app stores. Before this suite there
-- was no automated check that RLS actually isolated tenants, so a policy
-- regression would have shipped silently and leaked other families' recordings.
--
-- Fixtures: two households, each with an owner and a member, plus an unaffiliated
-- user. Every assertion runs as `authenticated` — the table owner bypasses RLS,
-- so a test run as postgres would pass no matter how broken the policies were.

\set ON_ERROR_STOP on
\timing off

BEGIN;

-- ============================================================
-- Fixtures (as the owner, so RLS does not obstruct setup)
-- ============================================================

INSERT INTO auth.users (id, email) VALUES
    ('aaaaaaaa-0000-0000-0000-000000000001', 'owner-a@example.com'),
    ('aaaaaaaa-0000-0000-0000-000000000002', 'member-a@example.com'),
    ('bbbbbbbb-0000-0000-0000-000000000001', 'owner-b@example.com'),
    ('bbbbbbbb-0000-0000-0000-000000000002', 'member-b@example.com'),
    ('cccccccc-0000-0000-0000-000000000001', 'loner@example.com');

-- The on_auth_user_created trigger from 001 populates public.users.
UPDATE public.users SET subscription_tier = 'family'
WHERE auth_id IN (
    'aaaaaaaa-0000-0000-0000-000000000001',
    'bbbbbbbb-0000-0000-0000-000000000001'
);
UPDATE public.users SET subscription_tier = 'premium'
WHERE auth_id IN (
    'aaaaaaaa-0000-0000-0000-000000000002',
    'bbbbbbbb-0000-0000-0000-000000000002'
);

CREATE TEMP TABLE ids AS
SELECT
    (SELECT id FROM public.users WHERE auth_id = 'aaaaaaaa-0000-0000-0000-000000000001') AS owner_a,
    (SELECT id FROM public.users WHERE auth_id = 'aaaaaaaa-0000-0000-0000-000000000002') AS member_a,
    (SELECT id FROM public.users WHERE auth_id = 'bbbbbbbb-0000-0000-0000-000000000001') AS owner_b,
    (SELECT id FROM public.users WHERE auth_id = 'bbbbbbbb-0000-0000-0000-000000000002') AS member_b,
    (SELECT id FROM public.users WHERE auth_id = 'cccccccc-0000-0000-0000-000000000001') AS loner;

INSERT INTO public.households (id, name, owner_id, invite_code)
SELECT 'dddddddd-0000-0000-0000-00000000000a', 'Household A', owner_a, 'INVITEAA' FROM ids;
INSERT INTO public.households (id, name, owner_id, invite_code)
SELECT 'dddddddd-0000-0000-0000-00000000000b', 'Household B', owner_b, 'INVITEBB' FROM ids;

INSERT INTO public.household_members (household_id, user_id, display_name, role)
SELECT 'dddddddd-0000-0000-0000-00000000000a', owner_a, 'Owner A', 'owner' FROM ids;
INSERT INTO public.household_members (household_id, user_id, display_name, role)
SELECT 'dddddddd-0000-0000-0000-00000000000a', member_a, 'Member A', 'member' FROM ids;
INSERT INTO public.household_members (household_id, user_id, display_name, role)
SELECT 'dddddddd-0000-0000-0000-00000000000b', owner_b, 'Owner B', 'owner' FROM ids;
INSERT INTO public.household_members (household_id, user_id, display_name, role)
SELECT 'dddddddd-0000-0000-0000-00000000000b', member_b, 'Member B', 'member' FROM ids;

-- Household A: one shared locus and one private locus.
INSERT INTO public.loci (id, user_id, household_id, location, transcription, is_shared)
SELECT
    'eeeeeeee-0000-0000-0000-00000000000a', owner_a,
    'dddddddd-0000-0000-0000-00000000000a',
    ST_SetSRID(ST_MakePoint(-111.891, 40.760), 4326)::geography,
    'Shared: spare key under the mat', true
FROM ids;

INSERT INTO public.loci (id, user_id, household_id, location, transcription, is_shared)
SELECT
    'eeeeeeee-0000-0000-0000-00000000000c', owner_a, NULL,
    ST_SetSRID(ST_MakePoint(-111.892, 40.761), 4326)::geography,
    'Private: therapist appointment notes', false
FROM ids;

-- Household B: one shared locus.
INSERT INTO public.loci (id, user_id, household_id, location, transcription, is_shared)
SELECT
    'eeeeeeee-0000-0000-0000-00000000000b', owner_b,
    'dddddddd-0000-0000-0000-00000000000b',
    ST_SetSRID(ST_MakePoint(-122.419, 37.775), 4326)::geography,
    'Shared: alarm code is 1234', true
FROM ids;

INSERT INTO storage.buckets (id, name) VALUES ('loci-audio', 'loci-audio')
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.objects (bucket_id, name)
SELECT 'loci-audio', owner_a || '/eeeeeeee-0000-0000-0000-00000000000a.m4a' FROM ids;
INSERT INTO storage.objects (bucket_id, name)
SELECT 'loci-audio', owner_b || '/eeeeeeee-0000-0000-0000-00000000000b.m4a' FROM ids;

-- Temp tables are not subject to RLS, which is what makes `ids` usable as a
-- trusted fixture lookup from inside an authenticated block. Grant it explicitly:
-- the temp schema belongs to the session's original role.
GRANT SELECT ON ids TO authenticated;

-- ============================================================
-- Assertions
-- ============================================================

SET ROLE authenticated;

-- ---- Loci: cross-tenant reads ----------------------------------------------

DO $$
BEGIN
    RAISE NOTICE 'loci: cross-household isolation';
    PERFORM tests.act_as('bbbbbbbb-0000-0000-0000-000000000002');

    PERFORM tests.assert_equals(
        (SELECT count(*)::int FROM public.loci
         WHERE id = 'eeeeeeee-0000-0000-0000-00000000000a'),
        0,
        'a household B member cannot read a household A shared locus'
    );

    PERFORM tests.assert_equals(
        (SELECT count(*)::int FROM public.loci
         WHERE id = 'eeeeeeee-0000-0000-0000-00000000000c'),
        0,
        'a household B member cannot read a household A private locus'
    );

    PERFORM tests.assert_equals(
        (SELECT count(*)::int FROM public.loci),
        1,
        'a household B member sees only household B loci'
    );
END
$$;

DO $$
BEGIN
    RAISE NOTICE 'loci: unaffiliated user sees nothing';
    PERFORM tests.act_as('cccccccc-0000-0000-0000-000000000001');

    PERFORM tests.assert_equals(
        (SELECT count(*)::int FROM public.loci),
        0,
        'a user in no household reads no loci at all'
    );
END
$$;

-- ---- Loci: within-household sharing is scoped to is_shared -----------------

DO $$
BEGIN
    RAISE NOTICE 'loci: private loci stay private inside a household';
    PERFORM tests.act_as('aaaaaaaa-0000-0000-0000-000000000002');

    PERFORM tests.assert_equals(
        (SELECT count(*)::int FROM public.loci
         WHERE id = 'eeeeeeee-0000-0000-0000-00000000000a'),
        1,
        'a household A member can read the household A shared locus'
    );

    -- The important one: opting a household in must not expose everything else.
    PERFORM tests.assert_equals(
        (SELECT count(*)::int FROM public.loci
         WHERE id = 'eeeeeeee-0000-0000-0000-00000000000c'),
        0,
        'a household co-member cannot read a non-shared locus'
    );
END
$$;

-- ---- Loci: cross-tenant writes --------------------------------------------

DO $$
DECLARE
    affected INT;
BEGIN
    RAISE NOTICE 'loci: cross-household writes';
    PERFORM tests.act_as('bbbbbbbb-0000-0000-0000-000000000002');

    UPDATE public.loci SET transcription = 'tampered'
    WHERE id = 'eeeeeeee-0000-0000-0000-00000000000a';
    GET DIAGNOSTICS affected = ROW_COUNT;
    PERFORM tests.assert_equals(
        affected, 0, 'a household B member cannot update a household A locus'
    );

    DELETE FROM public.loci WHERE id = 'eeeeeeee-0000-0000-0000-00000000000a';
    GET DIAGNOSTICS affected = ROW_COUNT;
    PERFORM tests.assert_equals(
        affected, 0, 'a household B member cannot delete a household A locus'
    );
END
$$;

DO $$
DECLARE
    victim UUID;
BEGIN
    RAISE NOTICE 'loci: cannot forge ownership on insert';
    PERFORM tests.act_as('bbbbbbbb-0000-0000-0000-000000000002');

    -- Read the victim's id from the fixture table, not from public.users: RLS
    -- hides that row, so an `INSERT ... SELECT` would match zero rows and look
    -- like a success without ever exercising the WITH CHECK clause.
    SELECT owner_a INTO victim FROM ids;

    PERFORM tests.assert_raises(
        format(
            $q$INSERT INTO public.loci (user_id, location, transcription)
               VALUES (%L, ST_SetSRID(ST_MakePoint(0, 0), 4326)::geography, 'forged')$q$,
            victim
        ),
        'a user cannot insert a locus attributed to someone else'
    );
END
$$;

DO $$
DECLARE
    affected INT;
BEGIN
    RAISE NOTICE 'loci: a shared locus is read-only to co-members';
    PERFORM tests.act_as('aaaaaaaa-0000-0000-0000-000000000002');

    UPDATE public.loci SET transcription = 'edited by co-member'
    WHERE id = 'eeeeeeee-0000-0000-0000-00000000000a';
    GET DIAGNOSTICS affected = ROW_COUNT;
    PERFORM tests.assert_equals(
        affected, 0, 'a co-member cannot edit a shared locus they do not own'
    );
END
$$;

-- ---- Users -----------------------------------------------------------------

DO $$
DECLARE
    affected INT;
BEGIN
    RAISE NOTICE 'users: profile isolation';
    PERFORM tests.act_as('bbbbbbbb-0000-0000-0000-000000000002');

    PERFORM tests.assert_equals(
        (SELECT count(*)::int FROM public.users),
        1,
        'a user reads only their own profile row'
    );

    -- apns_token lives on this row; a writable other-user row would let one
    -- account redirect another account's push notifications.
    UPDATE public.users SET apns_token = 'stolen'
    WHERE auth_id = 'aaaaaaaa-0000-0000-0000-000000000001';
    GET DIAGNOSTICS affected = ROW_COUNT;
    PERFORM tests.assert_equals(
        affected, 0, 'a user cannot write another user''s profile row'
    );
END
$$;

-- ---- Households and membership --------------------------------------------

DO $$
DECLARE
    affected INT;
BEGIN
    RAISE NOTICE 'households: membership isolation';
    PERFORM tests.act_as('bbbbbbbb-0000-0000-0000-000000000002');

    PERFORM tests.assert_equals(
        (SELECT count(*)::int FROM public.households),
        1,
        'a user sees only households they belong to'
    );

    PERFORM tests.assert_equals(
        (SELECT count(*)::int FROM public.household_members
         WHERE household_id = 'dddddddd-0000-0000-0000-00000000000a'),
        0,
        'a user cannot enumerate another household''s members'
    );

    -- Self-enrolment would defeat the invite flow entirely.
    PERFORM tests.assert_raises(
        $q$INSERT INTO public.household_members (household_id, user_id, display_name, role)
           SELECT 'dddddddd-0000-0000-0000-00000000000a', id, 'Intruder', 'member'
           FROM public.users WHERE auth_id = 'bbbbbbbb-0000-0000-0000-000000000002'$q$,
        'a non-owner cannot add themselves to another household'
    );

    UPDATE public.households SET name = 'Hijacked'
    WHERE id = 'dddddddd-0000-0000-0000-00000000000a';
    GET DIAGNOSTICS affected = ROW_COUNT;
    PERFORM tests.assert_equals(
        affected, 0, 'a non-owner cannot rename another household'
    );

    DELETE FROM public.households WHERE id = 'dddddddd-0000-0000-0000-00000000000a';
    GET DIAGNOSTICS affected = ROW_COUNT;
    PERFORM tests.assert_equals(
        affected, 0, 'a non-owner cannot delete another household'
    );
END
$$;

DO $$
DECLARE
    affected INT;
BEGIN
    RAISE NOTICE 'households: a member cannot evict another household''s members';
    PERFORM tests.act_as('bbbbbbbb-0000-0000-0000-000000000002');

    DELETE FROM public.household_members
    WHERE household_id = 'dddddddd-0000-0000-0000-00000000000a';
    GET DIAGNOSTICS affected = ROW_COUNT;
    PERFORM tests.assert_equals(affected, 0, 'cross-household member removal is denied');
END
$$;

-- ---- Storage objects ------------------------------------------------------

DO $$
DECLARE
    other_prefix TEXT;
BEGIN
    RAISE NOTICE 'storage: audio object isolation';
    PERFORM tests.act_as('cccccccc-0000-0000-0000-000000000001');

    PERFORM tests.assert_equals(
        (SELECT count(*)::int FROM storage.objects WHERE bucket_id = 'loci-audio'),
        0,
        'an unaffiliated user cannot list any audio object'
    );

    -- From the fixture table for the same reason as above.
    SELECT owner_a::text INTO other_prefix FROM ids;

    -- Writing into another user's folder would let an attacker overwrite their
    -- recordings even without read access.
    PERFORM tests.assert_raises(
        format(
            $q$INSERT INTO storage.objects (bucket_id, name)
               VALUES ('loci-audio', %L)$q$,
            other_prefix || '/planted.m4a'
        ),
        'a user cannot write into another user''s audio folder'
    );
END
$$;

DO $$
BEGIN
    RAISE NOTICE 'storage: cross-household audio reads';
    PERFORM tests.act_as('bbbbbbbb-0000-0000-0000-000000000002');

    PERFORM tests.assert_equals(
        (SELECT count(*)::int FROM storage.objects
         WHERE name LIKE (SELECT owner_a::text FROM ids) || '/%'),
        0,
        'a household B member cannot read household A audio objects'
    );
END
$$;

DO $$
BEGIN
    RAISE NOTICE 'storage: own audio remains readable';
    PERFORM tests.act_as('bbbbbbbb-0000-0000-0000-000000000001');

    PERFORM tests.assert_equals(
        (SELECT count(*)::int FROM storage.objects WHERE bucket_id = 'loci-audio'),
        1,
        'a user can still read their own audio objects'
    );
END
$$;

-- ---- Tier enforcement (008) ----------------------------------------------

RESET ROLE;

DO $$
DECLARE
    free_user UUID;
    i INT;
BEGIN
    RAISE NOTICE 'tier: free tier locus cap';

    INSERT INTO auth.users (id, email)
    VALUES ('ffffffff-0000-0000-0000-000000000001', 'free@example.com');

    SELECT id INTO free_user FROM public.users
    WHERE auth_id = 'ffffffff-0000-0000-0000-000000000001';

    PERFORM tests.assert_equals(
        (SELECT subscription_tier FROM public.users WHERE id = free_user),
        'free',
        'a new user starts on the free tier'
    );

    FOR i IN 1..10 LOOP
        INSERT INTO public.loci (user_id, location, transcription)
        VALUES (
            free_user,
            ST_SetSRID(ST_MakePoint(i, i), 4326)::geography,
            'note ' || i
        );
    END LOOP;

    PERFORM tests.assert_equals(
        (SELECT count(*)::int FROM public.loci WHERE user_id = free_user),
        10,
        'a free user can create 10 loci'
    );

    PERFORM tests.assert_raises(
        format(
            $q$INSERT INTO public.loci (user_id, location, transcription)
               VALUES (%L, ST_SetSRID(ST_MakePoint(11, 11), 4326)::geography, 'eleventh')$q$,
            free_user
        ),
        'the 11th locus is rejected server-side for a free user'
    );

    -- Upgrading must lift the cap without any other change.
    UPDATE public.users SET subscription_tier = 'premium' WHERE id = free_user;
    INSERT INTO public.loci (user_id, location, transcription)
    VALUES (free_user, ST_SetSRID(ST_MakePoint(11, 11), 4326)::geography, 'eleventh');

    PERFORM tests.assert_equals(
        (SELECT count(*)::int FROM public.loci WHERE user_id = free_user),
        11,
        'upgrading to premium lifts the cap'
    );

    -- Archived loci must not count against the cap.
    UPDATE public.users SET subscription_tier = 'free' WHERE id = free_user;
    UPDATE public.loci SET is_archived = true WHERE user_id = free_user;
    INSERT INTO public.loci (user_id, location, transcription)
    VALUES (free_user, ST_SetSRID(ST_MakePoint(12, 12), 4326)::geography, 'after archive');

    PERFORM tests.assert_equals(
        (SELECT count(*)::int FROM public.loci
         WHERE user_id = free_user AND is_archived = false),
        1,
        'archived loci do not count against the free cap'
    );
END
$$;

DO $$
BEGIN
    RAISE NOTICE 'All RLS isolation and tier enforcement assertions passed.';
END
$$;

ROLLBACK;
