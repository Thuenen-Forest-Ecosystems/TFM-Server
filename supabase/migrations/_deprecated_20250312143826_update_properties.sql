-- ============================================================================
-- Migration: update_properties
-- ============================================================================
-- Functions to validate and set records.properties (the current inventory data).
--
-- Functions:
--   - validate_json_properties_by_schema()   → validates properties vs schema
--   - validate_record_properties()           → trigger (DEPRECATED)
--   - call_validation_function()             → calls Edge Function for validation
--   - handle_validation_version_change()     → trigger on schema_id/properties change
--   - set_preliminary()                      → copies bwi2022 data into properties
-- ============================================================================
-- ────────────────────────────────────────────────────────────────────────────
-- 1. validate_json_properties_by_schema (DEPRECATED)
-- ────────────────────────────────────────────────────────────────────────────
-- Validates properties JSON against a schema definition.
-- Kept for backward compatibility.
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.validate_json_properties_by_schema(schema_id uuid, properties jsonb) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE schema_def json;
BEGIN
SELECT schema INTO schema_def
FROM public.schemas
WHERE id = schema_id;
IF schema_def IS NULL THEN RETURN FALSE;
END IF;
IF properties IS NULL
OR properties = '{}'::jsonb THEN RETURN TRUE;
END IF;
RETURN extensions.jsonb_matches_schema(schema := schema_def, instance := properties);
END;
$$;
-- ────────────────────────────────────────────────────────────────────────────
-- 2. validate_record_properties (TRIGGER FUNCTION — DEPRECATED)
-- ────────────────────────────────────────────────────────────────────────────
-- Sets is_valid flag by validating properties against the schema.
-- Kept for backward compatibility.
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.validate_record_properties() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$ BEGIN
SELECT id INTO NEW.schema_id
FROM public.schemas
WHERE interval_name = NEW.schema_name
    AND is_visible = true
ORDER BY created_at DESC
LIMIT 1;
IF NEW.schema_name IS NOT NULL
AND NEW.properties IS NOT NULL
AND jsonb_typeof(NEW.properties) = 'object' THEN
SELECT id INTO NEW.schema_id
FROM public.schemas
WHERE interval_name = NEW.schema_name
    AND is_visible = true
ORDER BY created_at DESC
LIMIT 1;
NEW.is_valid := public.validate_json_properties_by_schema(NEW.schema_id, NEW.properties);
ELSE NEW.is_valid := FALSE;
END IF;
RETURN NEW;
END;
$$;
-- ────────────────────────────────────────────────────────────────────────────
-- 3. call_validation_function
-- ────────────────────────────────────────────────────────────────────────────
-- Calls Supabase Edge Function to validate record properties.
-- Returns validation_errors and plausibility_errors as JSONB.
-- ────────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.call_validation_function;
CREATE OR REPLACE FUNCTION public.call_validation_function(
        p_properties jsonb,
        p_previous_properties jsonb,
        p_schema_id uuid
    ) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE validation_result jsonb;
function_url text;
payload text;
response record;
version_directory text;
debug text;
service_role_key text;
BEGIN function_url := current_setting('app.settings.supabase_functions_url', true) || '/validate-record';
IF function_url IS NULL
OR function_url = '/validate-record' THEN function_url := 'https://ci.thuenen.de/functions/v1/validate-record';
END IF;
service_role_key := current_setting('app.settings.service_role_key', true);
SELECT directory INTO version_directory
FROM public.schemas
WHERE id = p_schema_id;
payload := jsonb_build_object(
    'properties',
    p_properties,
    'previous_properties',
    p_previous_properties,
    'validation_version',
    version_directory
)::text;
SELECT * INTO response
FROM http(
        (
            'POST',
            function_url,
            ARRAY [http_header('Authorization', 'Bearer ' || COALESCE(service_role_key, ''))],
            'application/json',
            payload
        )::http_request
    );
