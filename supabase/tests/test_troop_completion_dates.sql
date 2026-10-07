-- ============================================================================
-- TEST: view_records_details — Abgabedaten je Trupp-Art, letzter
--       Kontrolltrupp, GNSS-Datum (Issue #261)
-- ============================================================================
-- Prueft die Ableitung aus 20261007000000_troop_completion_dates.sql gegen die
-- tatsaechlichen Daten der Datenbank, in der er laeuft.
--
-- SAFE BY DESIGN (auch gegen Produktion): der Test schreibt nichts, er liest
-- nur records, record_changes, troop und die beiden Views.
--
-- Run:  psql "$DATABASE_URL" -f test_troop_completion_dates.sql
-- ============================================================================
\set ON_ERROR_STOP on
\pset pager off
\timing off

\echo ''
\echo '=== View-Zustand ========================================================='

SELECT
    (SELECT count(*) FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'view_records_details'
        AND column_name IN ('completed_at_survey_troop', 'last_control_troop',
                            'completed_at_control_troop', 'gnss_measured_at')) = 4
                                                                     AS spalten_in_details,
    (SELECT reloptions FROM pg_class WHERE relname = 'view_records_details')
        @> ARRAY['security_invoker=true']                            AS details_ist_security_invoker,
    COALESCE((SELECT reloptions FROM pg_class WHERE relname = 'view_record_workflow_history'), '{}')
        @> ARRAY['security_invoker=true']                            AS historie_faelschlich_invoker,
    (SELECT count(*) FROM public.records)
        = (SELECT count(*) FROM public.view_records_details)         AS zeilenzahl_unveraendert,
    public.try_parse_timestamp('2026-02-30T10:00:00') IS NULL
        AND public.try_parse_timestamp('2026-05-18T14:46:43.607800')
            = '2026-05-18 14:46:43.6078'::timestamp                  AS cast_ist_fehlertolerant;

\echo ''
\echo '=== Invarianten =========================================================='

WITH v AS (
    SELECT id, responsible_troop, completed_at_troop, properties,
           last_survey_troop, completed_at_survey_troop,
           last_control_troop, completed_at_control_troop, gnss_measured_at
    FROM public.view_records_details
)
SELECT
    -- Trupp und Datum kommen immer aus derselben Quelle.
    (SELECT count(*) FROM v
      WHERE (v.last_survey_troop IS NULL) <> (v.completed_at_survey_troop IS NULL)) = 0
                                                                     AS aufnahmetrupp_paar_konsistent,
    (SELECT count(*) FROM v
      WHERE (v.last_control_troop IS NULL) <> (v.completed_at_control_troop IS NULL)) = 0
                                                                     AS kontrolltrupp_paar_konsistent,
    -- Ein gemeldeter Kontrolltrupp ist auch einer.
    (SELECT count(*) FROM v JOIN public.troop t ON t.id = v.last_control_troop
      WHERE NOT t.is_control_troop) = 0                              AS nur_kontrolltrupps,
    -- Der aktuell zugewiesene, abgebende Kontrolltrupp ist der juengste Stand.
    (SELECT count(*) FROM v JOIN public.troop t ON t.id = v.responsible_troop
      WHERE v.completed_at_troop IS NOT NULL AND t.is_control_troop
        AND (v.last_control_troop IS DISTINCT FROM v.responsible_troop
             OR v.completed_at_control_troop IS DISTINCT FROM v.completed_at_troop)) = 0
                                                                     AS aktuelle_zeile_hat_vorrang_kt,
    (SELECT count(*) FROM v JOIN public.troop t ON t.id = v.responsible_troop
      WHERE v.completed_at_troop IS NOT NULL
        AND NOT t.is_control_troop AND NOT t.is_read_only
        AND v.completed_at_survey_troop IS DISTINCT FROM v.completed_at_troop) = 0
                                                                     AS aktuelle_zeile_hat_vorrang_at,
    -- Kommt das Datum aus der Historie, muss es die belegende Zeile geben.
    (SELECT count(*) FROM v
      WHERE v.completed_at_control_troop IS NOT NULL
        AND v.completed_at_control_troop IS DISTINCT FROM v.completed_at_troop
        AND NOT EXISTS (
            SELECT 1 FROM public.record_changes rc
            WHERE rc.record_id = v.id
              AND rc.responsible_troop = v.last_control_troop
              AND rc.completed_at_troop = v.completed_at_control_troop)) = 0
                                                                     AS historie_belegt_kt_datum,
    -- Gibt es eine abgebende Kontrolltrupp-Zeile, darf die Spalte nicht leer sein.
    (SELECT count(*) FROM v
      WHERE v.last_control_troop IS NULL
        AND EXISTS (
            SELECT 1 FROM public.record_changes rc JOIN public.troop t ON t.id = rc.responsible_troop
            WHERE rc.record_id = v.id AND rc.completed_at_troop IS NOT NULL
              AND t.is_control_troop)) = 0                           AS keine_verlorene_kt_historie,
    -- Jeder gueltige Zeitstempel im JSON landet in der Spalte.
    (SELECT count(*) FROM v
      WHERE v.gnss_measured_at IS NULL
        AND public.try_parse_timestamp(v.properties -> 'position' ->> 'start_measurement') IS NOT NULL
        AND v.properties -> 'position' ->> 'start_measurement' ~ '^[0-9]{4}-') = 0
                                                                     AS gnss_vollstaendig;

\echo ''
\echo '=== Abdeckung (informativ, kein Pass/Fail) ==============================='

SELECT count(*)                          AS ecken,
       count(completed_at_survey_troop)  AS abgabe_at,
       count(completed_at_control_troop) AS abgabe_kt,
       count(gnss_measured_at)           AS gnss_datum,
       count(*) FILTER (WHERE properties -> 'position' ->> 'start_measurement' IS NOT NULL
                          AND gnss_measured_at IS NULL)
                                         AS gnss_unlesbar
FROM public.view_records_details;
