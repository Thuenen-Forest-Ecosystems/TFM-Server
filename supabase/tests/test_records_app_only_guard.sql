-- ============================================================================
-- Test: guard_records_app_only_columns (20261106000000)        DRY RUN
-- ============================================================================
-- Installs the migration inside one transaction (if not yet present), runs
-- every case in its own subtransaction and ROLLs BACK at the end — nothing
-- is persisted, even on a database where the migration is not applied.
--
-- PostgREST is simulated per case: SET ROLE + request.jwt.claims +
-- request.headers (the GUC PostgREST fills from the HTTP headers).
--
-- psql variables (override with -v):
--   troop_user / troop_record  normal troop member + one of their records
--   root_user  / root_record   root-org member ("Thünen") + record
-- Fails (exit 3) when any case deviates from its expectation.
-- ============================================================================
\set ON_ERROR_STOP on
\if :{?troop_user} \else \set troop_user 98fb8fd9-49c6-4b62-b4e4-6feb25cef2d2 \endif
\if :{?troop_record} \else \set troop_record 1a371567-c002-43a6-9d40-04e932a606fe \endif
\if :{?root_user} \else \set root_user b7a83082-dcc2-4dff-85cd-529363a7be8b \endif
\if :{?root_record} \else \set root_record f7a2ed08-3bd2-49f7-97d4-06a7f81ade7a \endif

BEGIN;

SELECT to_regprocedure('public.guard_records_app_only_columns()') IS NULL AS need_install \gset
\if :need_install
\echo '(migration not installed — installing inside the test transaction)'
\ir ../migrations/20261106000000_guard_records_app_only_columns.sql
\endif

SELECT set_config('t.troop_user',   :'troop_user',   true),
       set_config('t.troop_record', :'troop_record', true),
       set_config('t.root_user',    :'root_user',    true),
       set_config('t.root_record',  :'root_record',  true) \gset

CREATE TEMP TABLE results (n serial, mode text, persona text, header text, change text,
                           expected text, actual text, ok boolean, detail text) ON COMMIT DROP;
GRANT ALL ON results TO PUBLIC;

