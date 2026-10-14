-- ============================================================================
-- MIGRATION: plot_coordinates je Traktecke statt je Plot x Inventur
-- ============================================================================
-- Die Soll-Koordinate einer Traktecke stammt aus bwi.koord.b0_ecke_soll
-- (Tnr + Enr, ohne Inventurbezug). Bisher hing sie ueber plot_id UNIQUE an
-- genau einer plot-Zeile; die Migration schrieb deshalb fuer jede Inventur
-- eine identische Kopie (lokal 833.080 Zeilen fuer 261.708 Ecken, 0 Abweichungen).
--
-- Neu: eine Zeile pro Ecke, Schluessel (cluster_name, plot_name).
--
-- WARUM DER SCHLUESSEL IN plot_coordinates UND NICHT plot.plot_coordinates_id
-- plot ist oeffentlich (supabase/seeds/public, Open Data), plot_coordinates
-- intern (supabase/seeds/intern). Die interne Tabelle verweist auf die
-- oeffentliche, nie umgekehrt -- ein Public-Seed kommt ohne die internen
-- Koordinaten aus. plot bleibt unveraendert.
--
-- POSTGREST
-- Ohne FK zu plot erkennt PostgREST die Beziehung nicht von selbst. Die beiden
-- Funktionen am Ende sind "computed relationships": plot?select=*,plot_coordinates(*)
-- funktioniert damit wie bisher (ROWS 1 -> ein Objekt, kein Array).
--
-- FOLGE FUER DIE JSON-FORM
-- previous_properties.plot_coordinates bzw. plot_nested_json.plot_coordinates
-- verlieren den Schluessel plot_id und tragen cluster_name/plot_name. Die
-- TFM-app liest dort nur center_location. plot_nested_json_cached nach dem
-- Deploy mit public.refresh_plot_nested_json_cached() neu aufbauen.
-- ============================================================================

-- ============================================================================
-- 1. Eckenschluessel anlegen und befuellen
-- ============================================================================
ALTER TABLE inventory_archive.plot_coordinates
    ADD COLUMN cluster_name integer,
    ADD COLUMN plot_name integer;

UPDATE inventory_archive.plot_coordinates pc
SET cluster_name = p.cluster_name,
    plot_name = p.plot_name
FROM inventory_archive.plot p
WHERE p.id = pc.plot_id;

-- ============================================================================
-- 2. Guard: Kopien einer Ecke muessen identisch sein
-- ============================================================================
-- Sonst wuerde Schritt 5 still einen Wert verwerfen. Lieber abbrechen und von
-- Hand entscheiden.
DO $$
DECLARE
    n_diff integer;
    sample text;
BEGIN
    SELECT count(*), string_agg(cluster_name || '/' || plot_name, ', ')
    INTO n_diff, sample
    FROM (
        SELECT cluster_name, plot_name
        FROM inventory_archive.plot_coordinates
        GROUP BY cluster_name, plot_name
        HAVING count(DISTINCT (
                   COALESCE(extensions.ST_AsEWKT(center_location), 'NULL'),
                   cartesian_x,
                   cartesian_y
               )) > 1
        LIMIT 20
    ) d;
    IF n_diff > 0 THEN
        RAISE EXCEPTION 'plot_coordinates: % Ecke(n) mit abweichenden Kopien, z. B. %', n_diff, sample;
    END IF;
END $$;

-- ============================================================================
-- 3. Ueberlebende Zeile je Ecke
-- ============================================================================
-- Bevorzugt die bwi2022-Kopie (die bisher alle Leser verwendet haben), sonst
-- die juengste Aufnahme.
CREATE TEMP TABLE pc_keep ON COMMIT DROP AS
SELECT pc.id AS old_id,
    first_value(pc.id) OVER (
        PARTITION BY pc.cluster_name, pc.plot_name
        ORDER BY (p.interval_name = 'bwi2022') DESC,
            p.acquisition_date DESC NULLS LAST,
            pc.id
    ) AS keep_id
FROM inventory_archive.plot_coordinates pc
    JOIN inventory_archive.plot p ON p.id = pc.plot_id;

CREATE INDEX ON pc_keep (old_id);

-- ============================================================================
-- 4. subplots_relative_position auf die Eckzeile umhaengen
-- ============================================================================
UPDATE inventory_archive.subplots_relative_position srp
SET plot_coordinates_id = k.keep_id
FROM pc_keep k
WHERE srp.plot_coordinates_id = k.old_id
    AND k.old_id <> k.keep_id;

