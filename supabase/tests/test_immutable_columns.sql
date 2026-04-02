-- ============================================================================
-- TEST: guard_records_immutable_columns trigger
-- ============================================================================
-- Run inside a transaction so nothing is permanently changed:
--   psql -h <host> -p <port> -U postgres -d postgres -f test_immutable_columns.sql
--
-- Strategy: For each immutable column, attempt to change the value to
-- something different. We use values from a DIFFERENT record to satisfy
-- FK constraints. The trigger should block every attempt with ERRCODE 42501.
-- Editable columns (note, message, etc.) should succeed.
-- ============================================================================
BEGIN;
-- ── Helpers ─────────────────────────────────────────────────────────────────
-- Load two test records into a temp table BEFORE switching role,
-- because the authenticated role is subject to RLS and cannot SELECT.
CREATE TEMP TABLE _test_rows AS
SELECT *
FROM public.records
LIMIT 2;
DO $$
DECLARE rec1 record;
rec2 record;
err_code text;
err_msg text;
passed int := 0;
failed int := 0;
BEGIN
SELECT * INTO rec1
FROM _test_rows
LIMIT 1;
SELECT * INTO rec2
FROM _test_rows
WHERE id != rec1.id
LIMIT 1;
IF rec1.id IS NULL
OR rec2.id IS NULL THEN RAISE EXCEPTION 'Need at least 2 records to test. Found fewer.';
END IF;
-- Simulate an authenticated user.
-- We only set the JWT claims (which auth.role() reads) but keep the
-- actual Postgres role as postgres so RLS does not suppress the UPDATE.
-- The trigger checks auth.role(), not current_user, so this is sufficient.
-- Set BOTH GUC variants — different Supabase versions read different ones.
SET LOCAL request.jwt.claims TO '{"role": "authenticated"}';
SET LOCAL request.jwt.claim.role TO 'authenticated';
-- Verify auth.role() actually returns 'authenticated'
IF auth.role() IS DISTINCT
FROM 'authenticated' THEN RAISE EXCEPTION 'Setup error: auth.role() returned "%" instead of "authenticated". The trigger will not engage.',
    auth.role();
