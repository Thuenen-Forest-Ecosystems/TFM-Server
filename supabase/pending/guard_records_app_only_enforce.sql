-- ============================================================================
-- PENDING — not a migration yet. To deploy, copy to
--   supabase/migrations/<YYYYMMDDHHMMSS>_guard_records_app_only_enforce.sql
-- with the current timestamp, commit, `supabase db push`.
-- Kept out of migrations/ on purpose: `db push` applies every pending file.
-- ============================================================================
-- Switch guard_records_app_only_columns from 'log' to 'enforce'.
-- After that, authenticated clients whose X-Client-Info starts neither with
-- `supabase-flutter/` (app) nor with `tfm-web/` (web admin) get 42501 when
-- they change properties, completed_at_troop, schema_id_validated_by,
-- validation_errors or plausibility_errors.
--
-- Safety checks — on failure the migration rolls back and the mode stays 'log':
--   1. The web admin's own header has been seen at least once
--      (proves the TFM-Documentation build with tfm-web/* is live).
--   2. Since the first tfm-web entry (at most the last 7 days) no real user
--      wrote a protected column with a non-official client. The
--      integration-test account (b7a83082…, automated-tests@gruenecho.de) is
--      excluded — its entries are deliberate guard tests.
--
-- Roll back without touching the trigger:
--   UPDATE records_guard.settings SET mode = 'log';
-- Verify after deploy:
--   API_URL=https://ci.thuenen.de supabase/tests/run_app_only_guard_http.sh enforce
-- ============================================================================

DO $$
DECLARE
    first_web  timestamptz;
    since      timestamptz;
    offenders  text;
BEGIN
    SELECT min(logged_at) INTO first_web
    FROM records_guard.write_log
    WHERE client_info LIKE 'tfm-web/%';

    IF first_web IS NULL THEN
        RAISE EXCEPTION 'enforce abgebrochen: noch kein Schreibzugriff mit tfm-web/* im Log'
            USING HINT = 'Erst die Webanwendung mit dem neuen X-Client-Info deployen und benutzen lassen.';
    END IF;

    since := greatest(first_web, now() - interval '7 days');

    SELECT string_agg(format('%s (%s, %s×, zuletzt %s)',
                             user_id, coalesce(client_info, 'kein Header'), n, last_at), '; ')
    INTO offenders
    FROM (
        SELECT user_id, client_info, count(*) AS n, max(logged_at) AS last_at
        FROM records_guard.write_log
        WHERE logged_at >= since
          AND NOT coalesce(client_info LIKE 'supabase-flutter/%' OR client_info LIKE 'tfm-web/%', false)
          AND user_id IS DISTINCT FROM 'b7a83082-dcc2-4dff-85cd-529363a7be8b'
        GROUP BY 1, 2
    ) s;

    IF offenders IS NOT NULL THEN
        RAISE EXCEPTION 'enforce abgebrochen: Schreibzugriffe ohne offiziellen Client seit %: %', since, offenders
            USING HINT = 'Schreiber klären (alte Browser-Tabs der Webanwendung? Skripte?), dann erneut ausführen.';
    END IF;
END;
$$;

UPDATE records_guard.settings SET mode = 'enforce';
