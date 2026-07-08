-- ============================================================================
-- TEST: guard_records_tree_preservation trigger
-- ============================================================================
-- Run inside a transaction so nothing is permanently changed:
--   psql -h <host> -p <port> -U postgres -d postgres -f test_tree_preservation.sql
--
-- Strategy: pick one record, plant a synthetic tree array with two archive
-- trees (UUID id) and one app-added tree (no id), then verify as an
-- "authenticated" user that:
--   1. removing an archive tree → it is restored + logged,
--   2. removing the whole tree array → all archive trees restored,
--   3. removing only the app-added tree → allowed, nothing restored,
--   4. flagging a tree _deprecated (keeping it in the array) → untouched,
--   5. app.skip_tree_guard = 'on' → guard bypassed.
-- ============================================================================
BEGIN;
-- Load a test record BEFORE switching claims (RLS would hide it otherwise).
CREATE TEMP TABLE _test_rows AS
SELECT *
FROM public.records
LIMIT 1;
DO $$
DECLARE rec1 record;
uuid_a text := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
uuid_b text := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
seeded jsonb;
result jsonb;
log_count int;
passed int := 0;
failed int := 0;
BEGIN
SELECT * INTO rec1
FROM _test_rows
LIMIT 1;
IF rec1.id IS NULL THEN RAISE EXCEPTION 'Need at least 1 record to test.';
END IF;
-- Simulate an authenticated user (see test_immutable_columns.sql).
SET LOCAL request.jwt.claims TO '{"role": "authenticated"}';
SET LOCAL request.jwt.claim.role TO 'authenticated';
IF auth.role() IS DISTINCT
FROM 'authenticated' THEN RAISE EXCEPTION 'Setup error: auth.role() returned "%" instead of "authenticated".',
auth.role();
END IF;
-- Immutable-column / client guards would reject this synthetic UPDATE, so
-- disable the unrelated guards for the test transaction only.
PERFORM set_config('app.skip_updated_by', 'on', true);
PERFORM set_config('app.skip_updated_at', 'on', true);
-- Seed: two archive trees + one app-added tree (no id)
seeded := jsonb_build_object(
    'tree',
    jsonb_build_array(
        jsonb_build_object('id', uuid_a, 'tree_number', 1, 'dbh', 250),
        jsonb_build_object('id', uuid_b, 'tree_number', 2, 'dbh', 300),
        jsonb_build_object('tree_number', 3, 'dbh', 120)
    )
);
UPDATE public.records
SET properties = seeded
WHERE id = rec1.id;
-- ── Test 1: dropping an archive tree gets restored ─────────────────────────
UPDATE public.records
SET properties = jsonb_build_object(
        'tree',
        jsonb_build_array(
            jsonb_build_object('id', uuid_a, 'tree_number', 1, 'dbh', 250)
        )
    )
WHERE id = rec1.id;
SELECT properties INTO result
FROM public.records
WHERE id = rec1.id;
IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(result -> 'tree') e
    WHERE e.value ->> 'id' = uuid_b
) THEN passed := passed + 1;
RAISE NOTICE 'PASS: removed archive tree was restored';
ELSE failed := failed + 1;
RAISE WARNING 'FAIL: removed archive tree was NOT restored: %',
result;
END IF;
SELECT count(*) INTO log_count
FROM public.record_tree_guard_log
WHERE record_id = rec1.id
    AND uuid_b = ANY(restored_tree_ids);
IF log_count = 1 THEN passed := passed + 1;
RAISE NOTICE 'PASS: restoration was logged';
ELSE failed := failed + 1;
RAISE WARNING 'FAIL: expected 1 log entry for %, found %',
uuid_b,
log_count;
END IF;
-- ── Test 2: dropping the whole tree array restores all archive trees ───────
UPDATE public.records
SET properties = seeded
WHERE id = rec1.id;
UPDATE public.records
SET properties = '{}'::jsonb
WHERE id = rec1.id;
SELECT properties INTO result
FROM public.records
WHERE id = rec1.id;
IF (
    SELECT count(*)
    FROM jsonb_array_elements(result -> 'tree') e
    WHERE e.value ->> 'id' IN (uuid_a, uuid_b)
) = 2 THEN passed := passed + 1;
RAISE NOTICE 'PASS: emptied properties got both archive trees restored';
ELSE failed := failed + 1;
RAISE WARNING 'FAIL: archive trees not restored after wiping properties: %',
result;
END IF;
-- ── Test 3: app-added tree (no id) may be deleted ───────────────────────────
UPDATE public.records
SET properties = seeded
WHERE id = rec1.id;
UPDATE public.records
SET properties = jsonb_build_object(
        'tree',
        jsonb_build_array(
            jsonb_build_object('id', uuid_a, 'tree_number', 1, 'dbh', 250),
            jsonb_build_object('id', uuid_b, 'tree_number', 2, 'dbh', 300)
        )
    )
WHERE id = rec1.id;
SELECT properties INTO result
FROM public.records
WHERE id = rec1.id;
IF (
    SELECT count(*)
    FROM jsonb_array_elements(result -> 'tree')
) = 2 THEN passed := passed + 1;
RAISE NOTICE 'PASS: app-added tree (no archive id) stayed deleted';
ELSE failed := failed + 1;
RAISE WARNING 'FAIL: expected 2 trees after deleting the app-added one: %',
result;
END IF;
-- ── Test 4: _deprecated flag change is not a deletion ───────────────────────
UPDATE public.records
SET properties = jsonb_build_object(
        'tree',
        jsonb_build_array(
            jsonb_build_object('id', uuid_a, 'tree_number', 1, 'dbh', 250, '_deprecated', true),
            jsonb_build_object('id', uuid_b, 'tree_number', 2, 'dbh', 300)
        )
    )
WHERE id = rec1.id;
SELECT properties INTO result
FROM public.records
WHERE id = rec1.id;
IF (
    SELECT count(*)
    FROM jsonb_array_elements(result -> 'tree')
) = 2
AND (
    SELECT (e.value ->> '_deprecated')::boolean
    FROM jsonb_array_elements(result -> 'tree') e
    WHERE e.value ->> 'id' = uuid_a
) THEN passed := passed + 1;
RAISE NOTICE 'PASS: _deprecated flag update passed through untouched';
ELSE failed := failed + 1;
RAISE WARNING 'FAIL: _deprecated flag update was altered: %',
result;
END IF;
-- ── Test 5: skip flag bypasses the guard ────────────────────────────────────
PERFORM set_config('app.skip_tree_guard', 'on', true);
UPDATE public.records
SET properties = '{}'::jsonb
WHERE id = rec1.id;
SELECT properties INTO result
FROM public.records
WHERE id = rec1.id;
PERFORM set_config('app.skip_tree_guard', '', true);
IF result -> 'tree' IS NULL THEN passed := passed + 1;
RAISE NOTICE 'PASS: app.skip_tree_guard=on bypassed the guard';
ELSE failed := failed + 1;
RAISE WARNING 'FAIL: guard ran despite app.skip_tree_guard=on: %',
result;
END IF;
-- ── Summary ─────────────────────────────────────────────────────────────────
RAISE NOTICE '────────────────────────────────';
RAISE NOTICE 'Tree preservation tests: % passed, % failed',
passed,
failed;
IF failed > 0 THEN RAISE EXCEPTION '% test(s) failed',
failed;
END IF;
END;
$$;
ROLLBACK;
