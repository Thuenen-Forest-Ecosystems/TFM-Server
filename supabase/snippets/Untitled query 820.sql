-- Analogous to set_preliminary() for the properties column.
-- Fills previous_properties, previous_position_data, and cluster on
-- records where previous_properties IS NULL or '{}'::jsonb (i.e. not yet populated).
--
-- Only touches rows that have not yet received previous_properties data
-- (NULL or empty {}). Records with existing previous_properties are skipped.
--
-- Processes in batches with pg_sleep pauses to avoid I/O saturation.
--
-- Usage:
--   SELECT public.fill_previous_properties();              -- all records, default batch 200
--   SELECT public.fill_previous_properties(1234);          -- only cluster 1234
--   SELECT public.fill_previous_properties(NULL, 500);     -- all records, batch 500
--   SELECT public.fill_previous_properties(1234, 100);     -- cluster 1234, batch 100
-- ────────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.fill_previous_properties(INTEGER);
DROP FUNCTION IF EXISTS public.fill_previous_properties(INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION public.fill_previous_properties(
        p_cluster_name INTEGER DEFAULT NULL,
        p_batch_size INTEGER DEFAULT 200
    ) RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public,
    inventory_archive AS $$
DECLARE batch_count integer;
total integer := 0;
v_started_at timestamptz := clock_timestamp();
BEGIN
ALTER TABLE public.records DISABLE TRIGGER before_record_insert_or_update;
RAISE NOTICE 'set_previous_properties (cluster %, batch %) ...',
COALESCE(p_cluster_name::text, 'ALL'),
p_batch_size;
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
        AND (
            r.previous_properties IS NULL
            OR r.previous_properties = '{}'::jsonb
        )
        AND r.previous_properties_updated_at < v_started_at
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
REVOKE ALL ON FUNCTION public.fill_previous_properties(INTEGER, INTEGER)
FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fill_previous_properties(INTEGER, INTEGER)
FROM anon;
REVOKE ALL ON FUNCTION public.fill_previous_properties(INTEGER, INTEGER)
FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fill_previous_properties(INTEGER, INTEGER) TO postgres;
GRANT EXECUTE ON FUNCTION public.fill_previous_properties(INTEGER, INTEGER) TO service_role;