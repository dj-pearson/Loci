-- Seed: test data for development
-- Idempotent: uses ON CONFLICT DO NOTHING throughout.
-- Note: These reference auth.users IDs that must exist first.
-- In dev, create two auth users manually, then replace these UUIDs.

-- Fixed UUIDs for reproducible seeding
DO $$
DECLARE
    user1_auth_id UUID := 'a1111111-1111-1111-1111-111111111111';
    user2_auth_id UUID := 'a2222222-2222-2222-2222-222222222222';
    user1_id UUID;
    user2_id UUID;
    household_id UUID := 'h1111111-1111-1111-1111-111111111111';
BEGIN

-- Test user 1: premium subscriber
INSERT INTO public.users (id, auth_id, display_name, subscription_tier)
VALUES (
    'u1111111-1111-1111-1111-111111111111',
    user1_auth_id,
    'Alice Tester',
    'premium'
)
ON CONFLICT (auth_id) DO NOTHING;

-- Test user 2: family subscriber
INSERT INTO public.users (id, auth_id, display_name, subscription_tier)
VALUES (
    'u2222222-2222-2222-2222-222222222222',
    user2_auth_id,
    'Bob Tester',
    'family'
)
ON CONFLICT (auth_id) DO NOTHING;

user1_id := 'u1111111-1111-1111-1111-111111111111';
user2_id := 'u2222222-2222-2222-2222-222222222222';

-- Household: The Testers
INSERT INTO public.households (id, name, owner_id, invite_code, invite_expires_at)
VALUES (
    household_id,
    'The Testers',
    user2_id,
    'TEST42',
    now() + INTERVAL '48 hours'
)
ON CONFLICT (id) DO NOTHING;

-- Both users are members of the household
INSERT INTO public.household_members (household_id, user_id, display_name, role)
VALUES
    (household_id, user2_id, 'Bob Tester', 'owner'),
    (household_id, user1_id, 'Alice Tester', 'member')
ON CONFLICT (household_id, user_id) DO NOTHING;

-- 10 diverse loci across various categories, locations, and states
-- Locus 1: San Francisco coffee shop (food, Alice, personal)
INSERT INTO public.loci (id, user_id, location, location_name, transcription, category, is_shared, is_archived)
VALUES (
    'l0000001-0000-0000-0000-000000000001',
    user1_id,
    ST_SetSRID(ST_MakePoint(-122.4194, 37.7749), 4326)::geography,
    'Blue Bottle Coffee, SF',
    'Amazing pour-over here. Try the single origin Ethiopian.',
    'food',
    false,
    false
)
ON CONFLICT (id) DO NOTHING;

-- Locus 2: Golden Gate Park (outdoor, Alice, personal)
INSERT INTO public.loci (id, user_id, location, location_name, transcription, category, is_shared, is_archived)
VALUES (
    'l0000002-0000-0000-0000-000000000002',
    user1_id,
    ST_SetSRID(ST_MakePoint(-122.4862, 37.7694), 4326)::geography,
    'Golden Gate Park',
    'Beautiful spot near the Japanese Tea Garden. Come back in spring for cherry blossoms.',
    'outdoor',
    false,
    false
)
ON CONFLICT (id) DO NOTHING;

-- Locus 3: Parking garage downtown (parking, Alice, personal)
INSERT INTO public.loci (id, user_id, location, location_name, transcription, category, is_shared, is_archived)
VALUES (
    'l0000003-0000-0000-0000-000000000003',
    user1_id,
    ST_SetSRID(ST_MakePoint(-122.4089, 37.7851), 4326)::geography,
    'Union Square Garage',
    'Level 3, section B. Cheapest parking downtown on weekends.',
    'parking',
    false,
    false
)
ON CONFLICT (id) DO NOTHING;