-- ============================================================================
-- 5. Abhaengige Objekte auf den Eckenschluessel umstellen
-- ============================================================================
-- Muss vor dem DROP COLUMN plot_id passieren. Bodies stammen aus der Live-DB
-- (pg_get_viewdef / pg_get_functiondef), geaendert ist jeweils nur der Join.
--
-- ACHTUNG: CREATE OR REPLACE VIEW ohne WITH-Klausel setzt die Reloptions
-- zurueck, also auch security_invoker (geprueft auf PG 15). Ohne diese Option
-- liefe z. B. view_records_details mit den Rechten des Eigentuemers an der RLS
-- von records vorbei. Die Optionen werden deshalb hier gesichert und nach 5c
-- wieder gesetzt.
CREATE TEMP TABLE view_reloptions ON COMMIT DROP AS
SELECT c.oid::regclass AS view_name, c.reloptions
FROM pg_class c
WHERE c.oid IN (
        to_regclass('public.view_records_details'),
        to_regclass('public.plot_nested_json'),
        to_regclass('public.v_stats_workflow_plot_map'),
        to_regclass('public.v_stats_workflow_plot_map2')
    );

-- 5a. view_records_details (Body aus 20261007000000, CREATE OR REPLACE, kein
--     DROP -- siehe 20260820000000)
CREATE OR REPLACE VIEW public.view_records_details AS
SELECT r.*,
    p_coordinates.center_location,
    p_bwi.federal_state,
    p_bwi.growth_district,
    p_bwi.forest_status AS forest_status_bwi2022,
    p_bwi.accessibility,
    p_bwi.forest_office,
    p_bwi.ffh_forest_type_field,
    p_bwi.property_type,
    p_ci2017.forest_status AS forest_status_ci2017,
    p_ci2012.forest_status AS forest_status_ci2012,
    c.cluster_status,
    c.cluster_situation,
    c.state_responsible,
    c.states_affected,
    c.is_training AS cluster_is_training,
    c.grid_density,
    public.record_workflow_code(
        rec                        => r,
        is_control_troop           => COALESCE(t.is_control_troop, false),
        repeated_survey            => COALESCE(h.repeated_survey, false),
        seen_control_troop         => COALESCE(h.seen_control_troop, false),
        returned_by_administration => COALESCE(h.returned_by_administration, false)
    ) AS workflow_code,
    CASE WHEN r.properties ->> 'forest_status' ~ '^-?[0-9]{1,4}$'
         THEN (r.properties ->> 'forest_status')::smallint
    END AS forest_status_ci2027,
    CASE WHEN r.properties ->> 'accessibility' ~ '^-?[0-9]{1,4}$'
         THEN (r.properties ->> 'accessibility')::smallint
    END AS accessibility_ci2027,
    CASE WHEN cur.survey_troop_done THEN r.responsible_troop
         ELSE h.last_survey_troop
    END AS last_survey_troop,
    CASE WHEN cur.survey_troop_done THEN r.completed_at_troop
         ELSE h.completed_at_survey_troop
    END AS completed_at_survey_troop,
    CASE WHEN cur.control_troop_done THEN r.responsible_troop
         ELSE h.last_control_troop
    END AS last_control_troop,
    CASE WHEN cur.control_troop_done THEN r.completed_at_troop
         ELSE h.completed_at_control_troop
    END AS completed_at_control_troop,
    -- Beginn der GNSS-Messung am Plotzentrum, Geraete-Ortszeit.
    CASE WHEN r.properties -> 'position' ->> 'start_measurement'
              ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}'
         THEN public.try_parse_timestamp(r.properties -> 'position' ->> 'start_measurement')
    END AS gnss_measured_at
FROM public.records r
    LEFT JOIN inventory_archive.plot p_bwi ON r.plot_name = p_bwi.plot_name
    AND r.cluster_name = p_bwi.cluster_name
    AND p_bwi.interval_name = 'bwi2022'
    LEFT JOIN inventory_archive.plot_coordinates p_coordinates ON p_coordinates.cluster_name = p_bwi.cluster_name
    AND p_coordinates.plot_name = p_bwi.plot_name
    LEFT JOIN inventory_archive.plot p_ci2017 ON p_bwi.plot_name = p_ci2017.plot_name
    AND p_bwi.cluster_name = p_ci2017.cluster_name
    AND p_ci2017.interval_name = 'ci2017'
    LEFT JOIN inventory_archive.plot p_ci2012 ON p_bwi.plot_name = p_ci2012.plot_name
    AND p_bwi.cluster_name = p_ci2012.cluster_name
    AND p_ci2012.interval_name = 'bwi2012'
    LEFT JOIN inventory_archive.cluster c ON r.cluster_name = c.cluster_name
    LEFT JOIN public.troop t ON t.id = r.responsible_troop
    LEFT JOIN public.view_record_workflow_history h ON h.record_id = r.id
    -- t.id IS NOT NULL: nach Entzug der Verantwortlichkeit bleibt
    -- completed_at_troop stehen, responsible_troop ist aber NULL -- dann muss
    -- die Historie greifen (entspricht dem COALESCE aus 20260929000000).
    CROSS JOIN LATERAL (
        SELECT
            r.completed_at_troop IS NOT NULL AND t.id IS NOT NULL
                AND NOT t.is_control_troop
                AND NOT t.is_read_only AS survey_troop_done,
            r.completed_at_troop IS NOT NULL AND t.id IS NOT NULL
                AND t.is_control_troop AS control_troop_done
    ) cur;

