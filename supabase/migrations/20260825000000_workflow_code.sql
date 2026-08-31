-- ============================================================================
-- MIGRATION: Eckenstatus (Workflow-Code) im Backend ableiten
-- ============================================================================
-- Bisher wurde der Eckenstatus im Verwaltungstool berechnet
-- (TFM-Documentation, components/Utils.js: workflowCodes / getWorkflowCode).
-- Folgen:
--   * Nicht filter- oder sortierbar. Die Trakt-Liste muss erst alle Seiten
--     a 10.000 Zeilen laden und danach clientseitig auswerten.
--   * Zweite, abweichende Implementierung im View v_stats_workflow_plot_map2
--     (Spalten wf/wf_text), der nur in der Live-Datenbank existiert und in
--     keiner Migration steht.
--   * Die App (Flutter) und der R-Server haben ueberhaupt keinen Zugriff.
--
-- Diese Migration verlegt die Ableitung in die Datenbank:
--   1. lookup.lookup_workflow_status         Codes + Bezeichnungen
--   2. public.view_record_workflow_history   Vorgeschichte je Ecke
--   3. public.record_workflow_code()         die Ableitung, einzige Definition
--   4. view_records_details.workflow_code    filter- und sortierbare Spalte
--
-- Codes nach der abgestimmten Tabelle in
-- https://github.com/Thuenen-Forest-Ecosystems/TFM-Documentation/issues/14
--
-- Die Codes 32, 42, 43 und 44 unterscheiden sich von ihrem Basiscode nur durch
-- die Vorgeschichte ("nach Korrektur", "nach Kontrolltrupp", "nach Rueckgabe
-- durch BIL") und lassen sich aus der aktuellen records-Zeile allein nicht
-- ableiten. Die Vorgeschichte steht in public.record_changes: der Audit-Trigger
-- on_record_updated erfasst seit 20250312143819 unter anderem
-- completed_at_troop, completed_at_state und responsible_troop, und
-- handle_record_changes() schreibt record_id = OLD.id.
--
-- ACHTUNG, Abhaengigkeit von der Aufbewahrung: Wer Zeilen aus record_changes
-- loescht, aendert damit rueckwirkend Statuscodes. Solange es in public.records
-- keine eigenen Ereignis-Zeitstempel gibt (control_troop_id,
-- completed_at_control_troop, returned_at_troop, returned_at_state), darf die
-- Tabelle nicht beschnitten werden.
--
-- Code 45 ("Akzeptiert LIL") bleibt bewusst offen: er unterscheidet sich in der
-- Tabelle von 44 und 60 nur ueber die Spalte at_state, die es nicht gibt, und
-- records.is_plausible ist der Ergebnis-Slot der Plausibilitaetspruefung, kein
-- Freigabe-Kennzeichen der Landesinventurleitung.
-- ============================================================================

SET search_path TO public;

-- ============================================================================
-- 1. Lookup-Tabelle fuer die Bezeichnungen
-- ============================================================================
-- Bewusst als Lookup und nicht als CASE im View oder als Konstante im
-- Frontend: Verwaltungstool, App und R-Server lesen dieselben Bezeichnungen.

CREATE TABLE IF NOT EXISTS lookup.lookup_workflow_status (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);

ALTER TABLE lookup.lookup_workflow_status
    ADD COLUMN IF NOT EXISTS description_de text NULL;
ALTER TABLE lookup.lookup_workflow_status
    ADD COLUMN IF NOT EXISTS description_en text NULL;

COMMENT ON TABLE lookup.lookup_workflow_status IS
    'Eckenstatus (Workflow-Code) nach TFM-Documentation Issue #14. Wird von public.record_workflow_code() erzeugt, nicht von Hand gesetzt.';

INSERT INTO lookup.lookup_workflow_status (code, name_de, name_en, description_de, sort)
VALUES
    (10, 'Vorarbeiten BIL',              'Preparation NFI management',   'Initialisierung, Zuweisung LIL',                                        10),
    (20, 'Vorarbeiten LIL',              'Preparation state management', 'Anlage Dienstleister und Trupps, Zuweisung Aufnahmetrupp, Vorklaerung', 20),
    (31, 'Aufnahme im Feld AT',          'Field survey',                 'Erstaufnahme durch den Aufnahmetrupp',                                  31),
    (32, 'Aufnahme im Feld AT',          'Repeat survey',                'Wiederholung oder Korrektur durch den Aufnahmetrupp',                   32),
    (41, 'Qualitaetskontrolle LIL',      'Quality control state',        'Feldaufnahme beendet, Pruefung durch die Landesinventurleitung',        41),
    (42, 'Qualitaetskontrolle LIL',      'Quality control state',        'Pruefung nach Korrektur oder Wiederholungsaufnahme',                    42),
    (43, 'Qualitaetskontrolle LIL',      'Quality control state',        'Pruefung nach Einsatz des Kontrolltrupps',                              43),
    (44, 'Qualitaetskontrolle LIL',      'Quality control state',        'Pruefung nach Rueckgabe durch die Bundesinventurleitung',               44),
    (50, 'Kontrolle/Korrektur im Feld',  'Control survey',               'Kontrolltrupp erhebt Daten',                                            50),
    (60, 'Qualitaetskontrolle BIL',      'Quality control NFI',          'Von der LIL akzeptiert, Pruefung durch die Bundesinventurleitung',      60),
    (70, 'Akzeptiert BIL',               'Accepted',                     'Ecke abgeschlossen',                                                    70)
ON CONFLICT (code) DO UPDATE SET
    name_de        = EXCLUDED.name_de,
    name_en        = EXCLUDED.name_en,
    description_de = EXCLUDED.description_de,
    sort           = EXCLUDED.sort;

-- Rechte und RLS analog zu den uebrigen lookup-Tabellen. enable_rls_for_schema()
-- aus 20250115140841_rls.sql lief einmalig, greift also fuer neue Tabellen
-- nicht mehr; der Policy-Name ist derselbe, den die Funktion erzeugt haette.
-- ti_read fehlt in den DEFAULT PRIVILEGES von 20241202134806 und braucht ein
-- explizites GRANT.
GRANT SELECT ON lookup.lookup_workflow_status TO anon, authenticated, service_role, ti_read;

ALTER TABLE lookup.lookup_workflow_status ENABLE ROW LEVEL SECURITY;
ALTER TABLE lookup.lookup_workflow_status FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS default_select_anon_and_ti_read_and_authenticated ON lookup.lookup_workflow_status;
CREATE POLICY default_select_anon_and_ti_read_and_authenticated
    ON lookup.lookup_workflow_status FOR SELECT
    TO anon, ti_read, authenticated
    USING (true);

-- ============================================================================
-- 2. Teilindizes fuer die Historien-Abfragen
-- ============================================================================
-- Ohne sie kostet die Ableitung einen Bitmap Heap Scan pro Ecke. Mit ihnen
-- werden alle drei Pruefungen zu Index Only Scans mit null Heap-Zugriffen --
-- gemessen 826 ms -> 283 ms bei 60.000 Ecken und 300.000 Historienzeilen. Der
-- entscheidende Effekt ist nicht die Zeit, sondern dass die aufgeblaehten
-- properties-Kopien in record_changes gar nicht mehr angefasst werden.

CREATE INDEX IF NOT EXISTS idx_record_changes_completed_at_troop
    ON public.record_changes (record_id, completed_at_troop)
    WHERE completed_at_troop IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_record_changes_completed_at_state
    ON public.record_changes (record_id, completed_at_state)
    WHERE completed_at_state IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_record_changes_troop_history
    ON public.record_changes (record_id, responsible_troop)
    WHERE responsible_troop IS NOT NULL;

-- ============================================================================
-- 3. Historien-Merkmale je Ecke
-- ============================================================================
-- Dieser View laeuft BEWUSST ohne security_invoker, also mit den Rechten des
-- Eigentuemers. Grund: die SELECT-Policy auf record_changes greift pro
-- Historienzeile anhand der DAMALIGEN responsible_*-Werte. Unter
-- security_invoker saehe ein Trupp, dem die Ecke nicht mehr gehoert, andere
-- Historienzeilen als die LIL -- und damit einen anderen Statuscode fuer
-- dieselbe Ecke. Ein Status, der vom Betrachter abhaengt, waere keiner.
--
-- Kein GROUP BY: eine Aggregation ueber record_changes kostet konstant ~100 ms,
-- egal wie wenige Ecken die aeussere Abfrage will, und waechst mit der Historie.
-- In dieser Form kann der Planer den Filter der aeusseren Abfrage durchreichen
-- (gemessen: 3 ms statt 107 ms bei einer auf 7 Ecken gefilterten Abfrage).
--
-- Preis dafuer: authenticated darf den View auch direkt lesen und bekommt dann
-- drei Lebenslauf-Booleans zu Ecken, die es sonst nicht sieht -- allerdings nur
-- ueber deren UUID, die selbst per RLS geschuetzt ist.

CREATE OR REPLACE VIEW public.view_record_workflow_history AS
SELECT r.id AS record_id,
    -- Es gab eine Abgabe, die nicht die aktuelle ist: die Ecke wurde
    -- zurueckgegeben oder erneut abgegeben. Der naheliegende Test
    -- "completed_at_troop IS NOT NULL" waere falsch -- record_changes haelt den
    -- ALTEN Zustand, also entsteht schon beim blossen Abziehen des Trupps nach
    -- regulaerer Abgabe eine Zeile mit gesetztem completed_at_troop.
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
    ) AS returned_by_administration
