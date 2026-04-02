-- Analogous to fill_previous_properties() but for the properties column.
-- Fills records.properties with preliminary data from inventory_archive (bwi2022).
--
-- preliminary_set_at = NULL   →  not yet filled  (picked up)
-- preliminary_set_at = <ts>   →  already filled  (skipped)
--
-- Only touches rows where preliminary_set_at IS NULL.
-- Records with an existing timestamp are skipped unless p_force = TRUE.
--
-- Processes in batches with pg_sleep pauses to avoid I/O saturation.
--
-- Usage:
--   SELECT public.fill_properties();                        -- all records, default batch 200
--   SELECT public.fill_properties(1234);                    -- only cluster 1234
--   SELECT public.fill_properties(NULL, 500);               -- all records, batch 500
--   SELECT public.fill_properties(1234, 100);               -- cluster 1234, batch 100
--   SELECT public.fill_properties(NULL, 200, TRUE);         -- force-rewrite ALL records
--   SELECT public.fill_properties(1234, 200, TRUE);         -- force-rewrite cluster 1234
-- ────────────────────────────────────────────────────────────────────────────
-- Add tracking column so processed rows can be distinguished from unprocessed ones.
ALTER TABLE public.records
ADD COLUMN IF NOT EXISTS preliminary_set_at timestamptz NULL DEFAULT NULL;
COMMENT ON COLUMN public.records.preliminary_set_at IS 'Timestamp when fill_properties() last filled properties for this record. NULL means not yet populated. Used to skip already-processed rows and to enable force-rewrite via fill_properties(p_force := TRUE).';
-- Reset rows that have default-empty properties so they are picked up.
UPDATE public.records
SET preliminary_set_at = NULL
WHERE (
        properties IS NULL
        OR properties = '{}'::jsonb
    )
    AND preliminary_set_at IS NOT NULL;
-- ────────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.fill_properties();
DROP FUNCTION IF EXISTS public.fill_properties(INTEGER);
DROP FUNCTION IF EXISTS public.fill_properties(INTEGER, INTEGER);
DROP FUNCTION IF EXISTS public.fill_properties(INTEGER, INTEGER, BOOLEAN);
DROP FUNCTION IF EXISTS public.fill_properties(INTEGER, INTEGER, BOOLEAN, TIMESTAMPTZ);
-- Also drop old set_preliminary signatures in case they exist from a previous migration.
DROP FUNCTION IF EXISTS public.set_preliminary();
DROP FUNCTION IF EXISTS public.set_preliminary(INTEGER);
DROP FUNCTION IF EXISTS public.set_preliminary(INTEGER, INTEGER);
DROP FUNCTION IF EXISTS public.set_preliminary(INTEGER, INTEGER, BOOLEAN);
CREATE OR REPLACE FUNCTION public.fill_properties(
        p_cluster_name INTEGER DEFAULT NULL,
        p_batch_size INTEGER DEFAULT 200,
        p_force BOOLEAN DEFAULT FALSE,
        p_updated_before TIMESTAMPTZ DEFAULT NULL
    ) RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public,
    inventory_archive AS $$
DECLARE batch_count integer;
total integer := 0;
batch_num integer := 0;
BEGIN
ALTER TABLE public.records DISABLE TRIGGER before_record_insert_or_update;
ALTER TABLE public.records DISABLE TRIGGER on_record_updated;
RAISE NOTICE 'fill_properties (cluster %, batch %, force %, updated_before %) ...',
COALESCE(p_cluster_name::text, 'ALL'),
p_batch_size,
p_force,
COALESCE(p_updated_before::text, 'NULL');
-- Force mode: reset preliminary_set_at so the IS NULL filter picks rows up again.
IF p_force THEN
UPDATE public.records
SET preliminary_set_at = NULL
WHERE (
        p_cluster_name IS NULL
        OR cluster_name = p_cluster_name
    );
RAISE NOTICE '  force mode: reset preliminary_set_at to NULL for target rows';
END IF;
-- updated_before mode: reset preliminary_set_at for rows updated before the given timestamp.
IF p_updated_before IS NOT NULL THEN
UPDATE public.records
SET preliminary_set_at = NULL
WHERE (
        p_cluster_name IS NULL
        OR cluster_name = p_cluster_name
    )
    AND (
        completed_at_troop IS NULL
        OR completed_at_troop < p_updated_before
    );