-- 5b. plot_nested_json (Basis der Matview plot_nested_json_cached)
CREATE OR REPLACE VIEW public.plot_nested_json AS
 WITH base_plots AS (
         SELECT plot.intkey,
            plot.id,
            plot.interval_name,
            plot.sampling_stratum,
            plot.federal_state,
            plot.growth_district,
            plot.forest_status,
            plot.accessibility,
            plot.forest_office,
            plot.elevation_level,
            plot.property_type,
            plot.property_size_class,
            plot.forest_community,
            plot.forest_community_field,
            plot.ffh_forest_type,
            plot.ffh_forest_type_field,
            plot.land_use,
            plot.coast,
            plot.sandy,
            plot.protected_landscape,
            plot.long_time_forest,
            plot.harvest_restriction,
            plot.marker_status,
            plot.marker_profile,
            plot.terrain_form,
            plot.terrain_slope,
            plot.terrain_exposure,
            plot.management_type,
            plot.harvest_condition,
            plot.biotope,
            plot.stand_structure,
            plot.stand_age,
            plot.stand_development_phase,
            plot.stand_layer_regeneration,
            plot.fence_regeneration,
            plot.trees_greater_4meter_mirrored,
            plot.trees_greater_4meter_basal_area_factor,
            plot.trees_less_4meter_coverage,
            plot.trees_less_4meter_layer,
            plot.biogeographische_region,
            plot.biosphaere,
            plot.ffh,
            plot.national_park,
            plot.natur_park,
            plot.vogel_schutzgebiet,
            plot.natur_schutzgebiet,
            plot.harvest_restriction_nature_reserve,
            plot.harvest_restriction_protection_forest,
            plot.harvest_restriction_recreational_forest,
            plot.harvest_restriction_scattered,
            plot.harvest_restriction_fragmented,
            plot.harvest_restriction_insufficient_access,
            plot.harvest_restriction_wetness,
            plot.harvest_restriction_low_yield,
            plot.harvest_restriction_private_conservation,
            plot.harvest_restriction_other_internalcause,
            plot.harvest_method,
            plot.harvest_reason,
            plot.municipality,
            plot.plot_name,
            plot.cluster_name,
            plot.cluster_id,
            plot.acquisition_date
           FROM inventory_archive.plot
          WHERE (plot.interval_name = 'bwi2022'::text)
        ), nested_data AS (
         SELECT p.intkey,
            p.id,
            p.interval_name,
            p.sampling_stratum,
            p.federal_state,
            p.growth_district,
            p.forest_status,
            p.accessibility,
            p.forest_office,
            p.elevation_level,
            p.property_type,
            p.property_size_class,
            p.forest_community,
            p.forest_community_field,
            p.ffh_forest_type,
            p.ffh_forest_type_field,
            p.land_use,
            p.coast,
            p.sandy,
            p.protected_landscape,
            p.long_time_forest,
            p.harvest_restriction,
            p.marker_status,
            p.marker_profile,
            p.terrain_form,
            p.terrain_slope,
            p.terrain_exposure,
            p.management_type,
            p.harvest_condition,
            p.biotope,
            p.stand_structure,
            p.stand_age,
            p.stand_development_phase,
            p.stand_layer_regeneration,
            p.fence_regeneration,
            p.trees_greater_4meter_mirrored,
            p.trees_greater_4meter_basal_area_factor,
            p.trees_less_4meter_coverage,
            p.trees_less_4meter_layer,
            p.biogeographische_region,
            p.biosphaere,
            p.ffh,
            p.national_park,
            p.natur_park,
            p.vogel_schutzgebiet,
            p.natur_schutzgebiet,
            p.harvest_restriction_nature_reserve,
            p.harvest_restriction_protection_forest,
            p.harvest_restriction_recreational_forest,
            p.harvest_restriction_scattered,
            p.harvest_restriction_fragmented,
            p.harvest_restriction_insufficient_access,
            p.harvest_restriction_wetness,
            p.harvest_restriction_low_yield,
            p.harvest_restriction_private_conservation,
            p.harvest_restriction_other_internalcause,
            p.harvest_method,
            p.harvest_reason,
            p.municipality,
            p.plot_name,
            p.cluster_name,
            p.cluster_id,
            p.acquisition_date,
            COALESCE(( SELECT row_to_json(pc.*) AS row_to_json
                   FROM inventory_archive.plot_coordinates pc
                  WHERE ((pc.cluster_name = p.cluster_name) AND (pc.plot_name = p.plot_name))), '{}'::json) AS plot_coordinates,
            COALESCE(( SELECT json_agg(psp.*) AS json_agg
                   FROM inventory_archive.plot_support_points psp
                  WHERE (psp.plot_id = p.id)), '[]'::json) AS plot_support_points,
            COALESCE(( SELECT json_agg(srp.*) AS json_agg
                   FROM inventory_archive.subplots_relative_position srp
                  WHERE (srp.plot_id = p.id)), '[]'::json) AS subplots_relative_position,
            COALESCE(( SELECT json_agg(row_to_json(t.*)) AS json_agg
                   FROM inventory_archive.tree t
                  WHERE (t.plot_id = p.id)), '[]'::json) AS tree,
            COALESCE(( SELECT json_agg(row_to_json(d.*)) AS json_agg
                   FROM inventory_archive.deadwood d
                  WHERE (d.plot_id = p.id)), '[]'::json) AS deadwood,
            COALESCE(( SELECT json_agg(row_to_json(r.*)) AS json_agg
                   FROM inventory_archive.regeneration r
                  WHERE (r.plot_id = p.id)), '[]'::json) AS regeneration,
            COALESCE(( SELECT json_agg(row_to_json(s.*)) AS json_agg
                   FROM inventory_archive.structure_lt4m s
                  WHERE (s.plot_id = p.id)), '[]'::json) AS structure_lt4m,
            COALESCE(( SELECT json_agg(row_to_json(e.*)) AS json_agg
                   FROM inventory_archive.edges e
                  WHERE (e.plot_id = p.id)), '[]'::json) AS edges,
            COALESCE(( SELECT json_agg(row_to_json(gt4m.*)) AS json_agg
                   FROM inventory_archive.structure_gt4m gt4m
                  WHERE (gt4m.plot_id = p.id)), '[]'::json) AS structure_gt4m,
            COALESCE(( SELECT row_to_json(pos.*) AS row_to_json
                   FROM inventory_archive."position" pos
                  WHERE (pos.plot_id = p.id)), '{}'::json) AS "position"
           FROM base_plots p
        )
 SELECT nested_data.intkey,
    nested_data.id,
    nested_data.interval_name,
    nested_data.sampling_stratum,
    nested_data.federal_state,
    nested_data.growth_district,
    nested_data.forest_status,
    nested_data.accessibility,
    nested_data.forest_office,
    nested_data.elevation_level,
    nested_data.property_type,
    nested_data.property_size_class,
    nested_data.forest_community,
    nested_data.forest_community_field,
    nested_data.ffh_forest_type,
    nested_data.ffh_forest_type_field,
    nested_data.land_use,
    nested_data.coast,
    nested_data.sandy,
    nested_data.protected_landscape,
    nested_data.long_time_forest,
    nested_data.harvest_restriction,
    nested_data.marker_status,
    nested_data.marker_profile,
    nested_data.terrain_form,
    nested_data.terrain_slope,
    nested_data.terrain_exposure,
    nested_data.management_type,
    nested_data.harvest_condition,
    nested_data.biotope,
    nested_data.stand_structure,
    nested_data.stand_age,
    nested_data.stand_development_phase,
    nested_data.stand_layer_regeneration,
    nested_data.fence_regeneration,
    nested_data.trees_greater_4meter_mirrored,
    nested_data.trees_greater_4meter_basal_area_factor,
    nested_data.trees_less_4meter_coverage,
    nested_data.trees_less_4meter_layer,
    nested_data.biogeographische_region,
    nested_data.biosphaere,
    nested_data.ffh,
    nested_data.national_park,
    nested_data.natur_park,
    nested_data.vogel_schutzgebiet,
    nested_data.natur_schutzgebiet,
    nested_data.harvest_restriction_nature_reserve,
    nested_data.harvest_restriction_protection_forest,
    nested_data.harvest_restriction_recreational_forest,
    nested_data.harvest_restriction_scattered,
    nested_data.harvest_restriction_fragmented,
    nested_data.harvest_restriction_insufficient_access,
    nested_data.harvest_restriction_wetness,
    nested_data.harvest_restriction_low_yield,
    nested_data.harvest_restriction_private_conservation,
    nested_data.harvest_restriction_other_internalcause,
    nested_data.harvest_method,
    nested_data.harvest_reason,
    nested_data.municipality,
    nested_data.plot_name,
    nested_data.cluster_name,
    nested_data.cluster_id,
    nested_data.acquisition_date,
    nested_data.plot_coordinates,
    nested_data.plot_support_points,
    nested_data.subplots_relative_position,
    nested_data.tree,
    nested_data.deadwood,
    nested_data.regeneration,
    nested_data.structure_lt4m,
    nested_data.edges,
    nested_data.structure_gt4m,
    nested_data."position"
   FROM nested_data;

