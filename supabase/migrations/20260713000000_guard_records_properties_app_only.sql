-- ============================================================================
-- GUARD: records.properties may only be changed through the TFM app
-- ============================================================================
-- "properties" holds the field data collected by the troops. It must only be
-- written through the TFM app (PowerSync upload path), never through direct
-- REST API clients (R, Python, curl, Postman) — those bypass the app-side
-- validation of the collected data.
--
-- The app has no privileged channel: PowerSync uploads replay through
-- PostgREST as the authenticated user, exactly like any other REST client.
-- The only distinguishing signal is the X-Client-Info header the
-- supabase_flutter SDK sends on every request (e.g. "supabase-flutter/2.10.3").
--
-- NOTE: the header is client-supplied and therefore spoofable — this guard
-- stops accidental/unofficial API writes; it is not a cryptographic boundary.
--
-- Scope:
--   * only auth.role() = 'authenticated' — service_role, postgres and other
--     elevated roles bypass (fill_properties(), migration scripts, R server)
--   * only when properties actually changes; the app sends full rows, so
--     no-op property updates must keep working for everyone
--   * every other column stays writable via the API (status fields, notes,
--     responsibility assignments, ...)
--
-- Complements (does not replace):
--   * guard_records_properties_admin — blocks admins even from the app
--   * guard_records_write() — older all-column variant; remains unattached
--     (as written it would also block service_role and direct DB writes)
--
-- Verification: supabase/tests/run_writability_matrix.sh — expected result:
-- properties column W for troop with app header, X 42501 with plain API
-- header; read-only group X everywhere (20260714000000);
-- service/db_owner unaffected.
-- ============================================================================
SET search_path TO public;

CREATE OR REPLACE FUNCTION public.guard_records_properties_app_only() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE client_info text;
BEGIN
    -- Allow service_role and other elevated roles to update any column
    IF auth.role() IS DISTINCT FROM 'authenticated' THEN
        RETURN NEW;
    END IF;

    -- Nothing to enforce when properties is unchanged (jsonb equality)
    IF NEW.properties IS NOT DISTINCT FROM OLD.properties THEN
        RETURN NEW;
    END IF;

    -- PostgREST exposes the request headers as a JSON GUC. It is always set
    -- for requests coming through PostgREST; treat unset/unreadable as
    -- "no header" and block.
    BEGIN
        client_info := (nullif(current_setting('request.headers', true), '')::json)->>'x-client-info';
    EXCEPTION WHEN OTHERS THEN
        client_info := NULL;
    END;

    IF client_info LIKE 'supabase-flutter%' THEN
        RETURN NEW;
    END IF;

    RAISE EXCEPTION 'records.properties can only be modified through the TFM app'
        USING ERRCODE = '42501';  -- insufficient_privilege
END;
$$;
COMMENT ON FUNCTION public.guard_records_properties_app_only() IS
    'Blocks authenticated non-app clients (missing/foreign X-Client-Info header) from changing records.properties. service_role/postgres bypass; no-op property updates pass.';

-- Apply trigger
DROP TRIGGER IF EXISTS guard_records_properties_app_only ON public.records;
CREATE TRIGGER guard_records_properties_app_only BEFORE
UPDATE ON public.records FOR EACH ROW EXECUTE FUNCTION public.guard_records_properties_app_only();
