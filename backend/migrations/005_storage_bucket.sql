-- Migration: 005_storage_bucket
-- Creates Supabase Storage bucket for audio files with RLS policies.

-- Create the loci-audio storage bucket
INSERT INTO storage.buckets (id, name, file_size_limit, allowed_mime_types, public)
VALUES (
    'loci-audio',
    'loci-audio',
    10485760, -- 10MB
    ARRAY['audio/mp4', 'audio/x-m4a', 'audio/aac'],
    false
)
ON CONFLICT (id) DO UPDATE SET
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Policy: users can upload to their own folder (user_id/filename)
CREATE POLICY storage_audio_insert ON storage.objects
    FOR INSERT
    WITH CHECK (
        bucket_id = 'loci-audio'
        AND (storage.foldername(name))[1] = public.current_user_id()::text
    );

-- Policy: users can read their own files
CREATE POLICY storage_audio_select_own ON storage.objects
    FOR SELECT
    USING (
        bucket_id = 'loci-audio'
        AND (storage.foldername(name))[1] = public.current_user_id()::text
    );

-- Policy: users can read shared household files
-- (files belonging to other members in their households)
CREATE POLICY storage_audio_select_shared ON storage.objects
    FOR SELECT
    USING (
        bucket_id = 'loci-audio'
        AND (storage.foldername(name))[1] IN (
            SELECT hm.user_id::text
            FROM public.household_members hm
            WHERE hm.household_id IN (
                SELECT household_id FROM public.household_members
                WHERE user_id = public.current_user_id()
            )
        )
    );

-- Policy: users can delete only their own files
CREATE POLICY storage_audio_delete_own ON storage.objects
    FOR DELETE
    USING (
        bucket_id = 'loci-audio'
        AND (storage.foldername(name))[1] = public.current_user_id()::text
    );

-- Policy: users can update only their own files
CREATE POLICY storage_audio_update_own ON storage.objects
    FOR UPDATE
    USING (
        bucket_id = 'loci-audio'
        AND (storage.foldername(name))[1] = public.current_user_id()::text
    );