-- 5c. Objekte, deren Body je Umgebung abweicht oder die nicht im Repo stehen:
--     Der Live-Body wird gelesen und nur der Join ersetzt, sonst nichts.
--
--   * public.fill_previous_properties(integer, integer, boolean) (Stapelvariante;
--     die Trigger-Variante liest die Matview): auf Prod laeuft am 2026-10-14 eine
--     aeltere Fassung als in 20260616000000. Ein fester Body hier wuerde diese
--     Abweichung nebenbei in die eine oder andere Richtung "reparieren".
--   * public.v_stats_workflow_plot_map, public.v_stats_workflow_plot_map2:
--     existieren nur in der Produktions-DB (nicht versioniert); fehlen sie,
--     wird der Schritt uebersprungen.
--
--   Jede Ersetzung muss genau einmal greifen, sonst bricht die Migration ab.
DO $$
DECLARE
    obj record;
    def text;
    new_def text;
    n_hits integer;
BEGIN
    FOR obj IN
        SELECT * FROM (VALUES
            ('function', 'public.fill_previous_properties(integer, integer, boolean)',
                'WHERE pc.plot_id = p.id',
                E'WHERE pc.cluster_name = p.cluster_name\n                                    AND pc.plot_name = p.plot_name'),
            ('view', 'public.v_stats_workflow_plot_map',
                'JOIN inventory_archive.plot_coordinates c ON ((p.id = c.plot_id))',
                'JOIN inventory_archive.plot_coordinates c ON (((c.cluster_name = p.cluster_name) AND (c.plot_name = p.plot_name)))'),
            ('view', 'public.v_stats_workflow_plot_map2',
                'JOIN inventory_archive.plot_coordinates c ON ((p.id = c.plot_id))',
                'JOIN inventory_archive.plot_coordinates c ON (((c.cluster_name = p.cluster_name) AND (c.plot_name = p.plot_name)))')
        ) AS t(kind, name, old_text, new_text)
    LOOP
        IF obj.kind = 'function' THEN
            IF to_regprocedure(obj.name) IS NULL THEN
                RAISE NOTICE '% fehlt, uebersprungen', obj.name;
                CONTINUE;
            END IF;
            def := pg_get_functiondef(to_regprocedure(obj.name));
        ELSE
            IF to_regclass(obj.name) IS NULL THEN
                RAISE NOTICE '% fehlt, uebersprungen', obj.name;
                CONTINUE;
            END IF;
            def := pg_get_viewdef(to_regclass(obj.name));
        END IF;

        n_hits := (length(def) - length(replace(def, obj.old_text, ''))) / length(obj.old_text);
        IF n_hits <> 1 THEN
            RAISE EXCEPTION '%: Join "%" % mal gefunden statt genau einmal', obj.name, obj.old_text, n_hits;
        END IF;
        new_def := replace(def, obj.old_text, obj.new_text);

        IF obj.kind = 'function' THEN
            EXECUTE new_def;
        ELSE
            -- CREATE OR REPLACE behaelt Eigentuemer, Rechte und security_invoker
            EXECUTE format('CREATE OR REPLACE VIEW %s AS %s', obj.name, new_def);
        END IF;
        RAISE NOTICE '% auf den Eckenschluessel umgestellt', obj.name;
    END LOOP;