-- One case: switch identity, run the UPDATE, record the outcome, undo the case.
CREATE FUNCTION pg_temp.run_case(p_mode text, p_persona text, p_header text,
                                 p_change text, p_set text, p_expected text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_user   text;
    v_record text;
    v_role   text;
    v_rows   int;
    v_logs   int;
    v_actual text;
    v_detail text;
BEGIN
    v_user := CASE p_persona
        WHEN 'troop' THEN current_setting('t.troop_user')
        WHEN 'root'  THEN current_setting('t.root_user') END;
    v_record := CASE WHEN p_persona = 'troop' THEN current_setting('t.troop_record')
                     ELSE current_setting('t.root_record') END;
    v_role := CASE p_persona WHEN 'service' THEN 'service_role' WHEN 'anon' THEN 'anon'
                             WHEN 'postgres' THEN NULL ELSE 'authenticated' END;
    BEGIN
        UPDATE records_guard.settings SET mode = p_mode;
        PERFORM set_config('request.jwt.claims',
            json_build_object('sub', v_user, 'role', coalesce(v_role, 'postgres'))::text, true);
        PERFORM set_config('request.jwt.claim.sub', coalesce(v_user, ''), true);
        PERFORM set_config('request.jwt.claim.role', coalesce(v_role, ''), true);
        PERFORM set_config('request.headers',
            CASE WHEN p_header IS NULL THEN '{"user-agent":"curl/8.7.1"}'
                 ELSE json_build_object('x-client-info', p_header, 'user-agent', 'Dart/3.8')::text END, true);
        IF v_role IS NOT NULL THEN
            EXECUTE format('SET LOCAL ROLE %I', v_role);
        END IF;
        BEGIN
            EXECUTE format('UPDATE public.records SET %s WHERE id = %L', p_set, v_record);
            GET DIAGNOSTICS v_rows = ROW_COUNT;
            v_actual := CASE WHEN v_rows = 0 THEN 'NO_ROW' ELSE 'OK' END;
        EXCEPTION WHEN insufficient_privilege THEN
            v_actual := 'BLOCK';
            v_detail := SQLERRM;
        END;
        RESET ROLE;
        SELECT count(*) INTO v_logs FROM records_guard.write_log WHERE record_id = v_record::uuid;
        IF p_mode = 'log' THEN
            v_detail := coalesce(v_detail || ' / ', '') || 'log rows: ' || v_logs ||
                coalesce(' is_app=' || (SELECT is_app::text FROM records_guard.write_log
                                         WHERE record_id = v_record::uuid ORDER BY id DESC LIMIT 1), '');
            IF v_actual = 'OK' THEN
                v_actual := 'OK+LOG' || v_logs;
            END IF;
        END IF;
        RAISE EXCEPTION 'undo_case';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM <> 'undo_case' THEN RAISE; END IF;
    END;
    INSERT INTO results (mode, persona, header, change, expected, actual, ok, detail)
    VALUES (p_mode, p_persona, coalesce(p_header, '—'), p_change, p_expected, v_actual,
            v_actual = p_expected, v_detail);
END;
$$;


\o /dev/null
SET client_min_messages = warning;
-- ── enforce: protected columns ──────────────────────────────────────────────
SELECT pg_temp.run_case('enforce','troop', NULL, 'properties',            $$properties = properties || '{"_guard_test":1}'::jsonb$$, 'BLOCK');
SELECT pg_temp.run_case('enforce','troop', 'supabase-flutter/2.10.3', 'properties',            $$properties = properties || '{"_guard_test":1}'::jsonb$$, 'OK');
SELECT pg_temp.run_case('enforce','troop', 'supabase-dart/2.10.0', 'properties', $$properties = properties || '{"_guard_test":1}'::jsonb$$, 'BLOCK');
SELECT pg_temp.run_case('enforce','troop', 'supabase-js-web/2.45.0', 'properties', $$properties = properties || '{"_guard_test":1}'::jsonb$$, 'BLOCK');
SELECT pg_temp.run_case('enforce','troop', NULL, 'completed_at_troop',    'completed_at_troop = now()', 'BLOCK');
SELECT pg_temp.run_case('enforce','troop', 'supabase-flutter/2.10.3', 'completed_at_troop',    'completed_at_troop = now()', 'OK');
SELECT pg_temp.run_case('enforce','troop', NULL, 'validation_errors',     'validation_errors = ''[]''', 'BLOCK');
SELECT pg_temp.run_case('enforce','troop', NULL, 'plausibility_errors',   'plausibility_errors = ''[]''', 'BLOCK');
SELECT pg_temp.run_case('enforce','troop', NULL, 'schema_id_validated_by','schema_id_validated_by = gen_random_uuid()', 'BLOCK');
SELECT pg_temp.run_case('enforce','troop', 'supabase-flutter/2.10.3', 'App-Speichern komplett',
    'properties = properties || ''{"_guard_test":1}''::jsonb, schema_id_validated_by = schema_id, local_updated_at = now(), completed_at_troop = now(), validation_errors = ''[]'', plausibility_errors = ''[]''', 'OK');
-- ── enforce: columns that must stay writable via the API ───────────────────
SELECT pg_temp.run_case('enforce','troop', NULL, 'note',                  'note = ''API-Test''', 'OK');
SELECT pg_temp.run_case('enforce','troop', NULL, 'is_to_be_recorded',     'is_to_be_recorded = NOT coalesce(is_to_be_recorded, false)', 'OK');
SELECT pg_temp.run_case('enforce','troop', NULL, 'responsible_read_only_troop', 'responsible_read_only_troop = NULL', 'OK');
SELECT pg_temp.run_case('enforce','root',  NULL, 'responsible_troop',     'responsible_troop = NULL', 'OK');
SELECT pg_temp.run_case('enforce','root',  NULL, 'completed_at_state',    'completed_at_state = now()', 'OK');
SELECT pg_temp.run_case('enforce','root',  NULL, 'completed_at_administration', 'completed_at_administration = now()', 'OK');
SELECT pg_temp.run_case('enforce','troop', NULL, 'Vollzeile unverändert + note',
    'properties = properties, completed_at_troop = completed_at_troop, validation_errors = validation_errors, plausibility_errors = plausibility_errors, schema_id_validated_by = schema_id_validated_by, note = ''x''', 'OK');
-- ── enforce: other identities ──────────────────────────────────────────────
SELECT pg_temp.run_case('enforce','root',  NULL, 'properties',            $$properties = properties || '{"_guard_test":1}'::jsonb$$, 'BLOCK');
SELECT pg_temp.run_case('enforce','root',  'supabase-flutter/2.10.3', 'properties',            $$properties = properties || '{"_guard_test":1}'::jsonb$$, 'OK');
SELECT pg_temp.run_case('enforce','service', NULL, 'properties',          $$properties = properties || '{"_guard_test":1}'::jsonb$$, 'OK');
SELECT pg_temp.run_case('enforce','postgres', NULL, 'properties',         $$properties = properties || '{"_guard_test":1}'::jsonb$$, 'OK');
SELECT pg_temp.run_case('enforce','anon',  NULL, 'properties',            $$properties = properties || '{"_guard_test":1}'::jsonb$$, 'NO_ROW');
-- ── log mode: never blocks, records who wrote ─────────────────────────────
SELECT pg_temp.run_case('log','troop', NULL, 'properties',                $$properties = properties || '{"_guard_test":1}'::jsonb$$, 'OK+LOG1');
SELECT pg_temp.run_case('log','troop', 'supabase-flutter/2.10.3', 'properties',                $$properties = properties || '{"_guard_test":1}'::jsonb$$, 'OK+LOG1');
SELECT pg_temp.run_case('log','troop', NULL, 'note',                      'note = ''API-Test''', 'OK+LOG0');

\o
RESET client_min_messages;
\pset footer off
SELECT n, mode, persona, header, change, expected, actual,
       CASE WHEN ok THEN 'ok' ELSE '*** FAIL ***' END AS result, detail
FROM results ORDER BY n;

SELECT count(*) FILTER (WHERE NOT ok) AS failures, count(*) AS cases,
       count(*) FILTER (WHERE NOT ok) > 0 AS has_failures FROM results \gset
\echo :failures 'Abweichung(en) von' :cases 'Fällen'

ROLLBACK;

\if :has_failures
\echo 'TEST FAILED'
\quit 3
\endif
\echo 'TEST PASSED (alles zurückgerollt)'
