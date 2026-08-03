-- ============================================================================
-- DRY-RUN TEST: records writability matrix — which columns can which role write?
-- ============================================================================
-- Probes every updatable column of public.records as every relevant persona
-- (troop member, read-only-group member, admin, root-org member, outsider,
-- anon, ti_read, service_role, db owner), each authenticated persona both
-- with the Flutter app's x-client-info header and with a plain API client
-- header. Faithfully replicates what PostgREST does per request:
--   SET LOCAL ROLE + request.jwt.claims/claim.* + request.headers GUCs,
-- so RLS policies, table grants AND guard triggers are genuinely exercised.
--
-- SAFE BY DESIGN (runnable against production):
--   * exactly one BEGIN below and one ROLLBACK at the end — no COMMIT anywhere
--   * every single probe is additionally rolled back via a forced savepoint
--     rollback (custom SQLSTATE WM999), so probes cannot influence each other
--   * fixtures (test users/orgs/troops) only exist inside the transaction
--   * target record: prefers is_training = true so no real record is touched
--
-- Run:  ./run_writability_matrix.sh [--remote]     (see runner next to this file)
-- ============================================================================
\set ON_ERROR_STOP on
\pset pager off
\timing off

BEGIN;

\echo ''
\echo '=== Environment ==========================================================='
SELECT current_database() AS database,
       current_setting('server_version') AS pg_version,
       session_user,
       now() AS at;

\echo '=== Active (non-internal) triggers on public.records ======================'
SELECT tgname AS trigger_name,
       CASE tgenabled WHEN 'O' THEN 'enabled' WHEN 'D' THEN 'DISABLED'
            WHEN 'R' THEN 'replica-only' WHEN 'A' THEN 'always' END AS state,
       pg_get_triggerdef(oid) LIKE '%BEFORE%' AS is_before
FROM pg_trigger
WHERE tgrelid = 'public.records'::regclass AND NOT tgisinternal
ORDER BY tgname;

\echo '=== RLS policies on public.records ========================================'
SELECT polname AS policy,
       CASE polcmd WHEN 'r' THEN 'SELECT' WHEN 'a' THEN 'INSERT'
            WHEN 'w' THEN 'UPDATE' WHEN 'd' THEN 'DELETE' WHEN '*' THEN 'ALL' END AS cmd,
       polroles::regrole[] AS roles
FROM pg_policy
WHERE polrelid = 'public.records'::regclass
ORDER BY polcmd, polname;

-- ── Result / control tables (ordinary tables: created inside the transaction,
--    gone after ROLLBACK; avoids pg_temp ACL edge cases across SET ROLE) ─────
CREATE TABLE public._wm_results (
    persona     text NOT NULL,
    header      text NOT NULL,
    column_name text NOT NULL,
    outcome     text NOT NULL,   -- WRITABLE | WRITABLE_CONSTRAINT | BLOCKED_SILENT_RLS | BLOCKED_ERROR | SKIPPED
    sqlstate    text,
    detail      text
);
CREATE TABLE public._wm_probes (
    ord         int PRIMARY KEY,
    column_name text NOT NULL,
    stmt        text,            -- NULL = probe skipped (no distinct value available)
    note        text
);
CREATE TABLE public._wm_personas (
    ord          int PRIMARY KEY,
    persona      text NOT NULL,
    header       text NOT NULL,  -- 'app' | 'api' | 'db'
    pg_role      text NOT NULL,  -- 'none' = session user (db owner)
    uid          uuid,
    jwt_role     text,
    header_value text
);
CREATE TABLE public._wm_meta (key text PRIMARY KEY, val text);
GRANT SELECT, INSERT ON public._wm_results TO PUBLIC;
GRANT SELECT ON public._wm_probes, public._wm_personas, public._wm_meta TO PUBLIC;

