-- ============================================================================
-- MIGRATION: Abgabedaten je Trupp-Art, letzter Kontrolltrupp, GNSS-Datum
-- ============================================================================
-- TFM-Documentation Issue #261: in der Eckenansicht sollen sichtbar sein
--   * Datum der GNSS-Messung (Datum der Feldaufnahme)
--   * Abgeschlossen Aufnahmetrupp
--   * Abgeschlossen Kontrolltrupp
--   * letzter Kontrolltrupp
--
-- records.completed_at_troop gehoert immer zum AKTUELL zugewiesenen Trupp.
-- Wird ein Kontrolltrupp zugewiesen, setzt das Verwaltungstool den Wert auf
-- NULL, und gibt der Kontrolltrupp ab, steht dort sein Datum. Das Datum des
-- Aufnahmetrupps ist dann nur noch in public.record_changes zu finden --
-- dieselbe Lage wie beim Trupp selbst, deshalb dieselbe Ableitung wie
-- last_survey_troop in 20260929000000 (Begruendung dort).
--
-- Kontrolltrupp "zuletzt abgegeben", nicht "zuletzt zugewiesen": der aktuell
-- zugewiesene Kontrolltrupp steht schon in responsible_troop. Die neue Spalte
-- gehoert mit completed_at_control_troop zusammen -- Trupp und Datum stammen
-- immer aus derselben Quelle.
--
-- Die Daten werden mit max() statt ORDER BY ... LIMIT 1 geholt: das juengste
-- completed_at_troop ist genau das Datum der Zeile, die last_survey_troop
-- bzw. last_control_troop liefert.
-- ============================================================================

SET search_path TO public;

-- ============================================================================
-- 1. Fehlertoleranter Timestamp-Cast
-- ============================================================================
-- position.start_measurement ist Freitext im JSON (die App schreibt
-- DateTime.toIso8601String() in Geraete-Ortszeit, ohne Zeitzone). Ein
-- direkter ::timestamp-Cast liesse bei einem einzigen kaputten Wert die
-- komplette Abfrage auf view_records_details scheitern. PG 15 hat noch kein
-- pg_input_is_valid(), also ueber einen Exception-Block. Der kostet eine
-- Subtransaktion pro Aufruf -- der Regex-Vorfilter im View sorgt dafuer, dass
-- nur plausibel aussehende Werte hier ankommen.

CREATE OR REPLACE FUNCTION public.try_parse_timestamp(value text)
RETURNS timestamp without time zone
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
BEGIN
    RETURN value::timestamp without time zone;
EXCEPTION WHEN others THEN
    RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.try_parse_timestamp(text) IS
    'Cast text -> timestamp; NULL statt Fehler bei ungueltiger Eingabe. Fuer Zeitstempel aus records.properties (Issue #261).';

