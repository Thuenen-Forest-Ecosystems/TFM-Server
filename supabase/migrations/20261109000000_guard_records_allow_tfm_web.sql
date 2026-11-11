-- ============================================================================
-- guard_records_app_only_columns: also accept the TFM web admin (tfm-web/*)
-- ============================================================================
-- The write_log of 20261106000000 (log mode, 2026-11-06 .. 2026-11-09) showed
-- a second legitimate writer besides the app: the web admin
-- (TFM-Documentation, supabase-js 2.50.4, header supabase-js-web/2.50.4),
-- 105 writes by 5 users:
--   * FinishDialog.vue / ListOfClusterRecord.vue — completed_at_troop
--     (finish as provider, troop reassignment sends the corner back = NULL)
--   * HistoryHorizonatal.vue "Wiederherstellen" — properties, completed_at_*,
--     validation_errors, plausibility_errors from a history version
--   * DetailAdministration.vue — properties restore
-- The web admin now sends its own header `X-Client-Info: tfm-web/<version>`
-- (TFM-Documentation .vitepress/theme/index.js + supabase-connector.ts).
-- Generic supabase-js (supabase-js-web/*, supabase-js-node/*) stays
-- disallowed, so ad-hoc JS scripts are treated like R/Python/curl.
--
-- Mode is unchanged ('log'). Deploy order: this migration, then the web
-- admin; check write_log for tfm-web entries with is_app = true before
-- switching to enforce (supabase/pending/guard_records_app_only_enforce.sql).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.guard_records_app_only_columns() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
    app_only constant text[] := ARRAY[
        'properties', 'completed_at_troop', 'schema_id_validated_by',
        'validation_errors', 'plausibility_errors'
    ];
    -- X-Client-Info prefixes of the official clients:
    --   supabase-flutter/  TFM app (Android/iOS/web build), SDK default
    --   tfm-web/           TFM web admin (TFM-Documentation), set explicitly
    allowed_clients constant text[] := ARRAY['supabase-flutter/', 'tfm-web/'];
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
    is_app := coalesce(
        EXISTS (SELECT 1 FROM unnest(allowed_clients) AS p WHERE client_info LIKE p || '%'),
        false);

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

    RAISE EXCEPTION 'records: % kann nur über die TFM-App oder die TFM-Webanwendung geändert werden', array_to_string(changed, ', ')
        USING ERRCODE = '42501',
              HINT = 'Zuweisungen und andere Spalten sind weiterhin per API änderbar.';
END;
$$;

COMMENT ON FUNCTION public.guard_records_app_only_columns() IS
    'records field-data columns (properties, completed_at_troop, schema_id_validated_by, validation_errors, plausibility_errors) only changeable by authenticated clients sending X-Client-Info supabase-flutter/* (app) or tfm-web/* (web admin). Mode in records_guard.settings: log (default) or enforce.';

COMMENT ON COLUMN records_guard.write_log.is_app IS
    'true = official client (supabase-flutter/* or tfm-web/*). Rows before 20261109000000 classified tfm-web as false (header did not exist yet).';