-- ── Fixtures + probe statements ─────────────────────────────────────────────
DO $fixtures$
DECLARE
    rec1 public.records%ROWTYPE;
    v_troop_org uuid;
    v_fix_troop uuid;          -- extra troop in the SAME org as responsible_troop
    v_ctrl_org uuid;
    v_ctrl_troop uuid;
    v_root_org uuid;
    v_out_org uuid;
    v_u_troop   uuid := gen_random_uuid();
    v_u_control uuid := gen_random_uuid();
    v_u_admin   uuid := gen_random_uuid();
    v_u_root    uuid := gen_random_uuid();
    v_u_out     uuid := gen_random_uuid();
    v_free_plot uuid;
    v_other_cluster uuid;
    v_other_schema uuid;
    v_other_rc uuid;
    v_new_cluster_name int;
    v_new_plot_name int;
    v_ins_plot uuid;
    staged_ctrl boolean := false;
    staged_completed boolean := false;
    c record;
    v_expr text;
    v_ord int := 100;
BEGIN
    -- Target record: prefer a training record so production data is never locked
    SELECT * INTO rec1
    FROM public.records
    WHERE responsible_troop IS NOT NULL
    ORDER BY (is_training IS TRUE) DESC, created_at
    LIMIT 1;
    IF rec1.id IS NULL THEN
        RAISE EXCEPTION 'Setup: need at least one record with responsible_troop set.';
    END IF;

    SELECT organization_id INTO v_troop_org FROM public.troop WHERE id = rec1.responsible_troop;
    IF v_troop_org IS NULL THEN
        RAISE EXCEPTION 'Setup: responsible_troop % has no organization.', rec1.responsible_troop;
    END IF;

    -- Extra troop in the same org (target value for responsible_troop probes,
    -- keeps the RLS WITH CHECK satisfied for the troop persona)
    INSERT INTO public.troop (name, organization_id)
    VALUES ('_wm_fixture_troop', v_troop_org) RETURNING id INTO v_fix_troop;

    -- Read-only group (troop.is_read_only): reuse the record's, else stage a
    -- fixture group in a SEPARATE org (so the readonly persona does not also
    -- match the troop branch)
    IF rec1.responsible_read_only_troop IS NOT NULL THEN
        v_ctrl_troop := rec1.responsible_read_only_troop;
        SELECT organization_id INTO v_ctrl_org FROM public.troop WHERE id = v_ctrl_troop;
    ELSE
        INSERT INTO public.organizations (name, type) VALUES ('_wm_readonly_org', 'provider')
        RETURNING id INTO v_ctrl_org;
        INSERT INTO public.troop (name, organization_id, is_read_only)
        VALUES ('_wm_readonly_troop', v_ctrl_org, true) RETURNING id INTO v_ctrl_troop;
        UPDATE public.records SET responsible_read_only_troop = v_ctrl_troop WHERE id = rec1.id;
        staged_ctrl := true;
    END IF;
    -- Stage completed_at_troop deliberately: the removed control-troop UPDATE
    -- branch (20260709120000) was gated on it, so probing in this state proves
    -- read-only groups stay blocked even where control troops used to write.
    IF rec1.completed_at_troop IS NULL AND rec1.responsible_troop IS NOT NULL THEN
        UPDATE public.records SET completed_at_troop = now() WHERE id = rec1.id;
        staged_completed := true;
    END IF;
    SELECT * INTO rec1 FROM public.records WHERE id = rec1.id;  -- reload after staging

    -- Root org (reuse if present), outsider org (always fresh, unrelated)
    SELECT id INTO v_root_org FROM public.organizations
    WHERE type = 'root' AND NOT deleted LIMIT 1;
    IF v_root_org IS NULL THEN
        INSERT INTO public.organizations (name, type) VALUES ('_wm_root_org', 'root')
        RETURNING id INTO v_root_org;
    END IF;
    INSERT INTO public.organizations (name, type) VALUES ('_wm_outsider_org', 'provider')
    RETURNING id INTO v_out_org;

    -- Fixture users (auth.users -> users_profile -> users_permissions)
    INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, created_at, updated_at)
    VALUES
        ('00000000-0000-0000-0000-000000000000', v_u_troop,   'authenticated', 'authenticated', 'wm_troop@writability.test',    '', now(), now()),
        ('00000000-0000-0000-0000-000000000000', v_u_control, 'authenticated', 'authenticated', 'wm_readonly@writability.test', '', now(), now()),
        ('00000000-0000-0000-0000-000000000000', v_u_admin,   'authenticated', 'authenticated', 'wm_admin@writability.test',    '', now(), now()),
        ('00000000-0000-0000-0000-000000000000', v_u_root,    'authenticated', 'authenticated', 'wm_root@writability.test',     '', now(), now()),
        ('00000000-0000-0000-0000-000000000000', v_u_out,     'authenticated', 'authenticated', 'wm_outsider@writability.test', '', now(), now());
    INSERT INTO public.users_profile (id, email, is_admin) VALUES
        (v_u_troop,   'wm_troop@writability.test',    false),
        (v_u_control, 'wm_readonly@writability.test', false),
        (v_u_admin,   'wm_admin@writability.test',    true),
        (v_u_root,    'wm_root@writability.test',     false),
        (v_u_out,     'wm_outsider@writability.test', false)
    ON CONFLICT (id) DO UPDATE SET is_admin = EXCLUDED.is_admin;
    INSERT INTO public.users_permissions (user_id, organization_id, created_by) VALUES
        (v_u_troop,   v_troop_org, v_u_troop),
        (v_u_control, v_ctrl_org,  v_u_control),
        (v_u_root,    v_root_org,  v_u_root),
        (v_u_out,     v_out_org,   v_u_out);
    INSERT INTO public.troop_members (troop_id, user_id) VALUES
        (rec1.responsible_troop, v_u_troop),
        (v_ctrl_troop, v_u_control)
    ON CONFLICT DO NOTHING;

    -- Distinct probe values that satisfy FKs / UNIQUE constraints where possible
    SELECT p.id INTO v_free_plot
    FROM inventory_archive.plot p
    LEFT JOIN public.records r2 ON r2.plot_id = p.id
    WHERE r2.id IS NULL LIMIT 1;
    SELECT id INTO v_other_cluster FROM inventory_archive.cluster
    WHERE id IS DISTINCT FROM rec1.cluster_id LIMIT 1;
    SELECT id INTO v_other_schema FROM public.schemas
    WHERE id IS DISTINCT FROM rec1.schema_id LIMIT 1;
    SELECT id INTO v_other_rc FROM public.record_changes
    WHERE id IS DISTINCT FROM rec1.record_changes_id LIMIT 1;
    SELECT COALESCE(max(cluster_name), 0) + 1 INTO v_new_cluster_name FROM public.records;
    SELECT COALESCE(max(plot_name), 0) + 1 INTO v_new_plot_name
    FROM public.records WHERE cluster_name IS NOT DISTINCT FROM rec1.cluster_name;

    INSERT INTO public._wm_meta VALUES
        ('target_record_id', rec1.id::text),
        ('target_cluster/plot', COALESCE(rec1.cluster_name::text,'?') || ' / ' || COALESCE(rec1.plot_name::text,'?')),
        ('target_is_training', rec1.is_training::text),
        ('staged_read_only_troop', staged_ctrl::text),
        ('staged_completed_at_troop', staged_completed::text);

    -- ── Build one UPDATE probe per updatable column ─────────────────────────
    FOR c IN
        SELECT column_name, data_type
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'records'
          AND column_name NOT IN ('id', 'created_at')
        ORDER BY column_name
    LOOP
        v_expr := CASE c.column_name
            WHEN 'plot_id' THEN
                CASE WHEN v_free_plot IS NOT NULL THEN format('%L::uuid', v_free_plot) ELSE NULL END
            WHEN 'cluster_id' THEN
                CASE WHEN v_other_cluster IS NOT NULL THEN format('%L::uuid', v_other_cluster)
                     WHEN rec1.cluster_id IS NOT NULL THEN 'NULL' ELSE NULL END
            WHEN 'cluster_name'  THEN v_new_cluster_name::text
            WHEN 'plot_name'     THEN v_new_plot_name::text
            WHEN 'schema_id' THEN
                CASE WHEN v_other_schema IS NOT NULL THEN format('%L::uuid', v_other_schema)
                     WHEN rec1.schema_id IS NOT NULL THEN 'NULL' ELSE NULL END
            WHEN 'record_changes_id' THEN
                CASE WHEN v_other_rc IS NOT NULL THEN format('%L::uuid', v_other_rc)
                     ELSE format('%L::uuid', gen_random_uuid()) END
            WHEN 'updated_by' THEN format('%L::uuid', v_u_troop)
            WHEN 'current_troop_members' THEN
                format('COALESCE(current_troop_members, ARRAY[]::uuid[]) || %L::uuid', v_u_troop)
            WHEN 'responsible_administration' THEN format('%L::uuid', v_out_org)
            WHEN 'responsible_state'          THEN format('%L::uuid', v_out_org)
            WHEN 'responsible_provider'       THEN format('%L::uuid', v_out_org)
            WHEN 'responsible_troop'           THEN format('%L::uuid', v_fix_troop)
            WHEN 'responsible_read_only_troop' THEN format('%L::uuid', v_fix_troop)
            ELSE CASE c.data_type
                WHEN 'jsonb'   THEN format('COALESCE(%I, ''{}''::jsonb) || ''{"_wm_probe": true}''::jsonb', c.column_name)
                WHEN 'text'    THEN format('COALESCE(%I, '''') || ''_wm''', c.column_name)
                WHEN 'boolean' THEN format('NOT COALESCE(%I, false)', c.column_name)
                -- unknown uuid columns: random value; an FK violation still proves authz passed (W!)
                WHEN 'uuid'    THEN format('%L::uuid', gen_random_uuid())
                WHEN 'smallint' THEN format('(COALESCE(%I, 0) + 1)::smallint', c.column_name)
                WHEN 'integer' THEN format('COALESCE(%I, 0) + 1', c.column_name)
                WHEN 'bigint'  THEN format('COALESCE(%I, 0) + 1', c.column_name)
                WHEN 'timestamp with time zone' THEN 'now()'
                ELSE NULL
            END
        END;
        INSERT INTO public._wm_probes VALUES (
            v_ord,
            c.column_name,
            CASE WHEN v_expr IS NULL THEN NULL
                 ELSE format('UPDATE public.records SET %I = %s WHERE id = %L::uuid', c.column_name, v_expr, rec1.id)
            END,
            CASE WHEN v_expr IS NULL THEN 'no distinct value available (' || c.data_type || ')' END
        );
        v_ord := v_ord + 10;
    END LOOP;
    -- pull the two headline columns to the front
    UPDATE public._wm_probes SET ord = 10 WHERE column_name = 'properties';
    UPDATE public._wm_probes SET ord = 20 WHERE column_name = 'previous_properties';

    -- Row-level pseudo-probes
    v_ins_plot := COALESCE(v_free_plot, rec1.plot_id);  -- fallback: unique violation still proves authz passed
    INSERT INTO public._wm_probes VALUES
        (900, '__INSERT__', format('INSERT INTO public.records (plot_id, properties) VALUES (%L::uuid, ''{"_wm_probe": true}''::jsonb)', v_ins_plot), NULL),
        (910, '__DELETE__', format('DELETE FROM public.records WHERE id = %L::uuid', rec1.id), NULL);

    -- ── Personas × header variants ──────────────────────────────────────────
    INSERT INTO public._wm_personas VALUES
        (10, 'troop',    'app', 'authenticated', v_u_troop,   NULL, 'supabase-flutter/2.10.3'),
        (11, 'troop',    'api', 'authenticated', v_u_troop,   NULL, 'r-httr/1.4.7'),
        (20, 'readonly', 'app', 'authenticated', v_u_control, NULL, 'supabase-flutter/2.10.3'),
        (21, 'readonly', 'api', 'authenticated', v_u_control, NULL, 'r-httr/1.4.7'),
        (30, 'admin',    'app', 'authenticated', v_u_admin,   NULL, 'supabase-flutter/2.10.3'),
        (31, 'admin',    'api', 'authenticated', v_u_admin,   NULL, 'r-httr/1.4.7'),
        (40, 'root',     'app', 'authenticated', v_u_root,    NULL, 'supabase-flutter/2.10.3'),
        (41, 'root',     'api', 'authenticated', v_u_root,    NULL, 'r-httr/1.4.7'),
        (50, 'outsider', 'app', 'authenticated', v_u_out,     NULL, 'supabase-flutter/2.10.3'),
        (51, 'outsider', 'api', 'authenticated', v_u_out,     NULL, 'r-httr/1.4.7'),
        (60, 'anon',         'api', 'anon',         NULL, 'anon',         'r-httr/1.4.7'),
        (70, 'ti_read',      'db',  'ti_read',      NULL, NULL,           NULL),
        (80, 'service_role', 'api', 'service_role', NULL, 'service_role', 'node-fetch/3'),
        (90, 'db_owner',     'db',  'none',         NULL, NULL,           NULL);

    -- Allow SET ROLE ti_read for the sweep (session user is often not superuser).
    -- Transactional like everything else here — gone after ROLLBACK.
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ti_read') THEN
        BEGIN
            EXECUTE format('GRANT ti_read TO %I', session_user);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Could not GRANT ti_read to % — ti_read sweep may be skipped.', session_user;
        END;
    END IF;

    RAISE NOTICE 'Fixtures ready. Target record % (cluster %, plot %, is_training=%). staged_read_only_troop=%, staged_completed_at_troop=%',
        rec1.id, rec1.cluster_name, rec1.plot_name, rec1.is_training, staged_ctrl, staged_completed;
