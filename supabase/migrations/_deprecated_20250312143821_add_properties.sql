-- ============================================================================
-- Migration: add_properties
-- ============================================================================
-- Replaces the materialized view approach with direct row-by-row updates.
-- Eliminates plot_nested_json_cached (mat view) and its lock/IO problems.
--
-- New functions:
--   - get_plot_nested_json_by_id()  → queries inventory_archive directly (1 plot)
--   - fill_previous_properties()    → trigger, queries inventory_archive directly
--   - refresh_plot_nested_json_cached() → batch-updates records directly
--
-- Dropped:
--   - plot_nested_json_cached (MATERIALIZED VIEW)
-- ============================================================================
-- ────────────────────────────────────────────────────────────────────────────
-- 1. Drop the materialized view  (no longer needed)
-- ────────────────────────────────────────────────────────────────────────────
DROP MATERIALIZED VIEW IF EXISTS public.plot_nested_json_cached CASCADE;
-- ────────────────────────────────────────────────────────────────────────────
-- 2. get_plot_nested_json_by_id  (replaces mat-view reader)
-- ────────────────────────────────────────────────────────────────────────────
-- Queries the base view for exactly ONE plot.  With the existing index
-- idx_plot_cluster_name on inventory_archive.plot(cluster_name, plot_name,
-- interval_name), the WHERE predicates are pushed into each correlated
-- subquery → only one plot row is processed (~5 ms).
-- ────────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.get_plot_nested_json_by_id(UUID, INTEGER, INTEGER) CASCADE;
CREATE OR REPLACE FUNCTION public.get_plot_nested_json_by_id(
        p_plot_id UUID,
        p_cluster_name INTEGER DEFAULT NULL,
        p_plot_name INTEGER DEFAULT NULL
    ) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public,
    inventory_archive AS $$
DECLARE result jsonb;
BEGIN
SELECT row_to_json(t)::jsonb INTO result
FROM public.plot_nested_json t
WHERE t.cluster_name = p_cluster_name
    AND t.plot_name = p_plot_name;
RETURN result;
END;
$$;
-- Permissions
REVOKE ALL ON FUNCTION public.get_plot_nested_json_by_id(UUID, INTEGER, INTEGER)
FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_plot_nested_json_by_id(UUID, INTEGER, INTEGER)
FROM anon;
REVOKE ALL ON FUNCTION public.get_plot_nested_json_by_id(UUID, INTEGER, INTEGER)
FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_plot_nested_json_by_id(UUID, INTEGER, INTEGER) TO postgres;
GRANT EXECUTE ON FUNCTION public.get_plot_nested_json_by_id(UUID, INTEGER, INTEGER) TO service_role;
-- ────────────────────────────────────────────────────────────────────────────
-- 3. fill_previous_properties  (trigger — rewired to query directly)
-- ────────────────────────────────────────────────────────────────────────────
-- Fires on INSERT or UPDATE OF previous_properties_updated_at, plot_id,
-- cluster_name.  Populates previous_properties, previous_position_data,
-- and cluster from inventory_archive — no mat view involved.
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fill_previous_properties() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public,
    inventory_archive AS $$