END IF;
-- Verify trigger exists on public.records
IF NOT EXISTS (
    SELECT 1
    FROM information_schema.triggers
    WHERE event_object_schema = 'public'
        AND event_object_table = 'records'
        AND trigger_name = 'guard_records_immutable_columns'
) THEN RAISE EXCEPTION 'Trigger guard_records_immutable_columns does NOT exist on public.records. Has the migration been applied?';
END IF;
RAISE NOTICE '──────────────────────────────────────────────';
RAISE NOTICE 'Testing with record %  (cluster %, plot %)',
rec1.id,
rec1.cluster_name,
rec1.plot_name;
RAISE NOTICE '──────────────────────────────────────────────';
-- ── Test each immutable column ──────────────────────────────────────
-- plot_id
BEGIN
UPDATE public.records
SET plot_id = gen_random_uuid()
WHERE id = rec1.id;
RAISE NOTICE 'FAIL: plot_id — update should have been blocked';
failed := failed + 1;
EXCEPTION
WHEN OTHERS THEN GET STACKED DIAGNOSTICS err_code = RETURNED_SQLSTATE,
err_msg = MESSAGE_TEXT;
IF err_code = '42501' THEN RAISE NOTICE 'PASS: plot_id — blocked (%)',
err_msg;
passed := passed + 1;
ELSE RAISE NOTICE 'FAIL: plot_id — wrong error: % %',
err_code,
err_msg;
failed := failed + 1;
END IF;
END;
-- cluster_id
BEGIN
UPDATE public.records
SET cluster_id = gen_random_uuid()
WHERE id = rec1.id;
RAISE NOTICE 'FAIL: cluster_id — update should have been blocked';
failed := failed + 1;
EXCEPTION
WHEN OTHERS THEN GET STACKED DIAGNOSTICS err_code = RETURNED_SQLSTATE,
err_msg = MESSAGE_TEXT;
IF err_code = '42501' THEN RAISE NOTICE 'PASS: cluster_id — blocked';
passed := passed + 1;
ELSE RAISE NOTICE 'FAIL: cluster_id — wrong error: % %',
err_code,
err_msg;
failed := failed + 1;
END IF;
END;
-- cluster_name
BEGIN
UPDATE public.records
SET cluster_name = COALESCE(rec1.cluster_name, 0) + 1
WHERE id = rec1.id;
RAISE NOTICE 'FAIL: cluster_name — update should have been blocked';
failed := failed + 1;
EXCEPTION
WHEN OTHERS THEN GET STACKED DIAGNOSTICS err_code = RETURNED_SQLSTATE,
err_msg = MESSAGE_TEXT;
IF err_code = '42501' THEN RAISE NOTICE 'PASS: cluster_name — blocked';
passed := passed + 1;
ELSE RAISE NOTICE 'FAIL: cluster_name — wrong error: % %',
err_code,
err_msg;
failed := failed + 1;
END IF;
END;
-- plot_name
BEGIN
UPDATE public.records
SET plot_name = (COALESCE(rec1.plot_name, 0::smallint) + 1)::smallint
WHERE id = rec1.id;
RAISE NOTICE 'FAIL: plot_name — update should have been blocked';
failed := failed + 1;
EXCEPTION
WHEN OTHERS THEN GET STACKED DIAGNOSTICS err_code = RETURNED_SQLSTATE,
err_msg = MESSAGE_TEXT;
IF err_code = '42501' THEN RAISE NOTICE 'PASS: plot_name — blocked';
passed := passed + 1;
ELSE RAISE NOTICE 'FAIL: plot_name — wrong error: % %',
err_code,
err_msg;
failed := failed + 1;
END IF;
END;
-- responsible_administration
BEGIN
UPDATE public.records
SET responsible_administration = gen_random_uuid()
WHERE id = rec1.id;
RAISE NOTICE 'FAIL: responsible_administration — update should have been blocked';
failed := failed + 1;
EXCEPTION
WHEN OTHERS THEN GET STACKED DIAGNOSTICS err_code = RETURNED_SQLSTATE,
err_msg = MESSAGE_TEXT;
IF err_code = '42501' THEN RAISE NOTICE 'PASS: responsible_administration — blocked';
passed := passed + 1;
ELSE RAISE NOTICE 'FAIL: responsible_administration — wrong error: % %',
err_code,
err_msg;
failed := failed + 1;
END IF;
END;
-- responsible_state
BEGIN
UPDATE public.records
SET responsible_state = gen_random_uuid()
WHERE id = rec1.id;
RAISE NOTICE 'FAIL: responsible_state — update should have been blocked';
failed := failed + 1;
EXCEPTION
WHEN OTHERS THEN GET STACKED DIAGNOSTICS err_code = RETURNED_SQLSTATE,
err_msg = MESSAGE_TEXT;
IF err_code = '42501' THEN RAISE NOTICE 'PASS: responsible_state — blocked';
passed := passed + 1;
ELSE RAISE NOTICE 'FAIL: responsible_state — wrong error: % %',
err_code,
err_msg;
failed := failed + 1;
END IF;
END;
-- is_training
BEGIN
UPDATE public.records
SET is_training = CASE
        WHEN rec1.is_training IS TRUE THEN FALSE
        ELSE TRUE
    END