FROM public.records r;

COMMENT ON VIEW public.view_record_workflow_history IS
    'Historien-Merkmale je Ecke aus public.record_changes, Grundlage der Codes 32/42/43/44. Laeuft absichtlich OHNE security_invoker, damit der Statuscode nicht vom Betrachter abhaengt.';

REVOKE ALL ON public.view_record_workflow_history FROM PUBLIC;
REVOKE ALL ON public.view_record_workflow_history FROM anon;
GRANT SELECT ON public.view_record_workflow_history TO authenticated, service_role;

-- ============================================================================
-- 4. Die Ableitung
-- ============================================================================
-- Alle Merkmale kommen als Argumente herein, statt dass die Funktion sie selbst
-- nachschlaegt: is_control_troop steckt in public.troop, die drei
-- Historien-Merkmale in public.view_record_workflow_history -- beides nicht in
-- public.records. Wuerde die Funktion nachschlagen, waere sie nur STABLE und
-- machte Lookups pro Zeile. So bleibt sie IMMUTABLE, und der Aufrufer liefert
-- alles aus Joins.
--
-- Reihenfolge = Prioritaet, der erste Treffer gewinnt (spaetester Meilenstein
-- zuerst). Code 50 steht vor 41-44: ist ein Kontrolltrupp zugewiesen, ist die
-- Ecke in der Feldkontrolle, auch wenn completed_at_troop bereits gesetzt ist.
-- Innerhalb der Qualitaetskontrolle der LIL gewinnt ebenfalls das spaeteste
-- Ereignis: Rueckgabe durch die BIL (44) vor Kontrolltrupp (43) vor Korrektur
-- (42) vor Erstaufnahme (41).