-- Locus 4: Pharmacy (health, Alice, archived)
INSERT INTO public.loci (id, user_id, location, location_name, transcription, category, is_shared, is_archived)
VALUES (
    'l0000004-0000-0000-0000-000000000004',
    user1_id,
    ST_SetSRID(ST_MakePoint(-122.4233, 37.7620), 4326)::geography,
    'Walgreens Castro',
    'This location has the best wait times for prescriptions. Usually under ten minutes.',
    'health',
    false,
    true
)
ON CONFLICT (id) DO NOTHING;

-- Locus 5: Airport tip (travel, Bob, shared with household)
INSERT INTO public.loci (id, user_id, household_id, location, location_name, transcription, category, is_shared, created_by_name, is_archived)
VALUES (
    'l0000005-0000-0000-0000-000000000005',
    user2_id,
    household_id,
    ST_SetSRID(ST_MakePoint(-122.3790, 37.6213), 4326)::geography,
    'SFO Terminal 2',
    'TSA PreCheck line is on the far left. Global Entry kiosk near gate 25.',
    'travel',
    true,
    'Bob Tester',
    false
)
ON CONFLICT (id) DO NOTHING;

-- Locus 6: Grocery store (shopping, Bob, shared)
INSERT INTO public.loci (id, user_id, household_id, location, location_name, transcription, category, is_shared, created_by_name, is_archived)
VALUES (
    'l0000006-0000-0000-0000-000000000006',
    user2_id,
    household_id,
    ST_SetSRID(ST_MakePoint(-122.4312, 37.7632), 4326)::geography,
    'Trader Joes Castro',
    'Best time to shop is Tuesday mornings. They restock the frozen section on Mondays.',
    'shopping',
    true,
    'Bob Tester',
    false
)
ON CONFLICT (id) DO NOTHING;

-- Locus 7: Warning about a road (warning, Alice, personal)
INSERT INTO public.loci (id, user_id, location, location_name, transcription, category, is_shared, is_archived)
VALUES (
    'l0000007-0000-0000-0000-000000000007',
    user1_id,
    ST_SetSRID(ST_MakePoint(-122.4474, 37.8020), 4326)::geography,
    'Lombard St',
    'Construction on the south side. Detour through Chestnut Street instead.',
    'warning',
    false,
    false
)
ON CONFLICT (id) DO NOTHING;

-- Locus 8: Home reminder (home, Bob, personal)
INSERT INTO public.loci (id, user_id, location, location_name, transcription, category, is_shared, is_archived)
VALUES (
    'l0000008-0000-0000-0000-000000000008',
    user2_id,
    ST_SetSRID(ST_MakePoint(-122.4350, 37.7590), 4326)::geography,
    'Home',
    'Remember to water the plants on the balcony every other day.',
    'home',
    false,
    false
)
ON CONFLICT (id) DO NOTHING;

-- Locus 9: General note at distant location — New York (general, Alice, personal)
INSERT INTO public.loci (id, user_id, location, location_name, transcription, category, is_shared, is_archived)
VALUES (
    'l0000009-0000-0000-0000-000000000009',
    user1_id,
    ST_SetSRID(ST_MakePoint(-73.9857, 40.7484), 4326)::geography,
    'Empire State Building',
    'Get tickets online in advance. The 86th floor deck has the best views.',
    'general',
    false,
    false
)
ON CONFLICT (id) DO NOTHING;

-- Locus 10: Tip at distant location — Portland (tip, Bob, shared)
INSERT INTO public.loci (id, user_id, household_id, location, location_name, transcription, category, is_shared, created_by_name, is_archived)
VALUES (
    'l0000010-0000-0000-0000-000000000010',
    user2_id,
    household_id,
    ST_SetSRID(ST_MakePoint(-122.6765, 45.5231), 4326)::geography,
    'Powell''s Books, Portland',
    'The rare book room is on the third floor. Ask for the staff picks section.',
    'tip',
    true,
    'Bob Tester',
    false
)
ON CONFLICT (id) DO NOTHING;

END $$;