END $$;

-- 5c'. Reloptions (security_invoker) der ersetzten Views wiederherstellen
DO $$
DECLARE
    v record;
BEGIN
    FOR v IN SELECT * FROM view_reloptions WHERE reloptions IS NOT NULL LOOP
        EXECUTE format('ALTER VIEW %s SET (%s)', v.view_name, array_to_string(v.reloptions, ', '));
    END LOOP;
    -- Gegenprobe: keine der Views darf ihre Optionen verloren haben
    IF EXISTS (
        SELECT 1 FROM view_reloptions o JOIN pg_class c ON c.oid = o.view_name
        WHERE c.reloptions IS DISTINCT FROM o.reloptions
    ) THEN
        RAISE EXCEPTION 'Reloptions der umgestellten Views nicht wiederhergestellt';
    END IF;
END $$;

-- 5d. update_tree_location: Startpunkt ueber plot -> Ecke
CREATE OR REPLACE FUNCTION inventory_archive.update_tree_location()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'extensions', 'public', 'inventory_archive'
AS $function$
DECLARE start_point extensions.geometry;
azimuth_rad float8;
new_center_point extensions.geometry;
distance_m float8;
BEGIN RAISE NOTICE 'plot_id: %',
NEW."plot_id";
SELECT pc.center_location::extensions.geometry INTO start_point
FROM inventory_archive.plot p
    JOIN inventory_archive.plot_coordinates pc ON pc.cluster_name = p.cluster_name
    AND pc.plot_name = p.plot_name
