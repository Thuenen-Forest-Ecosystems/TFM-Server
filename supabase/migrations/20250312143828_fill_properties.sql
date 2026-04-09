-- Analogous to set_preliminary() for the properties column.
-- Fills previous_properties, previous_position_data, and cluster on
-- records where previous_properties_updated_at IS NULL (never processed).
--
-- previous_properties_updated_at = NULL  →  not yet filled  (picked up)
-- previous_properties_updated_at = <ts>  →  already filled  (skipped)
--
-- Only touches rows that have not yet received previous_properties data.
-- Records with an existing timestamp are skipped regardless of content.
--
-- Processes in batches with pg_sleep pauses to avoid I/O saturation.
--
-- Usage:
SELECT public.fill_previous_properties(9999911);
--   SELECT public.fill_previous_properties();              -- all records, default batch 200
--   SELECT public.fill_previous_properties(1234);          -- only cluster 1234
--   SELECT public.fill_previous_properties(NULL, 500);     -- all records, batch 500
--   SELECT public.fill_previous_properties(1234, 100);     -- cluster 1234, batch 100
--   SELECT public.fill_previous_properties(NULL, 200, TRUE); -- force-rewrite ALL records
--   SELECT public.fill_previous_properties(1234, 200, TRUE); -- force-rewrite cluster 1234
-- ────────────────────────────────────────────────────────────────────────────
-- Allow NULL so that unprocessed records can be distinguished from processed ones.
-- Existing NOT NULL default is dropped; new records start as NULL until filled.
ALTER TABLE public.records
ALTER COLUMN previous_properties_updated_at DROP NOT NULL,
    ALTER COLUMN previous_properties_updated_at
SET DEFAULT NULL;
-- Reset any records that have the factory default timestamp but no real data,
-- so they are picked up by this function.
UPDATE public.records
SET previous_properties_updated_at = NULL
WHERE (
        previous_properties IS NULL
        OR previous_properties = '{}'::jsonb
    )
    AND previous_properties_updated_at IS NOT NULL;
DROP FUNCTION IF EXISTS public.fill_previous_properties(INTEGER);
DROP FUNCTION IF EXISTS public.fill_previous_properties(INTEGER, INTEGER);
DROP FUNCTION IF EXISTS public.fill_previous_properties(INTEGER, INTEGER, BOOLEAN);
CREATE OR REPLACE FUNCTION public.fill_previous_properties(
        p_cluster_name INTEGER DEFAULT NULL,
        p_batch_size INTEGER DEFAULT 200,
        p_force BOOLEAN DEFAULT FALSE
    ) RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public,
    inventory_archive AS $$
DECLARE batch_count integer;
total integer := 0;
BEGIN
ALTER TABLE public.records DISABLE TRIGGER before_record_insert_or_update;
RAISE NOTICE 'set_previous_properties (cluster %, batch %, force %) ...',
COALESCE(p_cluster_name::text, 'ALL'),
p_batch_size,
p_force;
-- When forcing a rewrite, reset the timestamp on target rows to NULL first
-- so the normal IS NULL filter drives the loop (no infinite-loop risk).
IF p_force THEN
UPDATE public.records
SET previous_properties_updated_at = NULL
WHERE (
        p_cluster_name IS NULL
        OR cluster_name = p_cluster_name
    );
