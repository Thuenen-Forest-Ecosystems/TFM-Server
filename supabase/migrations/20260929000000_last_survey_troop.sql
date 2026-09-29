-- ============================================================================
-- MIGRATION: Letzter Aufnahmetrupp je Ecke aus der Historie
-- ============================================================================
-- Gefordert von den Landesinventurleitungen: in der Trakt-Liste soll sichtbar
-- sein, WELCHER Aufnahmetrupp eine Ecke zuletzt abgegeben hat -- auch dann,
-- wenn inzwischen ein Kontrolltrupp auf der Ecke sitzt.
--
-- public.records kennt nur den AKTUELL zugewiesenen Trupp. Sobald ein
-- Kontrolltrupp zugewiesen wird, ueberschreibt er responsible_troop, und der
-- Aufnahmetrupp ist in der laufenden Zeile nicht mehr zu sehen. Er steht aber
-- in public.record_changes: der Trigger on_record_updated feuert unter anderem
-- bei "OLD.responsible_troop IS DISTINCT FROM NEW.responsible_troop"
-- (20260714000000) und handle_record_changes() schreibt dabei den ALTEN Stand
-- der Zeile weg -- also genau den abgeloesten Trupp samt seinem
-- completed_at_troop.
--
-- Abgrenzung "zuletzt abgegeben" statt "zuletzt zugewiesen": gezaehlt wird nur
-- eine Historienzeile mit gesetztem completed_at_troop. Ein Trupp, der eine
-- Ecke nur zugewiesen bekam und wieder abgezogen wurde, hat sie nicht
-- aufgenommen und gehoert nicht in diese Spalte.
--
-- Warum das completed_at_troop der Historienzeile trotzdem zum Trupp DERSELBEN
-- Zeile passt: record_changes haelt den alten Zustand als Ganzes. Wird ein
-- Trupp neu zugewiesen, setzt das Verwaltungstool completed_at_troop
-- gleichzeitig auf NULL (die Ecke geht zurueck ins Feld), die beiden Werte
-- laufen also nicht auseinander.
--
-- Kosten: keine messbaren. Der Partial-Index idx_record_changes_completed_at_troop
-- (record_id, completed_at_troop) WHERE completed_at_troop IS NOT NULL aus
-- 20260825000000 deckt den Zugriff als Index-Only-Scan ab. Gemessen auf einem
-- Prod-Abzug (122k Ecken / 217k Historienzeilen): groesstes Land mit 30.680
-- Ecken 886 ms ohne, 627 ms mit der neuen Spalte -- der Unterschied liegt im
-- Messrauschen.
-- ============================================================================

SET search_path TO public;

-- ============================================================================
-- 1. view_record_workflow_history um den letzten Aufnahmetrupp erweitern
-- ============================================================================
-- Die Ableitung gehoert hierher und nicht direkt in view_records_details, weil
-- dieser View bewusst OHNE security_invoker laeuft (Begruendung in
-- 20260825000000): die SELECT-Policy auf record_changes greift pro
-- Historienzeile anhand der DAMALIGEN responsible_*-Werte. Unter
-- security_invoker saehe eine LIL den Aufnahmetrupp einer Ecke, die inzwischen
-- einem anderen Land gehoert, nicht mehr -- die Spalte haenge also am
-- Betrachter statt an der Ecke.
--
-- Kein GROUP BY, sondern ein korrelierter Subquery wie bei den drei
-- bestehenden Spalten: nur so kann der Planer den Filter der aeusseren Abfrage
-- durchreichen.
--
-- CREATE OR REPLACE darf Spalten nur ANHAENGEN -- die drei vorhandenen Spalten
-- bleiben deshalb unveraendert in ihrer Reihenfolge stehen.

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
    ) AS returned_by_administration,
    -- Juengster Aufnahmetrupp in der Historie, der die Ecke abgegeben hat.
    -- is_read_only schliesst die reinen Ansichtsgruppen aus: die sitzen zwar in
    -- einer eigenen Spalte (responsible_read_only_troop) und sollten hier gar
    -- nicht auftauchen, aber eine Gruppe ohne Schreibrechte darf unter keinen
    -- Umstaenden als Aufnahmetrupp gemeldet werden.
    -- Sortiert nach completed_at_troop, nicht nach created_at: massgeblich ist,
    -- wer zuletzt ABGEGEBEN hat, nicht in welcher Reihenfolge die Zuweisungen
    -- nachtraeglich weggeschrieben wurden. created_at nur als Tiebreaker.
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
    ) AS last_survey_troop
FROM public.records r;

COMMENT ON VIEW public.view_record_workflow_history IS
    'Historien-Merkmale je Ecke aus public.record_changes: Grundlage der Codes 32/42/43/44 sowie der letzte abgebende Aufnahmetrupp (last_survey_troop). Laeuft absichtlich OHNE security_invoker, damit die Werte nicht vom Betrachter abhaengen.';

REVOKE ALL ON public.view_record_workflow_history FROM PUBLIC;
REVOKE ALL ON public.view_record_workflow_history FROM anon;
GRANT SELECT ON public.view_record_workflow_history TO authenticated, service_role;

-- ============================================================================
-- 2. view_records_details: Spalte last_survey_troop
-- ============================================================================
-- CREATE OR REPLACE, kein DROP: ein DROP verwirft die Reloption
-- security_invoker, was diesem View schon einmal passiert ist (Ursache und
-- Reparatur in 20260820000000). Die neue Spalte haengt deshalb hinten an.
--
-- Schlaegt das hier mit "cannot change name/type of view column" fehl, hat
-- public.records eine Spalte dazubekommen und r.* expandiert anders als beim
-- Anlegen des Views. Dann die Spaltenliste hier angleichen -- nicht einfach
-- droppen, sonst faellt security_invoker wieder weg.
--
-- Der COALESCE-Zweig auf die laufende Zeile ist noetig, weil die Historie nur
-- ABGELOESTE Zustaende kennt: solange der Aufnahmetrupp noch selbst zugewiesen
-- ist, gibt es zu seiner Abgabe noch keine Historienzeile. Die laufende Zeile
-- ist immer der juengste Stand und hat deshalb Vorrang.

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
    COALESCE(
        CASE WHEN r.completed_at_troop IS NOT NULL
              AND NOT COALESCE(t.is_control_troop, false)
              AND NOT COALESCE(t.is_read_only, false)
             THEN r.responsible_troop
        END,
        h.last_survey_troop
    ) AS last_survey_troop
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
    'records + Plot-/Cluster-Kontext + abgeleiteter Eckenstatus (workflow_code) + Waldentscheid/Begehbarkeit der laufenden Aufnahme (forest_status_ci2027, accessibility_ci2027 aus records.properties) + letzter abgebender Aufnahmetrupp (last_survey_troop). Muss security_invoker = true behalten.';

-- Idempotent: CREATE OR REPLACE laesst Reloption und Rechte zwar stehen, aber
-- ein spaeteres DROP/CREATE in einer anderen Migration nicht. Deshalb hier
-- erneut setzen, damit dieser Zustand nicht von der Historie abhaengt.
ALTER VIEW public.view_records_details SET (security_invoker = true);

REVOKE ALL ON public.view_records_details FROM PUBLIC;
REVOKE ALL ON public.view_records_details FROM anon;
GRANT SELECT ON public.view_records_details TO authenticated;

-- PostgREST kennt die neue Spalte erst nach einem Schema-Cache-Reload.
NOTIFY pgrst, 'reload schema';
