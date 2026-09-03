-- ============================================================================
-- MIGRATION: Waldentscheid und Begehbarkeit der laufenden Inventur (CI 2027)
--            in view_records_details
-- ============================================================================
-- Gefordert von den Landesinventurleitungen:
-- https://github.com/Thuenen-Forest-Ecosystems/TFM-Documentation/issues/248
--   "forest_status 2027 (Waldentscheid 2027)" und
--   "accessibility 2027 (Begehbarkeit 2027)" im LIL-Tool anzeigen,
--   inklusive Filtermoeglichkeit.
--
-- Der View liefert bisher nur die Archivwerte (forest_status_bwi2022,
-- accessibility aus inventory_archive.plot mit interval_name = 'bwi2022' sowie
-- forest_status_ci2017/_ci2012). Die Werte der LAUFENDEN Aufnahme stehen nicht
-- im Archiv, sondern in public.records.properties -- so lesen sie auch die
-- Statistik-Views aus 20260702000000 (wald2027 / begehbar2027).
--
-- Bewusst NICHT im Frontend geloest: dafuer muesste die Trakt-Liste die ganze
-- properties-JSONB jeder Ecke laden (Feldaufnahme mit Baeumen, Totholz,
-- Raendern -- Kilobytes pro Zeile bei ~60.000 Zeilen), nur um zwei Zahlen
-- herauszuziehen. Als View-Spalten sind sie ausserdem serverseitig filter- und
-- sortierbar.
--
-- Die Codes zeigen auf dieselben Lookups wie die Archivspalten:
-- lookup.lookup_forest_status bzw. lookup.lookup_accessibility.
-- ============================================================================

SET search_path TO public;

-- ============================================================================
-- view_records_details um die beiden CI-2027-Spalten erweitern
-- ============================================================================
-- CREATE OR REPLACE, kein DROP: ein DROP verwirft die Reloption
-- security_invoker, was diesem View schon einmal passiert ist (Ursache und
-- Reparatur in 20260820000000). Die neuen Spalten haengen deshalb hinten an --
-- CREATE OR REPLACE VIEW darf Spalten nur anhaengen, nicht einfuegen. Die
-- Reihenfolge im Verwaltungstool macht ohnehin die Spaltendefinition des Grids.
--
-- Der Umweg ueber die Regex statt eines direkten ::smallint ist Absicht:
-- properties ist ungetypte JSONB. Ein einziger nicht-numerischer Wert wuerde
-- sonst nicht diese eine Zelle, sondern jede Abfrage des Views zum Fehler
-- bringen -- und damit die komplette Trakt-Liste. Die Begrenzung auf vier
-- Ziffern schliesst zusaetzlich einen smallint-Ueberlauf aus; die
-- zugelassenen Codes liegen zwischen 0 und 75. Nicht interpretierbare Werte
-- werden zu NULL, also zu einer leeren Zelle.
--
-- Schlaegt das hier mit "cannot change name/type of view column" fehl, hat
-- public.records eine Spalte dazubekommen und r.* expandiert anders als beim
-- Anlegen des Views. Dann die Spaltenliste hier angleichen -- nicht einfach
-- droppen, sonst faellt security_invoker wieder weg.

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
    END AS accessibility_ci2027
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
    LEFT JOIN public.view_record_workflow_history h ON h.record_id = r.id;

COMMENT ON VIEW public.view_records_details IS
    'records + Plot-/Cluster-Kontext + abgeleiteter Eckenstatus (workflow_code) + Waldentscheid/Begehbarkeit der laufenden Aufnahme (forest_status_ci2027, accessibility_ci2027 aus records.properties). Muss security_invoker = true behalten.';

-- Idempotent: CREATE OR REPLACE laesst Reloption und Rechte zwar stehen, aber
-- ein spaeteres DROP/CREATE in einer anderen Migration nicht. Deshalb hier
-- erneut setzen, damit dieser Zustand nicht von der Historie abhaengt.
ALTER VIEW public.view_records_details SET (security_invoker = true);

REVOKE ALL ON public.view_records_details FROM PUBLIC;
REVOKE ALL ON public.view_records_details FROM anon;
GRANT SELECT ON public.view_records_details TO authenticated;

-- PostgREST kennt die neuen Spalten erst nach einem Schema-Cache-Reload.
NOTIFY pgrst, 'reload schema';