RAISE NOTICE '  force mode: reset previous_properties_updated_at to NULL for target rows';
END IF;
SET LOCAL work_mem = '64MB';
LOOP WITH batch AS (
    SELECT r.id,
        r.cluster_name,
        r.plot_name
    FROM public.records r
    WHERE (
            p_cluster_name IS NULL
            OR r.cluster_name = p_cluster_name
        )
        AND r.previous_properties_updated_at IS NULL
    ORDER BY r.id
    LIMIT p_batch_size
)
UPDATE public.records r
SET -- previous_properties: inline equivalent of plot_nested_json, but with the
    -- cluster_name/plot_name filter pushed into the base plot lookup so the
    -- planner can use idx_plot_cluster_name rather than scanning the whole view.
    previous_properties = COALESCE(
        (
            SELECT row_to_json(nested.*)::jsonb
            FROM (
                    SELECT p.*,
                        COALESCE(
                            (
                                SELECT row_to_json(pc)
                                FROM inventory_archive.plot_coordinates pc
                                WHERE pc.plot_id = p.id
                            ),
                            '{}'::json
                        ) AS plot_coordinates,
                        COALESCE(
                            (
                                SELECT json_agg(psp)
                                FROM inventory_archive.plot_support_points psp
                                WHERE psp.plot_id = p.id
                            ),
                            '[]'::json
                        ) AS plot_support_points,
                        COALESCE(
                            (
                                SELECT json_agg(srp)
                                FROM inventory_archive.subplots_relative_position srp
                                WHERE srp.plot_id = p.id
                            ),
                            '[]'::json
                        ) AS subplots_relative_position,
                        COALESCE(
                            (
                                SELECT json_agg(row_to_json(t.*))
                                FROM inventory_archive.tree t
                                WHERE t.plot_id = p.id
                            ),
                            '[]'::json
                        ) AS tree,
                        COALESCE(
                            (
                                SELECT json_agg(row_to_json(d.*))
                                FROM inventory_archive.deadwood d
                                WHERE d.plot_id = p.id
                            ),
                            '[]'::json
                        ) AS deadwood,
                        COALESCE(
                            (
                                SELECT json_agg(row_to_json(rg.*))
                                FROM inventory_archive.regeneration rg
                                WHERE rg.plot_id = p.id
                            ),
                            '[]'::json
                        ) AS regeneration,
                        COALESCE(
                            (
                                SELECT json_agg(row_to_json(s.*))
                                FROM inventory_archive.structure_lt4m s
                                WHERE s.plot_id = p.id
                            ),
                            '[]'::json
                        ) AS structure_lt4m,
                        COALESCE(
                            (
                                SELECT json_agg(row_to_json(e.*))
                                FROM inventory_archive.edges e
                                WHERE e.plot_id = p.id
                            ),
                            '[]'::json
                        ) AS edges,
                        COALESCE(
                            (
                                SELECT json_agg(row_to_json(gt4m.*))
                                FROM inventory_archive.structure_gt4m gt4m
                                WHERE gt4m.plot_id = p.id
                            ),
                            '[]'::json
                        ) AS structure_gt4m,
                        COALESCE(
                            (
                                SELECT row_to_json(pos)
                                FROM inventory_archive.position pos
                                WHERE pos.plot_id = p.id
                            ),
                            '{}'::json
                        ) AS position
                    FROM inventory_archive.plot p
                    WHERE p.cluster_name = b.cluster_name
                        AND p.plot_name = b.plot_name
                        AND p.interval_name IN ('bwi2022', 'ci2027')
                    ORDER BY CASE
                            p.interval_name
                            WHEN 'bwi2022' THEN 1
                            ELSE 2
                        END
                    LIMIT 1
                ) nested
        ), '{}'::jsonb
    ), -- cluster
    cluster = COALESCE(
        (
            SELECT row_to_json(c)::jsonb
            FROM inventory_archive.cluster c
            WHERE c.cluster_name = b.cluster_name
        ),
        '{}'::jsonb
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
        '{}'::jsonb
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
RAISE NOTICE 'set_previous_properties complete: % records updated',
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
REVOKE ALL ON FUNCTION public.fill_previous_properties(INTEGER, INTEGER, BOOLEAN)
FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fill_previous_properties(INTEGER, INTEGER, BOOLEAN)
FROM anon;
REVOKE ALL ON FUNCTION public.fill_previous_properties(INTEGER, INTEGER, BOOLEAN)
FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fill_previous_properties(INTEGER, INTEGER, BOOLEAN) TO postgres;
GRANT EXECUTE ON FUNCTION public.fill_previous_properties(INTEGER, INTEGER, BOOLEAN) TO service_role;
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