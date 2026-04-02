-- ============================================================================
-- Migration: reset_properties
-- ============================================================================
-- Functions to reset and batch-(re)populate previous_properties,
-- previous_position_data, and cluster on public.records.
--
-- Functions:
--   - reset_previous_properties()        → clears the 3 fields for all / subset
--   - batch_update_records()             → fires trigger per row (legacy helper)
--   - update_records_cluster()           → batch-fills cluster only
--
-- For a full repopulation without the trigger overhead, use:
--   SELECT public.refresh_plot_nested_json_cached();   -- from add_properties.sql
-- ============================================================================
-- ────────────────────────────────────────────────────────────────────────────
-- 1. reset_previous_properties
-- ────────────────────────────────────────────────────────────────────────────
-- Clears previous_properties, previous_position_data, and cluster so they can
-- be re-populated via refresh_plot_nested_json_cached() or the row trigger.
--
-- Usage:
--   SELECT public.reset_previous_properties();           -- reset ALL records
--   SELECT public.reset_previous_properties(200);        -- batch size
--   SELECT public.reset_previous_properties(200, 1234);  -- only cluster 1234
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.reset_previous_properties(
        p_batch_size INTEGER DEFAULT 500,
        p_cluster_name INTEGER DEFAULT NULL
    ) RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE batch_count INTEGER;
total INTEGER := 0;
BEGIN -- Disable trigger so the reset UPDATE doesn't re-fire fill_previous_properties
ALTER TABLE public.records DISABLE TRIGGER before_record_insert_or_update;
RAISE NOTICE 'Resetting previous_properties (batch %, cluster %) ...',
p_batch_size,
COALESCE(p_cluster_name::text, 'ALL');
LOOP WITH batch AS (
    SELECT r.id
    FROM public.records r
    WHERE (
            r.previous_properties IS NOT NULL
            AND r.previous_properties <> '{}'::jsonb
        )
        OR (
            r.previous_position_data IS NOT NULL
            AND r.previous_position_data <> '{}'::jsonb
        )
        OR r.cluster IS NOT NULL -- optional cluster filter
        AND (
            p_cluster_name IS NULL
            OR r.cluster_name = p_cluster_name
        )
    ORDER BY r.id
    LIMIT p_batch_size
)
UPDATE public.records r
SET previous_properties = '{}'::jsonb,
    previous_position_data = '{}'::jsonb,
    cluster = NULL,
    previous_properties_updated_at = NULL
FROM batch b
WHERE r.id = b.id;
GET DIAGNOSTICS batch_count = ROW_COUNT;
EXIT
WHEN batch_count = 0;
total := total + batch_count;
RAISE NOTICE '  % records reset so far',
total;
PERFORM pg_sleep(0.1);
END LOOP;
ALTER TABLE public.records ENABLE TRIGGER before_record_insert_or_update;
RAISE NOTICE 'Reset complete: % records cleared',
total;
RETURN total;
EXCEPTION
WHEN OTHERS THEN BEGIN
ALTER TABLE public.records ENABLE TRIGGER before_record_insert_or_update;
EXCEPTION
WHEN OTHERS THEN
/* already enabled */
END;
RAISE;
END;
$$;
-- Permissions
REVOKE ALL ON FUNCTION public.reset_previous_properties(INTEGER, INTEGER)
FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reset_previous_properties(INTEGER, INTEGER)
FROM anon;
REVOKE ALL ON FUNCTION public.reset_previous_properties(INTEGER, INTEGER)
FROM authenticated;
GRANT EXECUTE ON FUNCTION public.reset_previous_properties(INTEGER, INTEGER) TO postgres;
GRANT EXECUTE ON FUNCTION public.reset_previous_properties(INTEGER, INTEGER) TO service_role;
-- ────────────────────────────────────────────────────────────────────────────
-- 2. update_records_cluster  (moved from functions.sql)
-- ────────────────────────────────────────────────────────────────────────────
-- Batch-fills public.records.cluster from inventory_archive.cluster.
-- Only touches rows where cluster IS NULL or empty.
--
-- Usage:
--   SELECT public.update_records_cluster();        -- default batch 500
--   SELECT public.update_records_cluster(1000);
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.update_records_cluster(p_batch_size INTEGER DEFAULT 500) RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public,
    inventory_archive AS $$