WHERE p.id = NEW."plot_id";
IF start_point IS NULL THEN RAISE NOTICE 'No start point found for plot_id: %',
NEW."plot_id";
RETURN NEW;
END IF;
-- Calculate in WGS84
azimuth_rad := radians_from_gon(CAST(NEW.azimuth AS float8));
distance_m := NEW.distance / 100.0;
-- Convert cm to m
-- Use ST_Project which handles geodetic calculations -- ST_Project requires geography
new_center_point := ST_Project(
    start_point::extensions.geography,
    distance_m,
    azimuth_rad
)::extensions.geometry;
INSERT INTO inventory_archive.tree_coordinates (tree_id, tree_location)
VALUES (NEW.id, new_center_point) ON CONFLICT (tree_id) DO
UPDATE
SET tree_location = EXCLUDED.tree_location;
RETURN NEW;
END;
$function$;

-- 5e. Freigabesperre (vgl. 20260904000100): eine Ecke ist sichtbar, sobald
--     einer ihrer Plots nicht gesperrt ist.
DROP POLICY IF EXISTS release_gate ON inventory_archive.plot_coordinates;
CREATE POLICY release_gate ON inventory_archive.plot_coordinates
AS RESTRICTIVE FOR SELECT TO anon, authenticated
USING (
    EXISTS (
        SELECT 1
        FROM inventory_archive.plot p
        WHERE p.cluster_name = plot_coordinates.cluster_name
            AND p.plot_name = plot_coordinates.plot_name
            AND p.id NOT IN (SELECT e.plot_id FROM inventory_archive.embargoed_plots() e)
    )
);

-- ============================================================================
-- 6. Doppelte Kopien loeschen
-- ============================================================================
DELETE FROM inventory_archive.plot_coordinates pc
USING pc_keep k
WHERE pc.id = k.old_id
    AND k.old_id <> k.keep_id;

-- ============================================================================
-- 7. Constraints umbauen
-- ============================================================================
ALTER TABLE inventory_archive.plot_coordinates
    DROP CONSTRAINT fk_plotposition_plot,
    DROP CONSTRAINT plot_coordinates_plot_id_key;
DROP INDEX IF EXISTS inventory_archive.idx_plot_coordinates_plot_id;
ALTER TABLE inventory_archive.plot_coordinates DROP COLUMN plot_id;

ALTER TABLE inventory_archive.plot_coordinates
    ALTER COLUMN cluster_name SET NOT NULL,
    ALTER COLUMN plot_name SET NOT NULL,
    ADD CONSTRAINT plot_coordinates_plot_name_check CHECK (plot_name BETWEEN 1 AND 4),
    ADD CONSTRAINT plot_coordinates_corner_key UNIQUE (cluster_name, plot_name),
    -- Loeschen eines Trakts (delete_cluster) nimmt seine Ecken mit.
    ADD CONSTRAINT plot_coordinates_cluster_name_fkey FOREIGN KEY (cluster_name)
        REFERENCES inventory_archive.cluster (cluster_name) ON DELETE CASCADE;

