-- ============================================================================
-- FIX: previous_properties->'tree' nimmt wieder Baeume frueherer Inventuren
-- (neueste Zeile je tree_number), nicht nur aus dem bwi2022-Plot
-- ============================================================================
-- records.properties->'tree' wird von fill_properties pro Ecke und tree_number
-- aus der NEUESTEN Archivzeile ueber alle Intervalle gebaut. Baeume, die 2022
-- nicht mehr erfasst wurden (z. B. 2017 ausgefallen, Status 12 -> 2022), stehen
-- dort deshalb mit ihrer ci2017- bzw. bwi2012-id.
--
-- 20260616000000 hatte previous_properties genau so angeglichen ("previous_
-- properties should match properties ... so that error checks work"), ist auf
-- Prod aber nie angekommen; 20261102100000 hat auf dem Prod-Body (nur Baeume
-- des gewaehlten Plots) aufgebaut. Folge (Prod-Snapshot 2026-11-04): 21.922
-- nicht-deprecated ci2017-Baeume in 4.884 records ohne Gegenstueck in
-- previous_properties, z. B. 18597/3 Baum 6 und 17.
--
-- Neu:
--   * Baumauswahl wie fill_properties: je tree_number die neueste Zeile ueber
--     die Intervalle der Ecke -> gleiche ids wie in properties, _deprecated-
--     Abgleich bleibt gueltig. "Neueste" = Inventurjahr aus interval_name,
--     nicht acquisition_date: 250 Archiv-Plots mit Baeumen haben kein Datum
--     (fill_properties sortiert sie per DESC NULLS FIRST als neueste ein).
--   * Vorerst nur bwi2012, ci2017, bwi2022 -- genau der Stand vom 2026-06-23
--     (bwi1987/bwi2002/ci2008 kamen erst im Oktober ins Archiv; ob sie dazu-
--     kommen, wird separat entschieden). ci2027 bleibt draussen (Ergebnisse
--     der laufenden Inventur, 20261018000000), ausser die Ecke hat nur ci2027.
--   * Jede Baumzeile bekommt acquisition_date und interval_name (wie properties).
--   * BHD-Ergaenzung aus 20261102100000 bleibt: Status 4/5/9/12 ohne dbh ->
--     dbh der letzten frueheren Messung mit Wert (ohne ci2027), ebenfalls
--     nach Inventurjahr sortiert.
-- Alles andere (Plotwahl, Kanten, Totholz, ...) unveraendert.
--
-- Neuaufbau danach: Zeitstempel selbst auf NULL setzen (p_force=true ueber alles
-- scheitert an der Waise f46dce0a-72f5-42a1-8e1c-bf258a2558f5, records_plot_id_fkey),
-- dann SELECT public.fill_previous_properties(NULL, 200, false);
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
                        -- tree: je tree_number die neueste Zeile aus bwi2012,
                        -- ci2017, bwi2022 (wie fill_properties zum Fuellzeitpunkt),
                        -- ci2027 nur bei reinen ci2027-Ecken; bei Status 4/5/9/12
                        -- ohne BHD wird dbh aus der letzten frueheren Messung
                        -- mit Wert ergaenzt (ohne ci2027).
                        COALESCE(
                            (
                                SELECT json_agg(
                                        (
                                            jsonb_build_object(
                                                'acquisition_date',
                                                x.acquisition_date,
                                                'interval_name',
                                                x.interval_name
                                            ) || CASE
                                                WHEN x.dbh IS NULL
                                                AND x.tree_status IN (4, 5, 9, 12) THEN x.tj || jsonb_build_object(
                                                    'dbh',
                                                    (
                                                        SELECT t2.dbh
                                                        FROM inventory_archive.plot p2
                                                            JOIN inventory_archive.tree t2 ON t2.plot_id = p2.id
                                                        WHERE p2.cluster_name = p.cluster_name
                                                            AND p2.plot_name = p.plot_name
                                                            AND p2.interval_name <> 'ci2027'
                                                            AND t2.tree_number = x.tree_number
                                                            AND t2.dbh IS NOT NULL
                                                        ORDER BY right(p2.interval_name, 4)::integer DESC,
                                                            p2.acquisition_date DESC NULLS LAST
                                                        LIMIT 1
                                                    )
                                                )
                                                ELSE x.tj
                                            END
                                        )::json
                                        ORDER BY x.tree_number
                                    )
                                FROM (
                                        SELECT pl.acquisition_date,
                                            pl.interval_name,
                                            t.tree_number,
                                            t.dbh,
                                            t.tree_status,
                                            row_to_json(t.*)::jsonb AS tj,
                                            row_number() OVER (
                                                PARTITION BY t.tree_number
                                                ORDER BY right(pl.interval_name, 4)::integer DESC,
                                                    pl.acquisition_date DESC NULLS LAST
                                            ) AS rn
                                        FROM inventory_archive.plot pl
                                            JOIN inventory_archive.tree t ON t.plot_id = pl.id
                                        WHERE pl.cluster_name = p.cluster_name
                                            AND pl.plot_name = p.plot_name
                                            AND (
                                                pl.interval_name IN ('bwi2012', 'ci2017', 'bwi2022')
                                                OR (
                                                    p.interval_name = 'ci2027'
                                                    AND pl.interval_name = 'ci2027'
                                                )
                                            )
                                    ) x
                                WHERE x.rn = 1
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
