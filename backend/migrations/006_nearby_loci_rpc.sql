-- Migration: 006_nearby_loci_rpc
-- RPC function for querying loci within a given radius using PostGIS.

CREATE OR REPLACE FUNCTION public.nearby_loci(
    p_user_id UUID,
    p_lat DOUBLE PRECISION,
    p_lon DOUBLE PRECISION,
    p_radius_meters DOUBLE PRECISION DEFAULT 100
)
RETURNS TABLE (
    id UUID,
    transcription TEXT,
    category TEXT,
    location_name TEXT,
    created_at TIMESTAMPTZ,
    is_shared BOOLEAN,
    created_by_name TEXT,
    distance_meters DOUBLE PRECISION
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        l.id,
        l.transcription,
        l.category,
        l.location_name,
        l.created_at,
        l.is_shared,
        l.created_by_name,
        ST_Distance(l.location, ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography) AS distance_meters
    FROM public.loci l
    WHERE l.is_archived = false
      AND (
          l.user_id = p_user_id
          OR (
              l.is_shared = true
              AND l.household_id IN (
                  SELECT hm.household_id FROM public.household_members hm
                  WHERE hm.user_id = p_user_id
              )
          )
      )
      AND ST_DWithin(
          l.location,
          ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography,
          p_radius_meters
      )
    ORDER BY distance_meters ASC;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;