-- War bisher ohne Constraint; nach dem Umhaengen in Schritt 4 vollstaendig.
ALTER TABLE inventory_archive.subplots_relative_position
    ADD CONSTRAINT subplots_relative_position_plot_coordinates_id_fkey
        FOREIGN KEY (plot_coordinates_id)
        REFERENCES inventory_archive.plot_coordinates (id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_subplots_relative_position_plot_coordinates_id
    ON inventory_archive.subplots_relative_position (plot_coordinates_id);

COMMENT ON TABLE inventory_archive.plot_coordinates IS
    'Traktecken/Plot-Koordinaten: Soll-Koordinate je Traktecke (cluster_name, plot_name), inventuruebergreifend. Gemessene Positionen je Inventur stehen in inventory_archive.position.';
COMMENT ON COLUMN inventory_archive.plot_coordinates.cluster_name IS 'Traktnummer (Tnr)';
COMMENT ON COLUMN inventory_archive.plot_coordinates.plot_name IS 'Eckennummer (Enr, 1-4)';

-- ============================================================================
-- 8. add_cluster_with_plots: Ecke wiederverwenden
-- ============================================================================
-- Bisher wurde nur die eigene Kopie der Inventur geaendert. Entsprechend wird
-- eine vorhandene Ecke nur ueberschrieben, wenn kein Plot einer anderen
-- Inventur an ihr haengt; sonst bleibt sie, und die gespeicherten Werte werden
-- zurueckgegeben.
CREATE OR REPLACE FUNCTION inventory_archive.add_cluster_with_plots(p_cluster_name integer, p_federal_state integer, p_longitude double precision, p_latitude double precision, p_state_responsible integer DEFAULT NULL::integer, p_topo_map_sheet integer DEFAULT NULL::integer, p_states_affected integer[] DEFAULT NULL::integer[], p_grid_density integer DEFAULT NULL::integer, p_cluster_status integer DEFAULT NULL::integer, p_cluster_situation integer DEFAULT NULL::integer, p_inspire_grid_cell text DEFAULT NULL::text, p_is_training boolean DEFAULT true, p_interval_name text DEFAULT 'ci2027'::text, p_acquisition_date date DEFAULT NULL::date, p_side_m double precision DEFAULT 150.0)
 RETURNS TABLE(out_cluster_id uuid, out_plot_id uuid, out_plot_name integer, out_plot_coordinates_id uuid, out_cartesian_x double precision, out_cartesian_y double precision, out_longitude double precision, out_latitude double precision)
 LANGUAGE plpgsql
 SET search_path TO 'inventory_archive', 'extensions', 'public'
AS $function$
DECLARE v_cluster_id UUID;
v_plot_id UUID;
v_coord_id UUID;
-- DHDN (EPSG:31466, 31467, 31468, 31469, depending on longitude) representation of the SW corner
v_sw_dhdn extensions.GEOMETRY;
v_sw_x FLOAT;
-- Easting  DHDN
v_sw_y FLOAT;
-- Northing DHDN
-- per-corner variables
v_corner RECORD;
v_pt_dhdn extensions.GEOMETRY;
v_pt_4326 extensions.GEOMETRY;
v_cx FLOAT;
v_cy FLOAT;
BEGIN -- ----------------------------------------------------------------
-- 1. Upsert cluster
-- ----------------------------------------------------------------
INSERT INTO inventory_archive.cluster (
        cluster_name,
        state_responsible,
        topo_map_sheet,
        states_affected,
        grid_density,
        cluster_status,
        cluster_situation,
        inspire_grid_cell,
        is_training
    )
VALUES (
        p_cluster_name,
        p_state_responsible,
        p_topo_map_sheet,
        p_states_affected,
        p_grid_density,
        p_cluster_status,
        p_cluster_situation,
        p_inspire_grid_cell,
        p_is_training
    ) ON CONFLICT (cluster_name) DO
UPDATE
SET state_responsible = COALESCE(
        EXCLUDED.state_responsible,
        inventory_archive.cluster.state_responsible
    ),
    topo_map_sheet = COALESCE(
        EXCLUDED.topo_map_sheet,
        inventory_archive.cluster.topo_map_sheet
    ),
    states_affected = COALESCE(
        EXCLUDED.states_affected,
        inventory_archive.cluster.states_affected
    ),
    grid_density = COALESCE(
        EXCLUDED.grid_density,
        inventory_archive.cluster.grid_density
    ),
    cluster_status = COALESCE(
        EXCLUDED.cluster_status,
        inventory_archive.cluster.cluster_status
    ),
    cluster_situation = COALESCE(
        EXCLUDED.cluster_situation,
        inventory_archive.cluster.cluster_situation
    ),
    inspire_grid_cell = COALESCE(
        EXCLUDED.inspire_grid_cell,
        inventory_archive.cluster.inspire_grid_cell
    ),
    is_training = EXCLUDED.is_training
RETURNING id INTO v_cluster_id;
-- ----------------------------------------------------------------
-- 2. Project SW corner from WGS84 → DHDN (EPSG:31466-69)
-- ----------------------------------------------------------------
v_sw_dhdn := CASE
    WHEN p_longitude < 7.51 THEN ST_Transform(
        ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326),
        31466
    )
    WHEN p_longitude >= 7.51
    AND p_longitude < 10.51 THEN ST_Transform(
        ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326),
        31467
    )
    WHEN p_longitude >= 10.51
    AND p_longitude < 13.51 THEN ST_Transform(
        ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326),
        31468
    )
    WHEN p_longitude >= 13.51 THEN ST_Transform(
        ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326),
        31469
    )
END;
v_sw_x := ST_X(v_sw_dhdn);
v_sw_y := ST_Y(v_sw_dhdn);
-- ----------------------------------------------------------------
-- 3. Insert each of the 4 corners
--
    --   plot_name 1 = SW  (origin)
--   plot_name 2 = NW  (+ N)
--   plot_name 3 = NE  (+ N + E)
--   plot_name 4 = SE  (+ E)
-- ----------------------------------------------------------------
FOR v_corner IN
SELECT *
FROM (
        VALUES (1, 0.0, 0.0),
            -- SW
            (2, 0.0, p_side_m),
            -- NW
            (3, p_side_m, p_side_m),
            -- NE
            (4, p_side_m, 0.0) -- SE
    ) AS t(plot_num, dx, dy) LOOP -- Offset in EPSG:31466-69 (metric CRS — 1 unit = 1 m)
    v_cx := v_sw_x + v_corner.dx;
v_cy := v_sw_y + v_corner.dy;
v_pt_dhdn := CASE
    WHEN p_longitude < 7.51 THEN ST_SetSRID(ST_MakePoint(v_cx, v_cy), 31466)
    WHEN p_longitude >= 7.51
    AND p_longitude < 10.51 THEN ST_SetSRID(ST_MakePoint(v_cx, v_cy), 31467)
    WHEN p_longitude >= 10.51
    AND p_longitude < 13.51 THEN ST_SetSRID(ST_MakePoint(v_cx, v_cy), 31468)
    WHEN p_longitude >= 13.51 THEN ST_SetSRID(ST_MakePoint(v_cx, v_cy), 31469)
