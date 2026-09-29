-- ============================================================================
-- TEST: view_records_details.last_survey_troop — letzter Aufnahmetrupp
-- ============================================================================
-- Prueft die Ableitung aus 20260929000000_last_survey_troop.sql gegen die
-- tatsaechlichen Daten der Datenbank, in der er laeuft.
--
-- SAFE BY DESIGN (auch gegen Produktion): der Test schreibt nichts, er liest
-- nur records, record_changes, troop und die beiden Views.
--
-- Die Wahrheitstabelle der Ableitung laesst sich nicht wie bei
-- record_workflow_code() aus Speicher-Composites bauen — sie haengt an echten
-- record_changes-Zeilen. Geprueft werden deshalb Invarianten, die auf jedem
-- Datenbestand gelten muessen.
--
-- Run:  psql "$DATABASE_URL" -f test_last_survey_troop.sql
-- ============================================================================
\set ON_ERROR_STOP on
\pset pager off
\timing off

\echo ''
\echo '=== View-Zustand ========================================================='

SELECT
    (SELECT count(*) FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'view_records_details'
        AND column_name = 'last_survey_troop') = 1                   AS spalte_in_details,
    (SELECT count(*) FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'view_record_workflow_history'
        AND column_name = 'last_survey_troop') = 1                   AS spalte_in_historie,
    (SELECT reloptions FROM pg_class WHERE relname = 'view_records_details')
        @> ARRAY['security_invoker=true']                            AS details_ist_security_invoker,
    -- Wie beim Statuscode: die Historie MUSS ohne security_invoker laufen,
    -- sonst haengt der angezeigte Aufnahmetrupp am Betrachter.
    COALESCE((SELECT reloptions FROM pg_class WHERE relname = 'view_record_workflow_history'), '{}')
        @> ARRAY['security_invoker=true']                            AS historie_faelschlich_invoker,
    (SELECT count(*) FROM public.records)
        = (SELECT count(*) FROM public.view_records_details)         AS zeilenzahl_unveraendert;

\echo ''
\echo '=== Invarianten =========================================================='

WITH v AS (
    SELECT id, responsible_troop, completed_at_troop, last_survey_troop
    FROM public.view_records_details
)
SELECT
    -- Ein Kontrolltrupp ist kein Aufnahmetrupp. Genau dafuer gibt es die
    -- Spalte: sie soll zeigen, WER aufgenommen hat, nicht wer kontrolliert.
    (SELECT count(*) FROM v JOIN public.troop t ON t.id = v.last_survey_troop
      WHERE t.is_control_troop) = 0                                  AS kein_kontrolltrupp,
    -- Eine reine Ansichtsgruppe schreibt nichts und kann nicht aufgenommen haben.
    (SELECT count(*) FROM v JOIN public.troop t ON t.id = v.last_survey_troop
      WHERE t.is_read_only) = 0                                      AS keine_leserechte_gruppe,
    -- Jeder gemeldete Trupp existiert noch.
    (SELECT count(*) FROM v WHERE v.last_survey_troop IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM public.troop t WHERE t.id = v.last_survey_troop)) = 0
                                                                     AS trupp_existiert,
    -- Steht der aktuell zugewiesene Trupp selbst als Aufnahmetrupp auf einer
    -- abgegebenen Ecke, ist er der juengste Stand und muss gewinnen.
    (SELECT count(*) FROM v JOIN public.troop t ON t.id = v.responsible_troop
      WHERE v.completed_at_troop IS NOT NULL
        AND NOT t.is_control_troop AND NOT t.is_read_only
        AND v.last_survey_troop IS DISTINCT FROM v.responsible_troop) = 0
                                                                     AS aktuelle_zeile_hat_vorrang,
    -- Kommt der Wert nicht aus der laufenden Zeile, muss es die belegende
    -- Historienzeile geben: derselbe Trupp, mit gesetztem completed_at_troop.
    (SELECT count(*) FROM v
      WHERE v.last_survey_troop IS NOT NULL
        AND v.last_survey_troop IS DISTINCT FROM v.responsible_troop
        AND NOT EXISTS (
            SELECT 1 FROM public.record_changes rc
            WHERE rc.record_id = v.id
              AND rc.responsible_troop = v.last_survey_troop
              AND rc.completed_at_troop IS NOT NULL)) = 0            AS historie_belegt_den_wert,
    -- Umkehrung: gibt es ueberhaupt eine abgebende Aufnahmetrupp-Zeile, darf
    -- die Spalte nicht leer bleiben.
    (SELECT count(*) FROM v
      WHERE v.last_survey_troop IS NULL
        AND EXISTS (
            SELECT 1 FROM public.record_changes rc JOIN public.troop t ON t.id = rc.responsible_troop
            WHERE rc.record_id = v.id AND rc.completed_at_troop IS NOT NULL
              AND NOT t.is_control_troop AND NOT t.is_read_only)) = 0
                                                                     AS keine_verlorene_historie;

\echo ''
\echo '=== Abdeckung (informativ, kein Pass/Fail) ==============================='

SELECT count(*)                                                          AS ecken,
       count(last_survey_troop)                                          AS mit_aufnahmetrupp,
       count(*) FILTER (WHERE last_survey_troop IS NOT NULL
                          AND last_survey_troop IS DISTINCT FROM responsible_troop)
                                                                         AS nur_aus_historie
FROM public.view_records_details;