DECLARE plot_data jsonb;
position_data jsonb;
cluster_data jsonb;
BEGIN NEW.message := COALESCE(NEW.message, '') || 'Trigger fired for ' || TG_OP || ' operation';
NEW.previous_properties := '{}'::jsonb;
NEW.previous_position_data := '{}'::jsonb;
-- ── Cluster data ────────────────────────────────────────────────────
IF NEW.cluster_name IS NOT NULL THEN BEGIN
SELECT public.fill_cluster_data(NEW.cluster_name) INTO cluster_data;
IF cluster_data IS NOT NULL THEN NEW.cluster := cluster_data;
END IF;
EXCEPTION
WHEN OTHERS THEN RAISE NOTICE 'Error fetching cluster data for cluster_name %: %',
NEW.cluster_name,
SQLERRM;
END;
END IF;
-- ── Plot data (previous_properties) ─────────────────────────────────
IF NEW.plot_id IS NOT NULL THEN BEGIN
SELECT public.get_plot_nested_json_by_id(NEW.plot_id, NEW.cluster_name, NEW.plot_name) INTO plot_data;
IF plot_data IS NOT NULL THEN NEW.previous_properties := plot_data;
NEW.message := 'Plot data found and set';
ELSE NEW.message := 'No plot data found';
END IF;
EXCEPTION
WHEN OTHERS THEN NEW.message := 'Error: ' || SQLERRM;
RAISE NOTICE 'Error fetching plot data for %: %',
NEW.plot_id,
SQLERRM;
END;
-- ── Position data (previous_position_data) ──────────────────────
BEGIN
SELECT json_object_agg(
        p.interval_name,
        json_build_object(
            'longitude_median',
            extensions.ST_X(pos.position_median),
            'latitude_median',
            extensions.ST_Y(pos.position_median),
            'longitude_mean',
            extensions.ST_X(pos.position_mean),
            'latitude_mean',
            extensions.ST_Y(pos.position_mean),
            'hdop_mean',
            pos.hdop_mean,
            'pdop_mean',
            pos.pdop_mean,
            'satellites_count_mean',
            pos.satellites_count_mean,
            'measurement_count',
            pos.measurement_count,
            'rtcm_age',
            pos.rtcm_age,
            'start_measurement',
            pos.start_measurement,
            'stop_measurement',
            pos.stop_measurement,
            'device_gnss',
            pos.device_gnss,
            'quality',
            pos.quality
        )
    ) INTO position_data
FROM inventory_archive.plot p
    JOIN inventory_archive.position pos ON pos.plot_id = p.id
WHERE p.cluster_name = NEW.cluster_name
    AND p.plot_name = NEW.plot_name;
IF position_data IS NOT NULL THEN NEW.previous_position_data := position_data;
END IF;
EXCEPTION
WHEN OTHERS THEN RAISE NOTICE 'Error fetching position data for %: %',
NEW.plot_id,
SQLERRM;
END;
ELSE NEW.message := 'plot_id IS NULL';
END IF;
RETURN NEW;
END;
$$;
-- Re-create the trigger (definition unchanged, function body updated above)
DROP TRIGGER IF EXISTS before_record_insert_or_update ON public.records;
CREATE TRIGGER before_record_insert_or_update BEFORE
INSERT
    OR
UPDATE OF previous_properties_updated_at,
    plot_id,
    cluster_name ON public.records FOR EACH ROW EXECUTE FUNCTION public.fill_previous_properties();
-- ────────────────────────────────────────────────────────────────────────────
-- 4. refresh_plot_nested_json_cached  (rewritten: batch-updates records)
-- ────────────────────────────────────────────────────────────────────────────
-- Keeps the same function name so existing callers (README, sync script)
-- continue to work.  Internally it now batch-updates records directly:
--   previous_properties, previous_position_data, cluster
-- No materialized view involved.
--
-- Usage:  SELECT public.refresh_plot_nested_json_cached();        -- default
--         SELECT public.refresh_plot_nested_json_cached(100);     -- smaller batches
-- ────────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.refresh_plot_nested_json_cached() CASCADE;
DROP FUNCTION IF EXISTS public.refresh_plot_nested_json_cached(INTEGER) CASCADE;
CREATE OR REPLACE FUNCTION public.refresh_plot_nested_json_cached(p_batch_size INTEGER DEFAULT 200) RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public,
    inventory_archive AS $$
