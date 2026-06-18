-- ============================================================================
-- FIX: add_plot_ids_to_records skips plots and inserts too few records
-- ============================================================================
-- The batching loop combined two mechanisms that each advance the candidate
-- window, so they double-counted each other:
--
--   WHERE ... AND NOT EXISTS (SELECT 1 FROM public.records r            -- (a)
--                             WHERE r.cluster_name = p.cluster_name
--                               AND r.plot_name    = p.plot_name)
--   ORDER BY p.id
--   LIMIT p_batch_size OFFSET total_processed                          -- (b)
--
-- (a) already removes every plot inserted by previous iterations from the
-- candidate set, so the window slides forward on its own. Adding (b) skips a
-- further `total_processed` rows on top, leaving growing gaps:
--
--   iter 1: OFFSET 0    -> inserts plots ranked    1 .. 1000
--   iter 2: OFFSET 1000 -> inserts plots ranked 2001 .. 3000   (1001..2000 skipped)
--   iter 3: OFFSET 2000 -> inserts plots ranked 5001 .. 6000   (3001..5000 skipped)
--
-- Result: far fewer records than expected, exiting early once a batch lands
-- entirely in a gap.
--
-- Fix: keep the NOT EXISTS anti-join (it makes the function safely re-runnable)
-- and drop the OFFSET so each iteration simply takes the next p_batch_size
-- not-yet-inserted plots.
--
-- Trigger handling is unchanged from 20260610000000_fix_orphaned_record_trigger_toggles.sql.
-- ============================================================================

-- ============================================================================
-- FUNCTION: add_plot_ids_to_records
-- ============================================================================
CREATE OR REPLACE FUNCTION public.add_plot_ids_to_records(
        p_schema_id UUID,
        p_batch_size INTEGER DEFAULT 1000
    ) RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public,
    inventory_archive AS $$
DECLARE batch_count INTEGER := 0;
root_org_id uuid;
total_processed INTEGER := 0;
BEGIN RAISE NOTICE 'Starting bulk insert/update of plot records...';
ALTER TABLE public.records DISABLE TRIGGER on_record_updated;
SELECT id INTO root_org_id
FROM public.organizations
WHERE type = 'root'
LIMIT 1;
RAISE NOTICE 'Root organization ID: %', root_org_id;
LOOP WITH eligible_plots AS (
    SELECT p.id,
        p.plot_name,
        p.cluster_name,
        p.cluster_id
    FROM (
            SELECT DISTINCT c.id
            FROM inventory_archive.plot p
                JOIN inventory_archive.cluster c ON p.cluster_id = c.id
            WHERE (
                    (
                        c.grid_density IN (64, 256)
                        AND p.federal_state IN (1, 2, 4, 8, 9, 13)
                    )
                    OR (
                        c.grid_density IN (16, 32, 64, 256)
                        AND p.federal_state IN (5, 6, 7, 10, 16)
                    )
                    OR (
                        c.grid_density IN (4, 8, 16, 32, 64, 256)
                        AND p.federal_state IN (11, 12, 14, 15)
                    )
                    OR p.sampling_stratum IN (308, 316)
                    OR c.is_training = TRUE
                )
                AND p.interval_name IN ('bwi2022', 'ci2027')
        ) cl
        JOIN inventory_archive.plot p ON cl.id = p.cluster_id
    WHERE p.interval_name IN ('bwi2022', 'ci2027') -- inkl. Testtrakte unter ci2027
        AND NOT EXISTS (
            -- Skip plots already in records; advances the candidate window on
            -- its own, so NO OFFSET is used (see migration header).
            SELECT 1
            FROM public.records r
            WHERE r.cluster_name = p.cluster_name
                AND r.plot_name = p.plot_name
        )
    ORDER BY p.id
    LIMIT p_batch_size
)
INSERT INTO public.records (
        plot_id,
        schema_id,
        plot_name,
        cluster_name,
        cluster_id,
        responsible_administration
    )
SELECT id,
    p_schema_id,
    plot_name,
    cluster_name,
    cluster_id,
    root_org_id
FROM eligible_plots;
-- NOT EXISTS above ensures no duplicates; ON CONFLICT not needed
GET DIAGNOSTICS batch_count = ROW_COUNT;
IF batch_count = 0 THEN EXIT;
END IF;
total_processed := total_processed + batch_count;
RAISE NOTICE 'Processed % records in this batch (total: %)...',
batch_count,
total_processed;
END LOOP;
ALTER TABLE public.records ENABLE TRIGGER on_record_updated;
RAISE NOTICE 'Bulk insert/update completed: % records processed',
total_processed;
RETURN total_processed;
EXCEPTION
WHEN OTHERS THEN
ALTER TABLE public.records ENABLE TRIGGER on_record_updated;
RAISE NOTICE 'Error in bulk insert/update: %',
SQLERRM;
RAISE;
END;
$$;
-- Permissions for add_plot_ids_to_records
REVOKE ALL ON FUNCTION public.add_plot_ids_to_records(UUID, INTEGER)
FROM PUBLIC;
REVOKE ALL ON FUNCTION public.add_plot_ids_to_records(UUID, INTEGER)
FROM anon;
REVOKE ALL ON FUNCTION public.add_plot_ids_to_records(UUID, INTEGER)
FROM authenticated;
GRANT EXECUTE ON FUNCTION public.add_plot_ids_to_records(UUID, INTEGER) TO postgres;
GRANT EXECUTE ON FUNCTION public.add_plot_ids_to_records(UUID, INTEGER) TO service_role;
