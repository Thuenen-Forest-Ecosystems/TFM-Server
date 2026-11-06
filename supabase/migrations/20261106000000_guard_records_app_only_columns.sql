-- ============================================================================
-- GUARD: field-data columns of public.records only writable through the app
-- ============================================================================
-- Problem (live test 2026-11-06, plain curl PATCH on 1000000070/3 → HTTP 200):
-- records.properties can be changed through the REST API with any client.
-- The first version of this guard (20260713000000) never reached production
-- and was deleted in 777e71d (2026-10-01) to unblock `db push`.
--
-- What is protected (APP_ONLY columns) — the troop's field data and what the
-- app derives from it when saving:
--     properties, completed_at_troop, schema_id_validated_by,
--     validation_errors, plausibility_errors
-- Everything else stays writable through the API: assignments
-- (responsible_*, *_los, is_to_be_recorded), completed_at_state /
-- completed_at_administration, note, ...
--
-- How "app" is recognised: the supabase_flutter SDK sends
-- `X-Client-Info: supabase-flutter/<version>` on every REST request,
-- including the PowerSync upload (uploadData uses Supabase.instance.client
-- .rest; Supabase.initialize is called without custom headers). Flutter web
-- sends the same header. The header is client-supplied and therefore
-- spoofable: this stops unofficial API writes (R, Python, curl, Postman), it
-- is not a cryptographic boundary.
--
-- Not affected:
--   * service_role, postgres and every other non-`authenticated` role
--     (R server, fill_properties, migration scripts)
--   * updates issued by other triggers (pg_trigger_depth() > 1)
--   * updates where no APP_ONLY column actually changes (full-row upserts)
--
-- Two modes, stored in records_guard.settings (schema not exposed via
-- PostgREST):
--   'log'     (default) — never blocks; every authenticated change of an
--             APP_ONLY column is written to records_guard.write_log together
--             with the X-Client-Info value. Used on production first to prove
--             with real traffic that app uploads arrive with the header
--             (through Envoy/Kong) and to find legitimate non-app writers.
--   'enforce' — non-app changes of APP_ONLY columns fail with 42501.
--             Switch only via a follow-up migration after the log check.
--
-- Deliberately NOT included: guard_records_properties_admin (20260625000000).
-- It would block root-org members even in the app; the troop
-- "Internal - Aufnahme" belongs to the root org "Thünen".
--
-- Tests: supabase/tests/test_records_app_only_guard.sql (SQL, rolled back)
--        supabase/tests/run_app_only_guard_http.sh (real HTTP via PostgREST)
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS records_guard;
REVOKE ALL ON SCHEMA records_guard FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS records_guard.settings (
    id      boolean PRIMARY KEY DEFAULT true CHECK (id),
    mode    text NOT NULL DEFAULT 'log' CHECK (mode IN ('log', 'enforce'))
);
INSERT INTO records_guard.settings (id, mode) VALUES (true, 'log')
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS records_guard.write_log (
    id           bigserial PRIMARY KEY,
    logged_at    timestamptz NOT NULL DEFAULT now(),
    record_id    uuid NOT NULL,
    user_id      uuid,
    client_info  text,
    is_app       boolean NOT NULL,
    mode         text NOT NULL,
    columns      text[] NOT NULL
);
CREATE INDEX IF NOT EXISTS write_log_logged_at_idx ON records_guard.write_log (logged_at);

REVOKE ALL ON ALL TABLES IN SCHEMA records_guard FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA records_guard FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.guard_records_app_only_columns() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
    app_only constant text[] := ARRAY[
        'properties', 'completed_at_troop', 'schema_id_validated_by',
        'validation_errors', 'plausibility_errors'
    ];
    changed     text[];
    client_info text;
    is_app      boolean;
    guard_mode  text;
    old_row     jsonb;
    new_row     jsonb;
BEGIN
    -- service_role, postgres, ... bypass
    IF auth.role() IS DISTINCT FROM 'authenticated' THEN
        RETURN NEW;
    END IF;
    -- updates issued by other triggers (e.g. los → responsible_* cascades)
    IF pg_trigger_depth() > 1 THEN
        RETURN NEW;
    END IF;

    old_row := to_jsonb(OLD);
    new_row := to_jsonb(NEW);
    SELECT array_agg(c ORDER BY c) INTO changed
    FROM unnest(app_only) AS c
    WHERE old_row -> c IS DISTINCT FROM new_row -> c;

    IF changed IS NULL THEN
        RETURN NEW;  -- no APP_ONLY column changed (incl. full-row no-op upserts)
    END IF;

    BEGIN
        client_info := (nullif(current_setting('request.headers', true), '')::json) ->> 'x-client-info';
    EXCEPTION WHEN OTHERS THEN
        client_info := NULL;
    END;
    is_app := coalesce(client_info LIKE 'supabase-flutter/%', false);

    SELECT s.mode INTO guard_mode FROM records_guard.settings s WHERE s.id;
    guard_mode := coalesce(guard_mode, 'log');

    IF guard_mode = 'log' THEN
        INSERT INTO records_guard.write_log (record_id, user_id, client_info, is_app, mode, columns)
        VALUES (NEW.id, auth.uid(), client_info, is_app, guard_mode, changed);
        RETURN NEW;
    END IF;

    IF is_app THEN
        RETURN NEW;
    END IF;

    RAISE EXCEPTION 'records: % kann nur über die TFM-App geändert werden', array_to_string(changed, ', ')
        USING ERRCODE = '42501',
              HINT = 'Zuweisungen und andere Spalten sind weiterhin per API änderbar.';
END;
$$;

COMMENT ON FUNCTION public.guard_records_app_only_columns() IS
    'records field-data columns (properties, completed_at_troop, schema_id_validated_by, validation_errors, plausibility_errors) only changeable by authenticated clients sending X-Client-Info supabase-flutter/*. Mode in records_guard.settings: log (default) or enforce.';

DROP TRIGGER IF EXISTS guard_records_app_only_columns ON public.records;
CREATE TRIGGER guard_records_app_only_columns
BEFORE UPDATE ON public.records
FOR EACH ROW EXECUTE FUNCTION public.guard_records_app_only_columns();