IF response.status >= 200
AND response.status < 300 THEN validation_result := response.content::jsonb;
ELSE debug := format(
    'HTTP Error %s: %s',
    response.status,
    response.content
);
RAISE NOTICE 'HTTP request failed: %',
debug;
RETURN jsonb_build_object(
    'validation_errors',
    jsonb_build_object('error', 'HTTP request failed', 'debug', debug),
    'plausibility_errors',
    jsonb_build_object('error', 'HTTP request failed', 'debug', debug)
);
END IF;
RETURN validation_result;
EXCEPTION
WHEN OTHERS THEN debug := 'Error calling Edge Function: ' || SQLERRM;
RAISE NOTICE 'Validation function error: %',
debug;
RETURN jsonb_build_object(
    'validation_errors',
    jsonb_build_object(
        'error',
        'Validation service unavailable',
        'debug',
        debug
    ),
    'plausibility_errors',
    jsonb_build_object(
        'error',
        'Plausibility service unavailable',
        'debug',
        debug
    )
);
END;
$$;
-- Permissions
REVOKE ALL ON FUNCTION public.call_validation_function(jsonb, jsonb, uuid)
FROM PUBLIC;
REVOKE ALL ON FUNCTION public.call_validation_function(jsonb, jsonb, uuid)
FROM anon;
REVOKE ALL ON FUNCTION public.call_validation_function(jsonb, jsonb, uuid)
FROM authenticated;
GRANT EXECUTE ON FUNCTION public.call_validation_function(jsonb, jsonb, uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.call_validation_function(jsonb, jsonb, uuid) TO service_role;
-- ────────────────────────────────────────────────────────────────────────────
-- 4. handle_validation_version_change (TRIGGER FUNCTION)
-- ────────────────────────────────────────────────────────────────────────────
-- Triggers validation when schema_id or properties change.
-- DISABLED (see trigger below) — causes connection exhaustion via sync HTTP.
-- ────────────────────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trigger_validation_version_change ON public.records;
DROP FUNCTION IF EXISTS public.handle_validation_version_change;
CREATE OR REPLACE FUNCTION public.handle_validation_version_change() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE validation_result jsonb;
BEGIN IF OLD.schema_id IS DISTINCT
FROM NEW.schema_id
    OR OLD.properties IS DISTINCT
FROM NEW.properties THEN
SELECT public.call_validation_function(
        NEW.properties,
        NEW.previous_properties,
        NEW.schema_id
    ) INTO validation_result;
IF validation_result IS NOT NULL THEN NEW.validation_errors := validation_result->'validation_errors';
NEW.is_valid := (NEW.validation_errors = '{}'::jsonb);
NEW.plausibility_errors := validation_result->'plausibility_errors';
NEW.is_plausible := (NEW.plausibility_errors = '{}'::jsonb);
END IF;
END IF;
RETURN NEW;
END;
$$;
-- TRIGGER: DISABLED — causes connection exhaustion due to synchronous HTTP calls
-- CREATE TRIGGER trigger_validation_version_change
--     BEFORE UPDATE OF schema_id, properties, previous_properties
--     ON public.records
--     FOR EACH ROW
--     EXECUTE FUNCTION public.handle_validation_version_change();
-- ────────────────────────────────────────────────────────────────────────────
-- 5. set_preliminary
-- ────────────────────────────────────────────────────────────────────────────
-- Sets preliminary properties from previous monitoring interval (bwi2022).
-- Copies field values from inventory_archive.plot into records.properties.
-- Reference: https://github.com/Thuenen-Forest-Ecosystems/TFM-Documentation/issues/79
--
-- Usage: SELECT public.set_preliminary();
-- ────────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.set_preliminary;
CREATE OR REPLACE FUNCTION public.set_preliminary() RETURNS VOID LANGUAGE plpgsql AS $$ BEGIN
UPDATE public.records r
SET properties = (
        to_jsonb(p) - 'id' - 'intkey' - 'cluster_id' - 'trees_less_4meter_coverage' - 'trees_less_4meter_layer' - 'stand_structure' - 'stand_age' - 'stand_development_phase' - 'stand_layer_regeneration' - 'fence_regeneration' - 'trees_greater_4meter_mirrored' - 'trees_greater_4meter_basal_area_factor' - 'harvest_method' - 'harvest_reason'
    ) || jsonb_build_object(
        'tree',
        COALESCE(
            (
                SELECT jsonb_agg(
                        jsonb_build_object(
                            'acquisition_date',
                            x.acquisition_date,
                            'interval_name',
                            x.interval_name
                        ) || jsonb_set(
                            jsonb_set(
                                jsonb_set(
                                    to_jsonb(x.t) - 'plot_id',
                                    '{dbh}',
                                    'null'::jsonb
                                ),
                                '{tree_age}',
                                CASE
                                    WHEN (to_jsonb(x.t)->'tree_age') IS NOT NULL
                                    AND (to_jsonb(x.t)->'tree_age') != 'null'::jsonb THEN to_jsonb(((to_jsonb(x.t)->>'tree_age')::smallint + 5))
                                    ELSE 'null'::jsonb
                                END
                            ),
                            '{tree_status}',
                            CASE
                                WHEN (to_jsonb(x.t)->>'tree_status')::integer IN (11, 12) THEN '2022'::jsonb
                                ELSE to_jsonb(x.t)->'tree_status'
                            END
                        )
                    )
                FROM (
                        SELECT pl.acquisition_date,
                            pl.interval_name,
                            t,
                            row_number() OVER(
                                PARTITION BY pl.cluster_name,
                                pl.plot_name,
                                t.tree_number
                                ORDER BY pl.acquisition_date DESC
                            ) as rn
                        FROM inventory_archive.plot pl
                            JOIN inventory_archive.tree t ON pl.id = t.plot_id
                        WHERE pl.cluster_name = r.cluster_name
                            AND pl.plot_name = r.plot_name
                    ) x
                WHERE x.rn = 1
            ),
            '[]'::jsonb
        ),
        'edges',
        COALESCE(
            (
                SELECT jsonb_agg(
                        jsonb_build_object(
                            'acquisition_date',
                            x.acquisition_date,
                            'interval_name',
                            x.interval_name
                        ) || (to_jsonb(x.e) - 'plot_id')
                    )
                FROM (
                        SELECT pl.acquisition_date,
                            pl.interval_name,
                            e,
                            row_number() OVER(
                                PARTITION BY pl.cluster_name,
                                pl.plot_name,
                                e.edge_number
                                ORDER BY pl.acquisition_date DESC
                            ) as rn
                        FROM inventory_archive.plot pl
                            JOIN inventory_archive.edges e ON pl.id = e.plot_id
                        WHERE pl.cluster_name = r.cluster_name
                            AND pl.plot_name = r.plot_name
                    ) x
                WHERE x.rn = 1
            ),
            '[]'::jsonb
        )
    )
FROM inventory_archive.plot p
WHERE r.cluster_name = p.cluster_name
    AND r.plot_name = p.plot_name
    AND p.interval_name = 'bwi2022';
END;
$$;
-- Permissions
REVOKE ALL ON FUNCTION public.set_preliminary()
FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_preliminary()
FROM anon;
REVOKE ALL ON FUNCTION public.set_preliminary()
FROM authenticated;
GRANT EXECUTE ON FUNCTION public.set_preliminary() TO postgres;
GRANT EXECUTE ON FUNCTION public.set_preliminary() TO service_role;