WHERE id = rec1.id;
RAISE NOTICE 'FAIL: is_training — update should have been blocked';
failed := failed + 1;
EXCEPTION
WHEN OTHERS THEN GET STACKED DIAGNOSTICS err_code = RETURNED_SQLSTATE,
err_msg = MESSAGE_TEXT;
IF err_code = '42501' THEN RAISE NOTICE 'PASS: is_training — blocked';
passed := passed + 1;
ELSE RAISE NOTICE 'FAIL: is_training — wrong error: % %',
err_code,
err_msg;
failed := failed + 1;
END IF;
END;
-- previous_position_data
BEGIN
UPDATE public.records
SET previous_position_data = '{"test": true}'::jsonb
WHERE id = rec1.id;
RAISE NOTICE 'FAIL: previous_position_data — update should have been blocked';
failed := failed + 1;
EXCEPTION
WHEN OTHERS THEN GET STACKED DIAGNOSTICS err_code = RETURNED_SQLSTATE,
err_msg = MESSAGE_TEXT;
IF err_code = '42501' THEN RAISE NOTICE 'PASS: previous_position_data — blocked';
passed := passed + 1;
ELSE RAISE NOTICE 'FAIL: previous_position_data — wrong error: % %',
err_code,
err_msg;
failed := failed + 1;
END IF;
END;
-- cluster
BEGIN
UPDATE public.records
SET cluster = '{"test": true}'::jsonb
WHERE id = rec1.id;
RAISE NOTICE 'FAIL: cluster — update should have been blocked';
failed := failed + 1;
EXCEPTION
WHEN OTHERS THEN GET STACKED DIAGNOSTICS err_code = RETURNED_SQLSTATE,
err_msg = MESSAGE_TEXT;
IF err_code = '42501' THEN RAISE NOTICE 'PASS: cluster — blocked';
passed := passed + 1;
ELSE RAISE NOTICE 'FAIL: cluster — wrong error: % %',
err_code,
err_msg;
failed := failed + 1;
END IF;
END;
-- previous_properties
BEGIN
UPDATE public.records
SET previous_properties = '{"test": true}'::jsonb
WHERE id = rec1.id;
RAISE NOTICE 'FAIL: previous_properties — update should have been blocked';
failed := failed + 1;
EXCEPTION
WHEN OTHERS THEN GET STACKED DIAGNOSTICS err_code = RETURNED_SQLSTATE,
err_msg = MESSAGE_TEXT;
IF err_code = '42501' THEN RAISE NOTICE 'PASS: previous_properties — blocked';
passed := passed + 1;
ELSE RAISE NOTICE 'FAIL: previous_properties — wrong error: % %',
err_code,
err_msg;
failed := failed + 1;
END IF;
END;
-- ── Test editable columns (should succeed) ─────────────────────────
BEGIN
UPDATE public.records
SET note = 'test_immutable_guard'
WHERE id = rec1.id;
RAISE NOTICE 'PASS: note — update allowed';
passed := passed + 1;
EXCEPTION
WHEN OTHERS THEN GET STACKED DIAGNOSTICS err_code = RETURNED_SQLSTATE,
err_msg = MESSAGE_TEXT;
RAISE NOTICE 'FAIL: note — should be editable: % %',
err_code,
err_msg;
failed := failed + 1;
END;
BEGIN
UPDATE public.records
SET message = 'test_immutable_guard'
WHERE id = rec1.id;
RAISE NOTICE 'PASS: message — update allowed';
passed := passed + 1;
EXCEPTION
WHEN OTHERS THEN GET STACKED DIAGNOSTICS err_code = RETURNED_SQLSTATE,
err_msg = MESSAGE_TEXT;
RAISE NOTICE 'FAIL: message — should be editable: % %',
err_code,
err_msg;
failed := failed + 1;
END;
BEGIN
UPDATE public.records
SET properties = rec1.properties || '{"_test": true}'::jsonb
WHERE id = rec1.id;
RAISE NOTICE 'PASS: properties — update allowed';
passed := passed + 1;
EXCEPTION
WHEN OTHERS THEN GET STACKED DIAGNOSTICS err_code = RETURNED_SQLSTATE,
err_msg = MESSAGE_TEXT;
RAISE NOTICE 'FAIL: properties — should be editable: % %',
err_code,
err_msg;
failed := failed + 1;
END;
-- ── Summary ─────────────────────────────────────────────────────────
RAISE NOTICE '';
RAISE NOTICE '══════════════════════════════════════════════';
RAISE NOTICE '  PASSED: %   FAILED: %   TOTAL: %',
passed,
failed,
passed + failed;
RAISE NOTICE '══════════════════════════════════════════════';
IF failed > 0 THEN RAISE EXCEPTION '% test(s) failed!',
failed;
END IF;
END;
$$;
-- Roll back everything — no data was changed
ROLLBACK;