DECLARE batch_count INTEGER := 0;
total_processed INTEGER := 0;
BEGIN RAISE NOTICE 'Starting bulk update of records.cluster field...';
LOOP WITH cluster_batch AS (
    SELECT r.id,
        c.cluster_name
    FROM public.records r
        LEFT JOIN inventory_archive.cluster c ON c.cluster_name = r.cluster_name
    WHERE r.cluster IS NULL
        OR r.cluster = '{}'::jsonb
    LIMIT p_batch_size
)
UPDATE public.records r
SET cluster = (
        SELECT row_to_json(c)::jsonb
        FROM inventory_archive.cluster c
        WHERE c.cluster_name = cb.cluster_name
    ),
    updated_at = NOW()
FROM cluster_batch cb
WHERE r.id = cb.id;
GET DIAGNOSTICS batch_count = ROW_COUNT;
IF batch_count = 0 THEN EXIT;
END IF;
total_processed := total_processed + batch_count;
RAISE NOTICE 'Processed % records in this batch (total: %)...',
batch_count,
total_processed;
END LOOP;
RAISE NOTICE 'Bulk update completed: % records processed',
total_processed;
RETURN total_processed;
EXCEPTION
WHEN OTHERS THEN RAISE NOTICE 'Error in bulk update: %',
SQLERRM;
RAISE;
END;
$$;
-- Permissions
REVOKE ALL ON FUNCTION public.update_records_cluster(INTEGER)
FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_records_cluster(INTEGER)
FROM anon;
REVOKE ALL ON FUNCTION public.update_records_cluster(INTEGER)
FROM authenticated;
GRANT EXECUTE ON FUNCTION public.update_records_cluster(INTEGER) TO postgres;
GRANT EXECUTE ON FUNCTION public.update_records_cluster(INTEGER) TO service_role;
-- ────────────────────────────────────────────────────────────────────────────
-- 3. batch_update_records  (moved from functions.sql)
-- ────────────────────────────────────────────────────────────────────────────
-- Legacy helper: touches plot_id on each row to fire the
-- before_record_insert_or_update trigger which populates
-- previous_properties, previous_position_data, and cluster one by one.
--
-- For bulk repopulation prefer refresh_plot_nested_json_cached() instead —
-- it writes directly without trigger overhead.
--
-- Usage: SELECT public.batch_update_records(1000);
-- ────────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.batch_update_records;
CREATE OR REPLACE FUNCTION public.batch_update_records(batch_size INTEGER) RETURNS VOID AS $$
DECLARE processed INTEGER := 0;
rows_updated INTEGER;
BEGIN
ALTER TABLE public.records DISABLE TRIGGER before_record_insert_or_update;
LOOP
UPDATE public.records
SET previous_properties_updated_at = NOW(),
    plot_id = plot_id
WHERE id IN (
        SELECT id
        FROM public.records
        WHERE previous_properties IS NULL
            OR previous_properties::text = '{}'
            OR previous_properties_updated_at IS NULL
            OR previous_properties_updated_at < NOW() - INTERVAL '1 day'
        ORDER BY id
        LIMIT batch_size
    );
GET DIAGNOSTICS rows_updated = ROW_COUNT;
IF rows_updated = 0 THEN EXIT;
END IF;
processed := processed + rows_updated;
RAISE NOTICE 'Processed % records total',
processed;
PERFORM pg_sleep(0.1);
END LOOP;
RAISE NOTICE 'Finished processing % records total',
processed;
ALTER TABLE public.records ENABLE TRIGGER before_record_insert_or_update;
END;
$$ LANGUAGE plpgsql;
-- Permissions
REVOKE ALL ON FUNCTION public.batch_update_records(INTEGER)
FROM PUBLIC;
REVOKE ALL ON FUNCTION public.batch_update_records(INTEGER)
FROM anon;
REVOKE ALL ON FUNCTION public.batch_update_records(INTEGER)
FROM authenticated;
GRANT EXECUTE ON FUNCTION public.batch_update_records(INTEGER) TO postgres;
GRANT EXECUTE ON FUNCTION public.batch_update_records(INTEGER) TO service_role;