END;
-- Project back to WGS84 for center_location
v_pt_4326 := ST_Transform(v_pt_dhdn, 4326);
-- Upsert plot
INSERT INTO inventory_archive.plot (
        cluster_id,
        cluster_name,
        plot_name,
        federal_state,
        interval_name,
        acquisition_date
    )
VALUES (
        v_cluster_id,
        p_cluster_name,
        v_corner.plot_num,
        p_federal_state,
        p_interval_name,
        p_acquisition_date
    ) ON CONFLICT (cluster_name, plot_name, interval_name) DO
UPDATE
SET cluster_id = EXCLUDED.cluster_id,
    federal_state = EXCLUDED.federal_state,
    acquisition_date = COALESCE(
        EXCLUDED.acquisition_date,
        inventory_archive.plot.acquisition_date
    )
RETURNING id INTO v_plot_id;
-- Upsert plot_coordinates (eine Zeile je Ecke, siehe 20261014000000)
v_coord_id := NULL;
INSERT INTO inventory_archive.plot_coordinates (
        cluster_name,
        plot_name,
        center_location,
        cartesian_x,
        cartesian_y
    )
VALUES (
        p_cluster_name,
        v_corner.plot_num,
        v_pt_4326,
        v_cx,
        v_cy
    ) ON CONFLICT (cluster_name, plot_name) DO
UPDATE
SET center_location = EXCLUDED.center_location,
    cartesian_x = EXCLUDED.cartesian_x,
    cartesian_y = EXCLUDED.cartesian_y
WHERE NOT EXISTS (
        SELECT 1
        FROM inventory_archive.plot op
        WHERE op.cluster_name = EXCLUDED.cluster_name
            AND op.plot_name = EXCLUDED.plot_name
            AND op.interval_name <> p_interval_name
    )
RETURNING id INTO v_coord_id;
-- Ecke gehoert auch anderen Inventuren: unveraendert lassen, gespeicherte Werte melden
IF v_coord_id IS NULL THEN
SELECT pc.id,
    pc.cartesian_x,
    pc.cartesian_y,
    pc.center_location INTO v_coord_id,
    v_cx,
    v_cy,
    v_pt_4326
FROM inventory_archive.plot_coordinates pc
WHERE pc.cluster_name = p_cluster_name
    AND pc.plot_name = v_corner.plot_num;
RAISE NOTICE 'Ecke %/% gehoert auch anderen Inventuren, Koordinate unveraendert',
p_cluster_name,
v_corner.plot_num;
END IF;
-- Emit result row
out_cluster_id := v_cluster_id;
out_plot_id := v_plot_id;
out_plot_name := v_corner.plot_num;
out_plot_coordinates_id := v_coord_id;
out_cartesian_x := v_cx;
out_cartesian_y := v_cy;
out_longitude := ST_X(v_pt_4326);
out_latitude := ST_Y(v_pt_4326);
RETURN NEXT;
END LOOP;
END;
$function$;

COMMENT ON FUNCTION inventory_archive.delete_cluster IS 'Deletes a cluster by cluster_name. Cascades to all dependent plots, plot_coordinates (via cluster_name), trees, etc. Raises an exception if the cluster does not exist. Callable by postgres only.';

-- ============================================================================
-- 9. PostgREST: computed relationships plot <-> plot_coordinates
-- ============================================================================
-- SECURITY INVOKER (Default): RLS und release_gate der Zieltabelle greifen.
CREATE OR REPLACE FUNCTION inventory_archive.plot_coordinates(inventory_archive.plot)
RETURNS SETOF inventory_archive.plot_coordinates
ROWS 1
STABLE
LANGUAGE sql
AS $$
    SELECT pc.*
    FROM inventory_archive.plot_coordinates pc
    WHERE pc.cluster_name = $1.cluster_name
        AND pc.plot_name = $1.plot_name
$$;
COMMENT ON FUNCTION inventory_archive.plot_coordinates(inventory_archive.plot) IS
    'PostgREST computed relationship: plot?select=*,plot_coordinates(*) liefert die Ecke des Plots.';

CREATE OR REPLACE FUNCTION inventory_archive.plot(inventory_archive.plot_coordinates)
RETURNS SETOF inventory_archive.plot
STABLE
LANGUAGE sql
AS $$
    SELECT p.*
    FROM inventory_archive.plot p
    WHERE p.cluster_name = $1.cluster_name
        AND p.plot_name = $1.plot_name
$$;
COMMENT ON FUNCTION inventory_archive.plot(inventory_archive.plot_coordinates) IS
    'PostgREST computed relationship: plot_coordinates?select=*,plot(*) liefert alle Plots (Inventuren) der Ecke.';

NOTIFY pgrst, 'reload schema';
