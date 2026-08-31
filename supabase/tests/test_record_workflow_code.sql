-- ============================================================================
-- TEST: public.record_workflow_code() — Wahrheitstabelle des Eckenstatus
-- ============================================================================
-- Prueft jede Stufe aus TFM-Documentation Issue #14 sowie die Grenzfaelle, in
-- denen sich zwei Regeln ueberlappen.
--
-- SAFE BY DESIGN (auch gegen Produktion): der Test schreibt nichts. Die
-- Testzeilen entstehen ueber jsonb_populate_record() als reine
-- Speicher-Composites — kein INSERT, kein Trigger, keine Sequenz. Dadurch ist
-- er ausserdem unabhaengig davon, welche Spalten public.records sonst noch hat.
--
-- Die Historien-Merkmale werden hier direkt gesetzt. Dass sie aus
-- public.record_changes korrekt entstehen, prueft
-- test_record_workflow_code_history.sql.
--
-- Run:  psql "$DATABASE_URL" -f test_record_workflow_code.sql
-- ============================================================================
\set ON_ERROR_STOP on
\pset pager off
\timing off

\echo ''
\echo '=== record_workflow_code: Wahrheitstabelle ================================'

WITH faelle(beschreibung, felder, is_control_troop, repeated_survey, seen_control_troop, returned_by_administration, erwartet) AS (
    VALUES
        ('nichts zugewiesen',
         '{}'::jsonb,                                                                                    false, false, false, false, NULL),
        ('10 Vorarbeiten BIL',
         '{"responsible_administration":"00000000-0000-0000-0000-0000000000a1"}'::jsonb,                 false, false, false, false, 10),
        ('20 Vorarbeiten LIL',
         '{"responsible_state":"00000000-0000-0000-0000-0000000000b1"}'::jsonb,                          false, false, false, false, 20),
        ('31 Aufnahme im Feld AT, Erstaufnahme',
         '{"responsible_troop":"00000000-0000-0000-0000-0000000000c1"}'::jsonb,                          false, false, false, false, 31),
        ('32 Aufnahme im Feld AT, Wiederholung',
         '{"responsible_troop":"00000000-0000-0000-0000-0000000000c1"}'::jsonb,                          false, true,  false, false, 32),
        ('41 Qualitaetskontrolle LIL, nach Erstaufnahme',
         '{"completed_at_troop":"2026-05-01T10:00:00Z"}'::jsonb,                                         false, false, false, false, 41),
        ('42 Qualitaetskontrolle LIL, nach Korrektur',
         '{"completed_at_troop":"2026-05-01T10:00:00Z"}'::jsonb,                                         false, true,  false, false, 42),
        ('43 Qualitaetskontrolle LIL, nach Kontrolltrupp',
         '{"completed_at_troop":"2026-05-01T10:00:00Z"}'::jsonb,                                         false, true,  true,  false, 43),
        ('44 Qualitaetskontrolle LIL, nach Rueckgabe BIL',
         '{"completed_at_troop":"2026-05-01T10:00:00Z"}'::jsonb,                                         false, true,  true,  true,  44),
        ('50 Kontrolltrupp im Feld',
         '{"responsible_troop":"00000000-0000-0000-0000-0000000000c2"}'::jsonb,                          true,  false, false, false, 50),
        ('50 schlaegt 43 (KT noch im Feld, nach Abgabe AT)',
         '{"responsible_troop":"00000000-0000-0000-0000-0000000000c2","completed_at_troop":"2026-05-01T10:00:00Z"}'::jsonb,
                                                                                                         true,  true,  true,  false, 50),
        ('60 Qualitaetskontrolle BIL',
         '{"completed_at_troop":"2026-05-01T10:00:00Z","completed_at_state":"2026-06-01T10:00:00Z"}'::jsonb,
                                                                                                         false, false, false, false, 60),
        ('60 schlaegt 50 (LIL hat abgenommen)',
         '{"responsible_troop":"00000000-0000-0000-0000-0000000000c2","completed_at_state":"2026-06-01T10:00:00Z"}'::jsonb,
                                                                                                         true,  false, false, false, 60),
        ('70 Akzeptiert BIL',
         '{"completed_at_state":"2026-06-01T10:00:00Z","completed_at_administration":"2026-07-01T10:00:00Z"}'::jsonb,
                                                                                                         false, false, false, false, 70)
), ergebnis AS (
    SELECT
        f.beschreibung,
        f.erwartet::smallint AS erwartet,
        public.record_workflow_code(
            rec                        => jsonb_populate_record(NULL::public.records, f.felder),
            is_control_troop           => f.is_control_troop,
            repeated_survey            => f.repeated_survey,
            seen_control_troop         => f.seen_control_troop,
            returned_by_administration => f.returned_by_administration
        ) AS ist
    FROM faelle f
)
SELECT
    beschreibung,
    erwartet,
    ist,
    CASE WHEN ist IS NOT DISTINCT FROM erwartet THEN 'ok' ELSE 'FEHLGESCHLAGEN' END AS ergebnis
FROM ergebnis
ORDER BY erwartet NULLS FIRST, beschreibung;

\echo ''
\echo '=== Jeder Code hat einen Eintrag in lookup.lookup_workflow_status ========='

SELECT
    c.code,
    l.name_de,
    l.description_de,
    CASE WHEN l.code IS NULL THEN 'FEHLT' ELSE 'ok' END AS ergebnis
FROM (VALUES (10),(20),(31),(32),(41),(42),(43),(44),(50),(60),(70)) AS c(code)
LEFT JOIN lookup.lookup_workflow_status l ON l.code = c.code
ORDER BY c.code;

\echo ''
\echo '=== View-Zustand ========================================================='

SELECT
    (SELECT count(*) FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'view_records_details'
        AND column_name = 'workflow_code') = 1                       AS spalte_vorhanden,
    (SELECT reloptions FROM pg_class WHERE relname = 'view_records_details')
        @> ARRAY['security_invoker=true']                            AS view_ist_security_invoker,
    -- view_record_workflow_history MUSS ohne security_invoker laufen, sonst
    -- haengt der Statuscode von den RLS-Rechten des Betrachters ab.
    COALESCE((SELECT reloptions FROM pg_class WHERE relname = 'view_record_workflow_history'), '{}')
        @> ARRAY['security_invoker=true']                            AS historie_faelschlich_invoker,
    (SELECT count(*) FROM public.records)
        = (SELECT count(*) FROM public.view_records_details)         AS zeilenzahl_unveraendert;
