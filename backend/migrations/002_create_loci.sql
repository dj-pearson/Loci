-- Migration: 002_create_loci
-- Creates the loci table with PostGIS spatial indexing.

-- Enable PostGIS extension
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS public.loci (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    household_id UUID,
    location GEOGRAPHY(POINT, 4326) NOT NULL,
    location_name TEXT,
    audio_url TEXT,
    transcription TEXT NOT NULL DEFAULT '',
    category TEXT NOT NULL DEFAULT 'general',
    is_shared BOOLEAN NOT NULL DEFAULT false,
    created_by_name TEXT,
    is_archived BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Spatial index on location for geo-queries
CREATE INDEX IF NOT EXISTS idx_loci_location ON public.loci USING GIST (location);

-- Composite index for user's active loci
CREATE INDEX IF NOT EXISTS idx_loci_user_archived ON public.loci(user_id, is_archived);

-- Composite index for shared household loci
CREATE INDEX IF NOT EXISTS idx_loci_household_shared ON public.loci(household_id, is_shared);

-- Enable RLS
ALTER TABLE public.loci ENABLE ROW LEVEL SECURITY;