CREATE OR REPLACE FUNCTION public.record_workflow_code(
    rec public.records,
    is_control_troop boolean,
    repeated_survey boolean,
    seen_control_troop boolean,
    returned_by_administration boolean
) RETURNS smallint
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
SELECT (CASE
    WHEN rec.completed_at_administration IS NOT NULL                       THEN 70
    WHEN rec.completed_at_state          IS NOT NULL                       THEN 60
    WHEN rec.responsible_troop IS NOT NULL AND is_control_troop            THEN 50
    WHEN rec.completed_at_troop IS NOT NULL AND returned_by_administration THEN 44
    WHEN rec.completed_at_troop IS NOT NULL AND seen_control_troop         THEN 43
    WHEN rec.completed_at_troop IS NOT NULL AND repeated_survey            THEN 42
    WHEN rec.completed_at_troop          IS NOT NULL                       THEN 41
    WHEN rec.responsible_troop IS NOT NULL AND repeated_survey             THEN 32
    WHEN rec.responsible_troop           IS NOT NULL                       THEN 31
    WHEN rec.responsible_state           IS NOT NULL                       THEN 20
    WHEN rec.responsible_administration  IS NOT NULL                       THEN 10
END)::smallint;
$$;

COMMENT ON FUNCTION public.record_workflow_code(public.records, boolean, boolean, boolean, boolean) IS
    'Eckenstatus einer records-Zeile nach lookup.lookup_workflow_status. is_control_troop aus troop.is_control_troop des zugewiesenen Trupps, die uebrigen drei aus public.view_record_workflow_history. NULL, wenn nicht einmal responsible_administration gesetzt ist.';

