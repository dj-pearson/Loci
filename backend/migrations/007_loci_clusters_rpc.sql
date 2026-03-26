-- Migration: 007_loci_clusters_rpc
-- RPC function for finding clusters of loci for AI summary generation.

CREATE OR REPLACE FUNCTION public.loci_clusters(
    p_user_id UUID,
    p_min_count INTEGER DEFAULT 3,
    p_cluster_radius DOUBLE PRECISION DEFAULT 50
)
RETURNS TABLE (
    user_id UUID,
    centroid_lon DOUBLE PRECISION,
    centroid_lat DOUBLE PRECISION,
    loci_count BIGINT,
    location_name TEXT,
    transcriptions TEXT[],
    loci_ids UUID[]
) AS $$
BEGIN
    RETURN QUERY
    WITH clustered AS (
        SELECT
            l.id,
            l.user_id AS uid,
            l.transcription,
            l.location_name AS loc_name,
            ST_ClusterDBSCAN(l.location::geometry, eps := p_cluster_radius, minpoints := p_min_count)
                OVER () AS cluster_id,
            ST_X(l.location::geometry) AS lon,
            ST_Y(l.location::geometry) AS lat
        FROM public.loci l
        WHERE l.user_id = p_user_id
          AND l.is_archived = false
          AND l.category != 'general' -- skip existing summaries
    )
    SELECT
        c.uid AS user_id,
        AVG(c.lon) AS centroid_lon,
        AVG(c.lat) AS centroid_lat,
        COUNT(*) AS loci_count,
        MODE() WITHIN GROUP (ORDER BY c.loc_name) AS location_name,
        ARRAY_AGG(c.transcription) AS transcriptions,
        ARRAY_AGG(c.id) AS loci_ids
    FROM clustered c
    WHERE c.cluster_id IS NOT NULL
    GROUP BY c.uid, c.cluster_id
    HAVING COUNT(*) >= p_min_count;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;