END
$fixtures$;

-- ── Sweep: personas × probes ────────────────────────────────────────────────
DO $sweep$
DECLARE
    p record;
    probe record;
    n int;
    ec text;
    em text;
BEGIN
    FOR p IN SELECT * FROM public._wm_personas ORDER BY ord LOOP
        PERFORM set_config('role', 'none', true);

        IF p.pg_role <> 'none'
           AND NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = p.pg_role) THEN
            INSERT INTO public._wm_results
            SELECT p.persona, p.header, column_name, 'SKIPPED', NULL, 'role "' || p.pg_role || '" does not exist'
            FROM public._wm_probes;
            CONTINUE;
        END IF;

        -- Simulate the PostgREST request context for this persona
        IF p.uid IS NOT NULL THEN
            PERFORM set_config('request.jwt.claims',
                json_build_object('sub', p.uid, 'role', 'authenticated',
                                  'email', p.persona || '@writability.test')::text, true);
            PERFORM set_config('request.jwt.claim.sub', p.uid::text, true);
            PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
        ELSIF p.jwt_role IS NOT NULL THEN
            PERFORM set_config('request.jwt.claims', json_build_object('role', p.jwt_role)::text, true);
            PERFORM set_config('request.jwt.claim.sub', '', true);
            PERFORM set_config('request.jwt.claim.role', p.jwt_role, true);
        ELSE  -- direct DB connection: no JWT at all
            PERFORM set_config('request.jwt.claims', NULL, true);
            PERFORM set_config('request.jwt.claim.sub', NULL, true);
            PERFORM set_config('request.jwt.claim.role', NULL, true);
        END IF;
        IF p.header_value IS NOT NULL THEN
            PERFORM set_config('request.headers', json_build_object('x-client-info', p.header_value)::text, true);
        ELSE
            PERFORM set_config('request.headers', NULL, true);
        END IF;

        BEGIN
            PERFORM set_config('role', p.pg_role, true);
        EXCEPTION WHEN OTHERS THEN
            PERFORM set_config('role', 'none', true);
            INSERT INTO public._wm_results
            SELECT p.persona, p.header, column_name, 'SKIPPED', NULL, 'cannot SET ROLE ' || p.pg_role
            FROM public._wm_probes;
            CONTINUE;
        END;

        FOR probe IN SELECT * FROM public._wm_probes ORDER BY ord LOOP
            IF probe.stmt IS NULL THEN
                INSERT INTO public._wm_results
                VALUES (p.persona, p.header, probe.column_name, 'SKIPPED', NULL, probe.note);
                CONTINUE;
            END IF;
            BEGIN
                EXECUTE probe.stmt;
                GET DIAGNOSTICS n = ROW_COUNT;
                -- Success: force a savepoint rollback so probes stay independent.
                RAISE EXCEPTION USING ERRCODE = 'WM999', MESSAGE = n::text;
            EXCEPTION
                WHEN SQLSTATE 'WM999' THEN
                    INSERT INTO public._wm_results VALUES (
                        p.persona, p.header, probe.column_name,
                        CASE WHEN n > 0 THEN 'WRITABLE' ELSE 'BLOCKED_SILENT_RLS' END,
                        NULL,
                        CASE WHEN n = 0 THEN 'no error, 0 rows (row invisible under RLS USING)' END);
                WHEN OTHERS THEN
                    GET STACKED DIAGNOSTICS ec = RETURNED_SQLSTATE, em = MESSAGE_TEXT;
                    INSERT INTO public._wm_results VALUES (
                        p.persona, p.header, probe.column_name,
                        -- integrity-constraint errors mean authz was passed: the write was attempted
                        CASE WHEN ec LIKE '23%' THEN 'WRITABLE_CONSTRAINT' ELSE 'BLOCKED_ERROR' END,
                        ec, left(em, 160));
            END;
        END LOOP;

        PERFORM set_config('role', 'none', true);
    END LOOP;