GRANT EXECUTE ON FUNCTION public.record_workflow_code(public.records, boolean, boolean, boolean, boolean)
    TO authenticated, service_role, ti_read;

-- ============================================================================
-- 5. view_records_details um workflow_code erweitern
-- ============================================================================
-- CREATE OR REPLACE, kein DROP: ein DROP verwirft die Reloption
-- security_invoker, was diesem View schon einmal passiert ist (Ursache und
-- Reparatur in 20260820000000). Die neue Spalte haengt deshalb am Ende --
-- CREATE OR REPLACE VIEW darf Spalten nur anhaengen, nicht einfuegen.
--
-- Schlaegt das hier mit "cannot change name/type of view column" fehl, hat
-- public.records seit dem 14.07.2026 eine Spalte dazubekommen und r.* expandiert
-- anders als beim Anlegen des Views. Dann die Spaltenliste hier angleichen --
-- nicht einfach droppen, sonst faellt security_invoker wieder weg.
--
-- Beide zusaetzlichen LEFT JOINs sind 1:1 (t.id ist PK, h.record_id ist die
-- records-PK) und aendern die Zeilenzahl nicht. Unter security_invoker greift
-- die RLS des Aufrufers: troop_member_read_policy ist FOR SELECT USING (true)
-- (20250115140841_rls.sql), der Join bricht also fuer keinen authentifizierten
-- Nutzer weg.

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
    ) AS workflow_code
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
    'records + Plot-/Cluster-Kontext + abgeleiteter Eckenstatus (workflow_code). Muss security_invoker = true behalten.';

-- Idempotent: CREATE OR REPLACE laesst Reloption und Rechte zwar stehen, aber
-- ein spaeteres DROP/CREATE in einer anderen Migration nicht. Deshalb hier
-- erneut setzen, damit dieser Zustand nicht von der Historie abhaengt.
ALTER VIEW public.view_records_details SET (security_invoker = true);

REVOKE ALL ON public.view_records_details FROM PUBLIC;
REVOKE ALL ON public.view_records_details FROM anon;
GRANT SELECT ON public.view_records_details TO authenticated;

-- Aufraeumen fuer Datenbanken, auf denen die urspruengliche zweistufige Fassung
-- dieser Migration schon lief: dort existiert noch die Zwei-Argument-Variante.
-- Erst hier, wo der View bereits auf die neue Signatur zeigt.
DROP FUNCTION IF EXISTS public.record_workflow_code(public.records, boolean);

-- PostgREST kennt die neue Spalte erst nach einem Schema-Cache-Reload.
NOTIFY pgrst, 'reload schema';
