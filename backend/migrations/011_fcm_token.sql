-- Migration: 011_fcm_token
--
-- US-197: Android had no push transport at all — no FCM dependency on the client
-- and no column to store a token in. `users.apns_token` (001) covered iOS only,
-- so household-share notifications and the weekly digest could never reach an
-- Android device.
--
-- Safe to re-run.

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS fcm_token TEXT;

COMMENT ON COLUMN public.users.fcm_token IS
    'Firebase Cloud Messaging registration token for Android devices. Mirrors '
    'apns_token for iOS. Cleared on sign-out and when FCM reports the token '
    'UNREGISTERED (US-197).';

-- Mirrors idx_users_auth_id's purpose: the digest cron scans for users with a
-- non-null token, so a partial index keeps that scan off the tokenless majority.
CREATE INDEX IF NOT EXISTS idx_users_fcm_token
    ON public.users (fcm_token)
    WHERE fcm_token IS NOT NULL;

-- The equivalent index for iOS was never created; the same scan applies.
CREATE INDEX IF NOT EXISTS idx_users_apns_token
    ON public.users (apns_token)
    WHERE apns_token IS NOT NULL;