END
$sweep$;

-- ── Reports (still inside the transaction; everything vanishes at ROLLBACK) ─
\echo ''
\echo '=== Test context ==========================================================='
SELECT key, val FROM public._wm_meta ORDER BY key;

\echo ''
\echo '=== WRITABILITY MATRIX ====================================================='
\echo 'W = writable | W! = passed authz, blocked only by data constraint (23xxx)'
\echo '0 = silently blocked by RLS (0 rows) | X = blocked with error | - = skipped'
\echo 'app = x-client-info: supabase-flutter/... | api = plain REST client | db = direct'
\echo ''
WITH marked AS (
    SELECT persona, header, column_name,
           CASE outcome
               WHEN 'WRITABLE'            THEN 'W'
               WHEN 'WRITABLE_CONSTRAINT' THEN 'W!'
               WHEN 'BLOCKED_SILENT_RLS'  THEN '0'
               WHEN 'BLOCKED_ERROR'       THEN 'X ' || sqlstate
               ELSE '-'
           END AS mark
    FROM public._wm_results
)
SELECT r.column_name,
       max(mark) FILTER (WHERE persona = 'troop'    AND header = 'app') AS troop_app,
       max(mark) FILTER (WHERE persona = 'troop'    AND header = 'api') AS troop_api,
       max(mark) FILTER (WHERE persona = 'readonly' AND header = 'app') AS ro_app,
       max(mark) FILTER (WHERE persona = 'readonly' AND header = 'api') AS ro_api,
       max(mark) FILTER (WHERE persona = 'admin'    AND header = 'app') AS admin_app,
       max(mark) FILTER (WHERE persona = 'admin'    AND header = 'api') AS admin_api,
       max(mark) FILTER (WHERE persona = 'root'     AND header = 'app') AS root_app,
       max(mark) FILTER (WHERE persona = 'root'     AND header = 'api') AS root_api,
       max(mark) FILTER (WHERE persona = 'outsider' AND header = 'app') AS out_app,
       max(mark) FILTER (WHERE persona = 'outsider' AND header = 'api') AS out_api,
       max(mark) FILTER (WHERE persona = 'anon')         AS anon,
       max(mark) FILTER (WHERE persona = 'ti_read')      AS ti_read,
       max(mark) FILTER (WHERE persona = 'service_role') AS service,
       max(mark) FILTER (WHERE persona = 'db_owner')     AS db_owner