DECLARE lock_key bigint := hashtext('refresh_plot_nested_json_cached');
got_lock boolean;
batch_count integer;
total integer := 0;
BEGIN -- ── Guard: one refresh at a time ────────────────────────────────────
SELECT pg_try_advisory_xact_lock(lock_key) INTO got_lock;
IF NOT got_lock THEN RAISE NOTICE 'refresh_plot_nested_json_cached: already in progress — skipping';
RETURN 0;
END IF;
-- Disable the trigger so our batch UPDATE doesn't re-fire it
ALTER TABLE public.records DISABLE TRIGGER before_record_insert_or_update;
RAISE NOTICE 'Batch-updating records (batch size %) ...',
p_batch_size;
SET LOCAL work_mem = '64MB';
LOOP -- ── Batch: pick records needing a refresh ───────────────────────
WITH batch AS (
    SELECT r.id,
        r.cluster_name,
        r.plot_name
    FROM public.records r
    WHERE r.previous_properties IS NULL
        OR r.previous_properties = '{}'::jsonb
        OR r.previous_properties_updated_at IS NULL
        OR r.previous_properties_updated_at < NOW() - INTERVAL '1 day'
    ORDER BY r.id
    LIMIT p_batch_size
)
UPDATE public.records r
SET -- previous_properties: nested JSON from base view (1 plot per row)
    previous_properties = COALESCE(
        (
            SELECT row_to_json(v)::jsonb
            FROM public.plot_nested_json v
            WHERE v.cluster_name = b.cluster_name
                AND v.plot_name = b.plot_name
        ),
        '{}'::jsonb
    ),
    -- cluster
    cluster = COALESCE(
        (
            SELECT row_to_json(c)::jsonb
            FROM inventory_archive.cluster c
            WHERE c.cluster_name = b.cluster_name
        ),
        r.cluster
    ),
    -- previous_position_data
    previous_position_data = COALESCE(
        (
            SELECT json_object_agg(
                    p.interval_name,
                    json_build_object(
                        'longitude_median',
                        extensions.ST_X(pos.position_median),
                        'latitude_median',
                        extensions.ST_Y(pos.position_median),
                        'longitude_mean',
                        extensions.ST_X(pos.position_mean),
                        'latitude_mean',
                        extensions.ST_Y(pos.position_mean),
                        'hdop_mean',
                        pos.hdop_mean,
                        'pdop_mean',
                        pos.pdop_mean,
                        'satellites_count_mean',
                        pos.satellites_count_mean,
                        'measurement_count',
                        pos.measurement_count,
                        'rtcm_age',
                        pos.rtcm_age,
                        'start_measurement',
                        pos.start_measurement,
                        'stop_measurement',
                        pos.stop_measurement,
                        'device_gnss',
                        pos.device_gnss,
                        'quality',
                        pos.quality
                    )
                )::jsonb
            FROM inventory_archive.plot p
                JOIN inventory_archive.position pos ON pos.plot_id = p.id
            WHERE p.cluster_name = b.cluster_name
                AND p.plot_name = b.plot_name
        ),
        r.previous_position_data
    ),
    previous_properties_updated_at = NOW()
FROM batch b
WHERE r.id = b.id;
GET DIAGNOSTICS batch_count = ROW_COUNT;
EXIT
WHEN batch_count = 0;
total := total + batch_count;
RAISE NOTICE '  % records updated so far',
total;
-- Brief pause to yield I/O to concurrent queries
PERFORM pg_sleep(0.15);
END LOOP;
ALTER TABLE public.records ENABLE TRIGGER before_record_insert_or_update;
RAISE NOTICE 'Refresh complete: % records updated',
total;
RETURN total;
EXCEPTION
WHEN OTHERS THEN -- Always re-enable the trigger
BEGIN
ALTER TABLE public.records ENABLE TRIGGER before_record_insert_or_update;
EXCEPTION
WHEN OTHERS THEN
/* already enabled — ignore */
END;
RAISE;
END;
$$;
-- Permissions
REVOKE ALL ON FUNCTION public.refresh_plot_nested_json_cached(INTEGER)
FROM PUBLIC;
REVOKE ALL ON FUNCTION public.refresh_plot_nested_json_cached(INTEGER)
FROM anon;
REVOKE ALL ON FUNCTION public.refresh_plot_nested_json_cached(INTEGER)
FROM authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_plot_nested_json_cached(INTEGER) TO postgres;
GRANT EXECUTE ON FUNCTION public.refresh_plot_nested_json_cached(INTEGER) TO service_role;