REVOKE ALL ON FUNCTION public.try_parse_timestamp(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.try_parse_timestamp(text) TO authenticated, service_role;

-- ============================================================================
-- 2. view_record_workflow_history: Abgabedaten und letzter Kontrolltrupp
-- ============================================================================
-- CREATE OR REPLACE darf Spalten nur ANHAENGEN -- die vier vorhandenen Spalten
-- bleiben unveraendert in ihrer Reihenfolge stehen.

CREATE OR REPLACE VIEW public.view_record_workflow_history AS
SELECT r.id AS record_id,
    EXISTS (
        SELECT 1 FROM public.record_changes rc
        WHERE rc.record_id = r.id
          AND rc.completed_at_troop IS NOT NULL
          AND rc.completed_at_troop IS DISTINCT FROM r.completed_at_troop
    ) AS repeated_survey,
    EXISTS (
        SELECT 1 FROM public.record_changes rc
        JOIN public.troop t ON t.id = rc.responsible_troop
        WHERE rc.record_id = r.id AND t.is_control_troop
    ) AS seen_control_troop,
    EXISTS (
        SELECT 1 FROM public.record_changes rc
        WHERE rc.record_id = r.id
          AND rc.completed_at_state IS NOT NULL
          AND rc.completed_at_state IS DISTINCT FROM r.completed_at_state
    ) AS returned_by_administration,
    (
        SELECT rc.responsible_troop
        FROM public.record_changes rc
        JOIN public.troop t ON t.id = rc.responsible_troop
        WHERE rc.record_id = r.id
          AND rc.completed_at_troop IS NOT NULL
          AND NOT t.is_control_troop
          AND NOT t.is_read_only
        ORDER BY rc.completed_at_troop DESC, rc.created_at DESC
        LIMIT 1
    ) AS last_survey_troop,
    -- Abgabedatum zu last_survey_troop.
    (
        SELECT max(rc.completed_at_troop)
        FROM public.record_changes rc
        JOIN public.troop t ON t.id = rc.responsible_troop
        WHERE rc.record_id = r.id
          AND rc.completed_at_troop IS NOT NULL
          AND NOT t.is_control_troop
          AND NOT t.is_read_only
    ) AS completed_at_survey_troop,
    -- Juengster Kontrolltrupp in der Historie, der die Ecke abgegeben hat.
    (
        SELECT rc.responsible_troop
        FROM public.record_changes rc
        JOIN public.troop t ON t.id = rc.responsible_troop
        WHERE rc.record_id = r.id
          AND rc.completed_at_troop IS NOT NULL
          AND t.is_control_troop
        ORDER BY rc.completed_at_troop DESC, rc.created_at DESC
        LIMIT 1
    ) AS last_control_troop,
    -- Abgabedatum zu last_control_troop.
    (
        SELECT max(rc.completed_at_troop)
        FROM public.record_changes rc
        JOIN public.troop t ON t.id = rc.responsible_troop
        WHERE rc.record_id = r.id
          AND rc.completed_at_troop IS NOT NULL
          AND t.is_control_troop
    ) AS completed_at_control_troop
FROM public.records r;

COMMENT ON VIEW public.view_record_workflow_history IS
    'Historien-Merkmale je Ecke aus public.record_changes: Grundlage der Codes 32/42/43/44, letzter abgebender Aufnahme- und Kontrolltrupp samt Abgabedatum. Laeuft absichtlich OHNE security_invoker, damit die Werte nicht vom Betrachter abhaengen.';

REVOKE ALL ON public.view_record_workflow_history FROM PUBLIC;
REVOKE ALL ON public.view_record_workflow_history FROM anon;
GRANT SELECT ON public.view_record_workflow_history TO authenticated, service_role;

-- ============================================================================
-- 3. view_records_details: vier neue Spalten
-- ============================================================================
-- CREATE OR REPLACE, kein DROP (security_invoker, siehe 20260820000000).
-- Neue Spalten haengen hinten an.
--
-- Wie bei last_survey_troop hat die laufende Zeile Vorrang vor der Historie:
-- solange der abgebende Trupp noch zugewiesen ist, gibt es zu seiner Abgabe
-- keine Historienzeile. Trupp und Datum laufen ueber dieselbe Bedingung, damit
-- sie nie aus verschiedenen Quellen kommen.

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
    LEFT JOIN inventory_archive.plot_coordinates p_coordinates ON p_bwi.id = p_coordinates.plot_id
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

COMMENT ON VIEW public.view_records_details IS
    'records + Plot-/Cluster-Kontext + abgeleiteter Eckenstatus (workflow_code) + Waldentscheid/Begehbarkeit der laufenden Aufnahme (forest_status_ci2027, accessibility_ci2027 aus records.properties) + letzter abgebender Aufnahme-/Kontrolltrupp samt Abgabedatum + Beginn der GNSS-Messung (gnss_measured_at). Muss security_invoker = true behalten.';

ALTER VIEW public.view_records_details SET (security_invoker = true);

REVOKE ALL ON public.view_records_details FROM PUBLIC;
REVOKE ALL ON public.view_records_details FROM anon;
GRANT SELECT ON public.view_records_details TO authenticated;

NOTIFY pgrst, 'reload schema';
