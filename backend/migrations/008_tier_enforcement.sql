-- Migration: 008_tier_enforcement
-- Server-side enforcement of free tier loci limit (max 10 non-archived personal loci).
-- Prevents bypassing client-side checks with modified clients.

-- Function to check if a user can insert a new locus based on their subscription tier.
CREATE OR REPLACE FUNCTION public.check_loci_tier_limit()
RETURNS TRIGGER AS $$
DECLARE
    user_tier TEXT;
    active_loci_count INT;
    max_free_loci CONSTANT INT := 10;
BEGIN
    -- Look up the user's subscription tier
    SELECT subscription_tier INTO user_tier
    FROM public.users
    WHERE id = NEW.user_id;

    -- Premium and family tiers have unlimited loci
    IF user_tier IN ('premium', 'family') THEN
        RETURN NEW;
    END IF;

    -- Count existing non-archived personal (non-shared) loci for this user
    SELECT COUNT(*) INTO active_loci_count
    FROM public.loci
    WHERE user_id = NEW.user_id
      AND is_archived = false;

    IF active_loci_count >= max_free_loci THEN
        RAISE EXCEPTION 'Free tier limit reached: maximum % active loci allowed. Upgrade to Premium for unlimited loci.', max_free_loci
            USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Trigger fires before each INSERT on loci table
CREATE TRIGGER enforce_loci_tier_limit
    BEFORE INSERT ON public.loci
    FOR EACH ROW
    EXECUTE FUNCTION public.check_loci_tier_limit();
