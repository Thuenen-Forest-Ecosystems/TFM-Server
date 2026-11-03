-- ============================================================================
-- FIX: fill_previous_properties ergaenzt fehlenden BHD aus frueheren Inventuren
-- ============================================================================
-- Tote/entnommene Baeume (tree_status 4, 5, 9, 12) haben in der bwi2022-Zeile
-- dbh = NULL. Fuer diese Baeume schreibt die Stapelfunktion jetzt den BHD der
-- letzten frueheren Messung mit Wert (gleiche Ecke, gleiche tree_number,
-- ohne ci2027) in previous_properties->'tree'.
--
-- Basis ist der Live-Body von Prod (pg_get_functiondef, Stand 2026-11-02),
-- NICHT 20260616000000: Prod nimmt nur die Baeume des gewaehlten Plots
-- (bwi2022, sonst ci2027). Das bleibt so -- Baumauswahl und Baum-ids aendern
-- sich nicht, damit die _deprecated-Markierungen in records.properties
-- (set_trees_to_deprecated, Abgleich ueber die id) weiter passen.
-- Lokal/frisch aufgesetzte DBs verlieren damit die Baum-Logik aus 20260616
-- und entsprechen danach Prod.
--
-- Der Trigger before_record_insert_or_update (fill_previous_properties()
-- RETURNS trigger) ist auf Prod deaktiviert; previous_properties wird nur
-- ueber diese Funktion geschrieben.
--
-- Aufruf nur fuer betroffene Trakte, z. B.:
--   SELECT public.fill_previous_properties(<cluster_name>, 200, true);
-- Affected functions (previous definitions):
--   public.fill_previous_properties  → Prod-Body / 20260616000000
-- ============================================================================

-- ============================================================================
-- FUNCTION: fill_previous_properties
-- ============================================================================
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
                                WHERE pc.cluster_name = p.cluster_name
                                    AND pc.plot_name = p.plot_name
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
                        -- tree: Baeume des gewaehlten Plots; bei Status 4/5/9/12
                        -- ohne BHD wird dbh aus der letzten frueheren Messung
                        -- mit Wert ergaenzt (ohne ci2027).
                        COALESCE(
                            (
                                SELECT json_agg(
                                        (
                                            CASE
                                                WHEN t.dbh IS NULL
                                                AND t.tree_status IN (4, 5, 9, 12) THEN row_to_json(t.*)::jsonb || jsonb_build_object(
                                                    'dbh',
                                                    (
                                                        SELECT t2.dbh
                                                        FROM inventory_archive.plot p2
                                                            JOIN inventory_archive.tree t2 ON t2.plot_id = p2.id
                                                        WHERE p2.cluster_name = p.cluster_name
                                                            AND p2.plot_name = p.plot_name
                                                            AND p2.interval_name <> 'ci2027'
                                                            AND t2.tree_number = t.tree_number
                                                            AND t2.dbh IS NOT NULL
                                                        ORDER BY p2.acquisition_date DESC NULLS LAST,
                                                            p2.interval_name DESC
                                                        LIMIT 1
                                                    )
                                                )
                                                ELSE row_to_json(t.*)::jsonb
                                            END
                                        )::json
                                    )
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
RAISE NOTICE 'set_previous_properties complete: % records updated',
total;
RETURN total;
EXCEPTION
WHEN OTHERS THEN
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