FROM marked r
GROUP BY r.column_name
ORDER BY CASE r.column_name
             WHEN 'properties' THEN 0
             WHEN 'previous_properties' THEN 1
             WHEN '__INSERT__' THEN 9998
             WHEN '__DELETE__' THEN 9999
             ELSE 2 END,
         r.column_name;

\echo ''
\echo '=== Focus: records.properties ============================================='
SELECT persona, header, outcome, sqlstate, detail
FROM public._wm_results
WHERE column_name = 'properties'
ORDER BY (SELECT ord FROM public._wm_personas pp
          WHERE pp.persona = _wm_results.persona AND pp.header = _wm_results.header);

\echo ''
\echo '=== Blocked/constraint details (grouped) ==================================='
SELECT persona, header, outcome, sqlstate,
       count(*) AS cols,
       left(min(detail), 90) AS example_message,
       left(string_agg(column_name, ', ' ORDER BY column_name), 200) AS columns
FROM public._wm_results
WHERE outcome IN ('BLOCKED_ERROR', 'WRITABLE_CONSTRAINT', 'SKIPPED')
GROUP BY persona, header, outcome, sqlstate
ORDER BY persona, header, outcome, sqlstate;

-- ── Headline verdict ─────────────────────────────────────────────────────────
DO $verdict$
DECLARE
    troop_api text;
    troop_app text;
    guard_attached boolean;
    ctrl_writable int;
    ctrl_columns text;