RAISE NOTICE '  updated_before mode: reset preliminary_set_at for rows updated before %',
p_updated_before;
END IF;
SET LOCAL work_mem = '64MB';
LOOP batch_num := batch_num + 1;
RAISE NOTICE '  batch % (total so far: %) ...',
batch_num,
total;
WITH batch AS (
    SELECT r.id,
        r.cluster_name,
        r.plot_name
    FROM public.records r
    WHERE (
            p_cluster_name IS NULL
            OR r.cluster_name = p_cluster_name
        )
        AND r.preliminary_set_at IS NULL
    ORDER BY r.id
    LIMIT p_batch_size
)
UPDATE public.records r
SET properties = CASE
        -- Only fill when a bwi2022 plot exists; leave properties untouched otherwise.
        WHEN p.id IS NOT NULL THEN (
            to_jsonb(p) - 'id' - 'intkey' - 'cluster_id' - 'trees_less_4meter_coverage' - 'trees_less_4meter_layer' - 'stand_structure' - 'stand_age' - 'stand_development_phase' - 'stand_layer_regeneration' - 'fence_regeneration' - 'trees_greater_4meter_mirrored' - 'trees_greater_4meter_basal_area_factor' - 'harvest_method' - 'harvest_reason'
        ) || jsonb_build_object(
            'fence_regeneration',
            NULL,
            'tree',
            COALESCE(
                (
                    SELECT jsonb_agg(
                            jsonb_build_object(
                                'acquisition_date',
                                x.acquisition_date,
                                'interval_name',
                                x.interval_name
                            ) || jsonb_set(
                                jsonb_set(
                                    jsonb_set(
                                        jsonb_set(
                                            jsonb_set(
                                                to_jsonb(x.t) - 'plot_id',
                                                '{dbh}',
                                                'null'::jsonb
                                            ),
                                            '{tree_height}',
                                            'null'::jsonb
                                        ),
                                        '{tree_age}',
                                        CASE
                                            WHEN (to_jsonb(x.t)->'tree_age') IS NOT NULL
                                            AND (to_jsonb(x.t)->'tree_age') != 'null'::jsonb THEN to_jsonb(((to_jsonb(x.t)->>'tree_age')::smallint + 5))
                                            ELSE 'null'::jsonb
                                        END
                                    ),
                                    '{tree_status}',
                                    CASE
                                        WHEN (to_jsonb(x.t)->>'tree_status')::integer IN (11, 12) THEN '2022'::jsonb
                                        ELSE to_jsonb(x.t)->'tree_status'
                                    END
                                ),
                                '{deadwood_used}',
                                'null'::jsonb
                            )
                        )
                    FROM (
                            SELECT pl.acquisition_date,
                                pl.interval_name,
                                t,
                                row_number() OVER (
                                    PARTITION BY pl.cluster_name,
                                    pl.plot_name,
                                    t.tree_number
                                    ORDER BY pl.acquisition_date DESC
                                ) AS rn
                            FROM inventory_archive.plot pl
                                JOIN inventory_archive.tree t ON pl.id = t.plot_id
                            WHERE pl.cluster_name = b.cluster_name
                                AND pl.plot_name = b.plot_name
                        ) x
                    WHERE x.rn = 1
                ),
                '[]'::jsonb
            ),
            'edges',
            COALESCE(
                (
                    SELECT jsonb_agg(
                            jsonb_build_object(
                                'acquisition_date',
                                x.acquisition_date,
                                'interval_name',
                                x.interval_name
                            ) || (to_jsonb(x.e) - 'plot_id')
                        )
                    FROM (
                            SELECT pl.acquisition_date,
                                pl.interval_name,
                                e,
                                row_number() OVER (
                                    PARTITION BY pl.cluster_name,
                                    pl.plot_name,
                                    e.edge_number
                                    ORDER BY pl.acquisition_date DESC
                                ) AS rn
                            FROM inventory_archive.plot pl
                                JOIN inventory_archive.edges e ON pl.id = e.plot_id
                            WHERE pl.cluster_name = b.cluster_name
                                AND pl.plot_name = b.plot_name
                        ) x
                    WHERE x.rn = 1
                ),
                '[]'::jsonb
            )
        ) -- No bwi2022 plot (ci2027-only cluster): leave properties as-is but still
        -- stamp preliminary_set_at so the row is not re-selected in the next batch.
        ELSE r.properties
    END,
    preliminary_set_at = NOW()
FROM batch b
    LEFT JOIN LATERAL (
        SELECT *
        FROM inventory_archive.plot
        WHERE cluster_name = b.cluster_name
            AND plot_name = b.plot_name
            AND interval_name IN ('bwi2022', 'ci2027')
        ORDER BY CASE
                interval_name
                WHEN 'bwi2022' THEN 1
                ELSE 2
            END
        LIMIT 1
    ) p ON TRUE
WHERE r.id = b.id;
GET DIAGNOSTICS batch_count = ROW_COUNT;
EXIT
WHEN batch_count = 0;
total := total + batch_count;
RAISE NOTICE '  batch % done: % records in batch, % total',
batch_num,
batch_count,
total;
PERFORM pg_sleep(0.15);
END LOOP;
ALTER TABLE public.records ENABLE TRIGGER before_record_insert_or_update;
ALTER TABLE public.records ENABLE TRIGGER on_record_updated;
RAISE NOTICE 'fill_properties complete: % records updated',
total;
RETURN total;
EXCEPTION
WHEN OTHERS THEN BEGIN
ALTER TABLE public.records ENABLE TRIGGER before_record_insert_or_update;
ALTER TABLE public.records ENABLE TRIGGER on_record_updated;
EXCEPTION
WHEN OTHERS THEN
/* already enabled */
END;
RAISE;
END;
$$;
-- Permissions
REVOKE ALL ON FUNCTION public.fill_properties(INTEGER, INTEGER, BOOLEAN, TIMESTAMPTZ)
FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fill_properties(INTEGER, INTEGER, BOOLEAN, TIMESTAMPTZ)
FROM anon;
REVOKE ALL ON FUNCTION public.fill_properties(INTEGER, INTEGER, BOOLEAN, TIMESTAMPTZ)
FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fill_properties(INTEGER, INTEGER, BOOLEAN, TIMESTAMPTZ) TO postgres;
GRANT EXECUTE ON FUNCTION public.fill_properties(INTEGER, INTEGER, BOOLEAN, TIMESTAMPTZ) TO service_role;