-- Migration: 003_create_households
-- Creates households and household_members tables for family sharing.

CREATE TABLE IF NOT EXISTS public.households (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    owner_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    invite_code TEXT UNIQUE,
    invite_expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.household_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    display_name TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'member',
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(household_id, user_id)
);

-- Index for looking up a user's households
CREATE INDEX IF NOT EXISTS idx_household_members_user_id ON public.household_members(user_id);

-- Add foreign key from loci.household_id to households
ALTER TABLE public.loci
    ADD CONSTRAINT fk_loci_household
    FOREIGN KEY (household_id) REFERENCES public.households(id) ON DELETE SET NULL;

-- Enable RLS
ALTER TABLE public.households ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.household_members ENABLE ROW LEVEL SECURITY;