BEGIN
    SELECT outcome INTO troop_api FROM public._wm_results
    WHERE persona = 'troop' AND header = 'api' AND column_name = 'properties';
    SELECT outcome INTO troop_app FROM public._wm_results
    WHERE persona = 'troop' AND header = 'app' AND column_name = 'properties';
    -- Read-only groups (troop.is_read_only, 20260714000000) are pure viewers:
    -- no probe may pass authz, regardless of column or client header.
    SELECT count(*),
           left(string_agg(DISTINCT column_name, ', ' ORDER BY column_name), 200)
    INTO ctrl_writable, ctrl_columns
    FROM public._wm_results
    WHERE persona = 'readonly'
      AND outcome IN ('WRITABLE', 'WRITABLE_CONSTRAINT');
    SELECT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'public.records'::regclass AND tgname = 'guard_records_write'
    ) INTO guard_attached;

    RAISE NOTICE '';
    RAISE NOTICE '============================================================';
    RAISE NOTICE 'VERDICT on records.properties';
    RAISE NOTICE '  via app header (supabase-flutter): %', troop_app;
    RAISE NOTICE '  via plain API client:              %', troop_api;
    RAISE NOTICE '  guard_records_write trigger attached: %', guard_attached;
    IF troop_api = 'WRITABLE' THEN
        RAISE NOTICE '  => GAP CONFIRMED: a responsible troop user can modify';
        RAISE NOTICE '     records.properties through the plain REST API.';
    ELSIF troop_app = 'WRITABLE' AND troop_api <> 'WRITABLE' THEN
        RAISE NOTICE '  => Guard effective: app can write, plain API cannot.';
    ELSE
        RAISE NOTICE '  => Unexpected combination — inspect the matrix above.';
    END IF;
    RAISE NOTICE '------------------------------------------------------------';
    RAISE NOTICE 'VERDICT on read-only group (must have zero write access)';
    IF ctrl_writable = 0 THEN
        RAISE NOTICE '  => OK: readonly persona passed authz on 0 probes.';
    ELSE
        RAISE NOTICE '  => GAP CONFIRMED: readonly persona can write % probe(s): %',
            ctrl_writable, ctrl_columns;
    END IF;
    RAISE NOTICE '============================================================';
END
$verdict$;

-- Dry run: nothing is ever committed.
ROLLBACK;
\echo ''
\echo 'ROLLBACK complete — no data was changed.'
