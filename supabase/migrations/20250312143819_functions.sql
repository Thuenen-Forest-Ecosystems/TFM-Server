-- ============================================================================
-- VIEW: plot_nested_json
-- ============================================================================
-- Creates a nested JSON view of plots with all related data (trees, deadwood, etc.)
-- Optimized using CTEs and subqueries for better performance
-- ============================================================================
--DROP VIEW IF EXISTS public.plot_nested_json;
CREATE OR REPLACE VIEW public.plot_nested_json AS WITH base_plots AS (
        -- Filter plots first to reduce working set
        SELECT *
        FROM inventory_archive.plot
        WHERE interval_name = 'bwi2022'
    ),
    -- Use subqueries for better performance with smaller result sets
    nested_data AS (
        SELECT p.*,
            -- Optimized aggregations using LATERAL joins
            COALESCE(
                (
                    SELECT row_to_json(pc)
                    FROM inventory_archive.plot_coordinates pc
                    WHERE pc.plot_id = p.id
                ),
                '{}'::json
            ) AS plot_coordinates,
            COALESCE(
                (
                    SELECT json_agg(row_to_json(t.*))
                    FROM inventory_archive.tree t
                    WHERE t.plot_id = p.id
                ),
                '[]'::json
            ) AS tree,
            COALESCE(
                (
                    SELECT json_agg(row_to_json(d.*))
                    FROM inventory_archive.deadwood d
                    WHERE d.plot_id = p.id
                ),
                '[]'::json
            ) AS deadwood,
            COALESCE(
                (
                    SELECT json_agg(row_to_json(r.*))
                    FROM inventory_archive.regeneration r
                    WHERE r.plot_id = p.id
                ),
                '[]'::json
            ) AS regeneration,
            COALESCE(
                (
                    SELECT json_agg(row_to_json(s.*))
                    FROM inventory_archive.structure_lt4m s
                    WHERE s.plot_id = p.id
                ),
                '[]'::json
            ) AS structure_lt4m,
            COALESCE(
                (
                    SELECT json_agg(row_to_json(e.*))
                    FROM inventory_archive.edges e
                    WHERE e.plot_id = p.id
                ),
                '[]'::json
            ) AS edges,
            COALESCE(
                (
                    SELECT json_agg(row_to_json(gt4m.*))
                    FROM inventory_archive.structure_gt4m gt4m
                    WHERE gt4m.plot_id = p.id
                ),
                '[]'::json
            ) AS structure_gt4m,
            COALESCE(
                (
                    SELECT json_agg(row_to_json(pl.*))
                    FROM inventory_archive.plot_landmark pl
                    WHERE pl.plot_id = p.id
                ),
                '[]'::json
            ) AS plot_landmark,
            COALESCE(
                (
                    SELECT row_to_json(pos)
                    FROM inventory_archive.position pos
                    WHERE pos.plot_id = p.id
                ),
                '{}'::json
            ) AS position
        FROM base_plots p
    )
SELECT *
FROM nested_data;
-- ============================================================================
-- PERMISSIONS: plot_nested_json
-- ============================================================================
-- Restrict access to postgres and service_role only
REVOKE ALL ON public.plot_nested_json
FROM PUBLIC;
REVOKE ALL ON public.plot_nested_json
FROM anon;
REVOKE ALL ON public.plot_nested_json
FROM authenticated;
GRANT SELECT ON public.plot_nested_json TO postgres;
GRANT SELECT ON public.plot_nested_json TO service_role;
-- ============================================================================
-- MATERIALIZED VIEW: plot_nested_json_cached
-- ============================================================================
-- Cached version of plot_nested_json for faster queries
-- Must be refreshed manually using refresh_plot_nested_json_cached()
-- ============================================================================
CREATE MATERIALIZED VIEW IF NOT EXISTS plot_nested_json_cached AS
SELECT *
FROM public.plot_nested_json;
-- ============================================================================
-- INDEXES: plot_nested_json_cached
-- ============================================================================
CREATE UNIQUE INDEX IF NOT EXISTS idx_plot_nested_json_cached_id ON plot_nested_json_cached (id);
CREATE INDEX IF NOT EXISTS idx_plot_nested_json_cached_cluster ON plot_nested_json_cached (cluster_id);
CREATE INDEX IF NOT EXISTS idx_plot_nested_json_cached_name ON plot_nested_json_cached (plot_name, cluster_name);
-- ============================================================================
-- PERMISSIONS: plot_nested_json_cached
-- ============================================================================
-- Restrict access to postgres and service_role only
REVOKE ALL ON plot_nested_json_cached
FROM PUBLIC;
REVOKE ALL ON plot_nested_json_cached
FROM anon;
REVOKE ALL ON plot_nested_json_cached
FROM authenticated;
GRANT SELECT ON plot_nested_json_cached TO postgres;
GRANT SELECT ON plot_nested_json_cached TO service_role;
-- ============================================================================
-- FUNCTION: refresh_plot_nested_json_cached
-- ============================================================================
-- Refreshes the materialized view with latest data
-- Usage: SELECT public.refresh_plot_nested_json_cached();
-- ============================================================================
CREATE OR REPLACE FUNCTION public.refresh_plot_nested_json_cached() RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$ BEGIN REFRESH MATERIALIZED VIEW plot_nested_json_cached;
END;
$$;
-- Permissions for refresh_plot_nested_json_cached
REVOKE ALL ON FUNCTION public.refresh_plot_nested_json_cached()
FROM PUBLIC;
REVOKE ALL ON FUNCTION public.refresh_plot_nested_json_cached()
FROM anon;
REVOKE ALL ON FUNCTION public.refresh_plot_nested_json_cached()
FROM authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_plot_nested_json_cached() TO postgres;
GRANT EXECUTE ON FUNCTION public.refresh_plot_nested_json_cached() TO service_role;
-- ============================================================================
-- FUNCTION: get_plot_nested_json_by_id
-- ============================================================================
-- Retrieves nested JSON data for a specific plot from the cached view
-- Usage: SELECT public.get_plot_nested_json_by_id('plot-uuid', 123, 456);
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_plot_nested_json_by_id(
        p_plot_id UUID,
        p_cluster_name INTEGER DEFAULT NULL,
        p_plot_name INTEGER DEFAULT NULL
    ) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public,
    inventory_archive AS $$
DECLARE result jsonb;
BEGIN
SELECT row_to_json(t)::jsonb INTO result
FROM public.plot_nested_json_cached t
WHERE t.cluster_name = p_cluster_name
    AND t.plot_name = p_plot_name;
RETURN result;
END;
$$;
-- Permissions for get_plot_nested_json_by_id
REVOKE ALL ON FUNCTION public.get_plot_nested_json_by_id(UUID, INTEGER, INTEGER)
FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_plot_nested_json_by_id(UUID, INTEGER, INTEGER)
FROM anon;
REVOKE ALL ON FUNCTION public.get_plot_nested_json_by_id(UUID, INTEGER, INTEGER)
FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_plot_nested_json_by_id(UUID, INTEGER, INTEGER) TO postgres;
GRANT EXECUTE ON FUNCTION public.get_plot_nested_json_by_id(UUID, INTEGER, INTEGER) TO service_role;
-- ============================================================================
-- FUNCTION: fill_previous_properties (TRIGGER FUNCTION)
-- ============================================================================
-- Automatically fills previous_properties field with plot data when a record
-- is inserted or updated. Uses the cached plot_nested_json view for performance.
-- ============================================================================
CREATE OR REPLACE FUNCTION fill_previous_properties() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public,
    inventory_archive AS $$
DECLARE plot_data jsonb;
position_data jsonb;
BEGIN NEW.message := COALESCE(NEW.message, '') || 'Trigger fired for ' || TG_OP || ' operation';
NEW.previous_properties := '{}'::jsonb;
NEW.previous_position_data := '{}'::jsonb;
IF NEW.plot_id IS NOT NULL THEN BEGIN -- Use the function instead of direct view query for better caching
SELECT public.get_plot_nested_json_by_id(NEW.plot_id, NEW.cluster_name, NEW.plot_name) INTO plot_data;
IF plot_data IS NOT NULL THEN NEW.previous_properties := plot_data;
NEW.message := 'Plot data found and set';
ELSE NEW.message := 'No plot data found';
END IF;
EXCEPTION
WHEN OTHERS THEN NEW.message := 'Error: ' || SQLERRM;
RAISE NOTICE 'Error fetching plot data for %: %',
NEW.plot_id,
SQLERRM;
END;
-- Populate previous_position_data from inventory_archive
BEGIN
SELECT json_object_agg(
        p.interval_name,
        json_build_object(
            'longitude_median',
            ST_X(pos.position_median),
            'latitude_median',
            ST_Y(pos.position_median),
            'longitude_mean',
            ST_X(pos.position_mean),
            'latitude_mean',
            ST_Y(pos.position_mean),
            'hdop_mean',
            pos.hdop_mean,
            'pdop_mean',
            pos.pdop_mean,
            'satellites_count_mean',
            pos.satellites_count_mean,
            'measurement_count',
            pos.measurement_count,
            'rtcm_age',
            pos.rtcm_age,
            'start_measurement',
            pos.start_measurement,
            'stop_measurement',
            pos.stop_measurement,
            'device_gnss',
            pos.device_gnss,
            'quality',
            pos.quality
        )
    ) INTO position_data
FROM inventory_archive.plot p
    JOIN inventory_archive.position pos ON pos.plot_id = p.id
WHERE p.cluster_name = NEW.cluster_name
    AND p.plot_name = NEW.plot_name;
IF position_data IS NOT NULL THEN NEW.previous_position_data := position_data;
END IF;
EXCEPTION
WHEN OTHERS THEN RAISE NOTICE 'Error fetching position data for %: %',
NEW.plot_id,
SQLERRM;
END;
ELSE NEW.message := 'plot_id IS NULL';
END IF;
RETURN NEW;
END;
$$;
-- ============================================================================
-- TRIGGER: before_record_insert_or_update
-- ============================================================================
-- Fires before INSERT or UPDATE to populate previous_properties field
-- ============================================================================
DROP TRIGGER IF EXISTS before_record_insert_or_update ON public.records;
CREATE TRIGGER before_record_insert_or_update BEFORE
INSERT
    OR
UPDATE OF previous_properties_updated_at,
    plot_id ON public.records FOR EACH ROW EXECUTE FUNCTION fill_previous_properties();
-- ============================================================================
-- FUNCTION: handle_record_changes (TRIGGER FUNCTION)
-- ============================================================================
-- Backs up record data to record_changes table every time a record is updated
-- Preserves history of all changes for audit purposes
-- ============================================================================
CREATE OR REPLACE FUNCTION public.handle_record_changes() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$ BEGIN -- Insert a record into the record_changes table
INSERT INTO public.record_changes (
        id,
        created_at,
        updated_by,
        properties,
        previous_properties,
        previous_properties_updated_at,
        is_valid,
        plot_id,
        schema_id,
        schema_name,
        responsible_administration,
        responsible_state,
        responsible_provider,
        responsible_troop,
        validated_at,
        message,
        cluster_id,
        cluster_name,
        plot_name,
        completed_at_troop,
        completed_at_state,
        completed_at_administration,
        updated_at,
        record_id
    )
VALUES (
        gen_random_uuid(),
        NOW(),
        OLD.updated_by,
        OLD.properties,
        OLD.previous_properties,
        OLD.previous_properties_updated_at,
        OLD.is_valid,
        OLD.plot_id,
        OLD.schema_id,
        OLD.schema_name,
        OLD.responsible_administration,
        OLD.responsible_state,
        OLD.responsible_provider,
        OLD.responsible_troop,
        OLD.validated_at,
        OLD.message,
        OLD.cluster_id,
        OLD.cluster_name,
        OLD.plot_name,
        OLD.completed_at_troop,
        OLD.completed_at_state,
        OLD.completed_at_administration,
        OLD.updated_at,
        OLD.id
    );
RETURN NEW;
END;
$$;
-- ============================================================================
-- TRIGGER: on_record_updated
-- ============================================================================
-- Archives record changes to record_changes table on specific field updates
-- ============================================================================
DROP TRIGGER IF EXISTS on_record_updated ON public.records;
CREATE TRIGGER on_record_updated
AFTER
UPDATE OF is_valid,
    completed_at_troop,
    completed_at_state,
    completed_at_administration,
    responsible_provider,
    responsible_troop,
    record_changes_id ON public.records FOR EACH ROW EXECUTE FUNCTION public.handle_record_changes();
-- ============================================================================
-- FUNCTION: validate_json_properties_by_schema (DEPRECATED)
-- ============================================================================
-- Validates properties JSON against a schema definition
-- NOTE: This function is deprecated and kept for backward compatibility
-- ============================================================================
CREATE OR REPLACE FUNCTION public.validate_json_properties_by_schema(schema_id uuid, properties jsonb) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE schema_def json;
-- Changed to jsonb
BEGIN -- Get the schema definition
SELECT schema INTO schema_def
FROM public.schemas
WHERE id = schema_id;
-- Cast to jsonb
-- Check if schema_def is null (schema not found) before calling jsonb_matches_schema
IF schema_def IS NULL THEN RETURN FALSE;
-- Or handle the error as needed (e.g., RAISE EXCEPTION)
END IF;
-- Check if properties is null or empty
IF properties IS NULL
OR properties = '{}'::jsonb THEN RETURN TRUE;
-- Or FALSE, depending on your requirements
END IF;
return extensions.jsonb_matches_schema(schema := schema_def, instance := properties);
END;
$$;
-- ============================================================================
-- FUNCTION: validate_record_properties (TRIGGER FUNCTION - DEPRECATED)
-- ============================================================================
-- Validates record properties and sets is_valid flag
-- NOTE: This function is deprecated and kept for backward compatibility
-- ============================================================================
CREATE OR REPLACE FUNCTION public.validate_record_properties() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$ BEGIN
SELECT id INTO NEW.schema_id
FROM public.schemas
WHERE interval_name = NEW.schema_name
    AND is_visible = true
ORDER BY created_at DESC
LIMIT 1;
-- Only validate if both schema_id and properties are present
IF NEW.schema_name IS NOT NULL
AND NEW.properties IS NOT NULL
AND jsonb_typeof(NEW.properties) = 'object' THEN -- Get Schema ID from interval_name, selecting the latest
SELECT id INTO NEW.schema_id
FROM public.schemas
WHERE interval_name = NEW.schema_name
    AND is_visible = true
ORDER BY created_at DESC
LIMIT 1;
-- Check if the JSON data is valid against the schema
NEW.is_valid := public.validate_json_properties_by_schema(NEW.schema_id, NEW.properties);
ELSE -- If either schema_id or properties is missing, mark as invalid
NEW.is_valid := FALSE;
END IF;
RETURN NEW;
END;
$$;
-- ============================================================================
-- FUNCTION: add_plot_ids_to_records
-- ============================================================================
-- Populates the records table with plots from inventory_archive
-- Filters plots based on grid_density, federal_state, sampling_stratum, and training status
-- Processes in batches to avoid performance issues
-- Usage: SELECT public.add_plot_ids_to_records('schema-uuid', 1000);
-- ============================================================================
DROP FUNCTION IF EXISTS public.add_plot_ids_to_records;
CREATE OR REPLACE FUNCTION public.add_plot_ids_to_records(
        p_schema_id UUID,
        p_batch_size INTEGER DEFAULT 1000
    ) RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public,
    inventory_archive AS $$
DECLARE batch_count INTEGER := 0;
root_org_id uuid;
total_processed INTEGER := 0;
BEGIN RAISE NOTICE 'Starting bulk insert/update of plot records...';
ALTER TABLE public.records DISABLE TRIGGER before_record_insert_or_update;
ALTER TABLE public.records DISABLE TRIGGER on_record_updated;
SELECT id INTO root_org_id
FROM public.organizations
WHERE type = 'root'
LIMIT 1;
RAISE NOTICE 'Root organization ID: %', root_org_id;
LOOP WITH eligible_plots AS (
    SELECT p.id,
        p.plot_name,
        p.cluster_name,
        p.cluster_id
    FROM inventory_archive.plot p
        JOIN inventory_archive.cluster c ON p.cluster_id = c.id
    WHERE (
            (
                c.grid_density in (64, 256)
                and p.federal_state in (1, 2, 4, 8, 9, 13)
            )
            or (
                c.grid_density in (16, 32, 64, 256)
                and p.federal_state in (5, 6, 7, 10, 16)
            )
            or (
                c.grid_density in (4, 8, 16, 32, 64, 256)
                and p.federal_state in (11, 12, 14, 15)
            )
            or p.sampling_stratum in (308, 316)
            or c.is_training = true
        )
        AND p.interval_name = 'bwi2022'
    ORDER BY p.id
    LIMIT p_batch_size OFFSET total_processed
)
INSERT INTO public.records (
        plot_id,
        schema_id,
        plot_name,
        cluster_name,
        cluster_id,
        responsible_administration
    )
SELECT id,
    p_schema_id,
    plot_name,
    cluster_name,
    cluster_id,
    root_org_id
FROM eligible_plots ON CONFLICT (cluster_name, plot_name) DO
UPDATE
SET plot_id = EXCLUDED.plot_id,
    schema_id = EXCLUDED.schema_id,
    cluster_id = EXCLUDED.cluster_id,
    responsible_administration = EXCLUDED.responsible_administration,
    updated_at = NOW();
GET DIAGNOSTICS batch_count = ROW_COUNT;
IF batch_count = 0 THEN EXIT;
END IF;
total_processed := total_processed + batch_count;
RAISE NOTICE 'Processed % records in this batch (total: %)...',
batch_count,
total_processed;
PERFORM pg_sleep(0.1);
END LOOP;
ALTER TABLE public.records ENABLE TRIGGER before_record_insert_or_update;
ALTER TABLE public.records ENABLE TRIGGER on_record_updated;
RAISE NOTICE 'Bulk insert/update completed: % records processed',
total_processed;
RETURN total_processed;
EXCEPTION
WHEN OTHERS THEN
ALTER TABLE public.records ENABLE TRIGGER before_record_insert_or_update;
ALTER TABLE public.records ENABLE TRIGGER on_record_updated;
RAISE NOTICE 'Error in bulk insert/update: %',
SQLERRM;
RAISE;
END;
$$;
-- Permissions for add_plot_ids_to_records
REVOKE ALL ON FUNCTION public.add_plot_ids_to_records(UUID, INTEGER)
FROM PUBLIC;
REVOKE ALL ON FUNCTION public.add_plot_ids_to_records(UUID, INTEGER)
FROM anon;
REVOKE ALL ON FUNCTION public.add_plot_ids_to_records(UUID, INTEGER)
FROM authenticated;
GRANT EXECUTE ON FUNCTION public.add_plot_ids_to_records(UUID, INTEGER) TO postgres;
GRANT EXECUTE ON FUNCTION public.add_plot_ids_to_records(UUID, INTEGER) TO service_role;
-- ============================================================================
-- VIEW: view_records_details
-- ============================================================================
-- Comprehensive view joining records with plot data from multiple intervals
-- Includes cluster information and coordinates
-- ============================================================================
DROP VIEW IF EXISTS public.view_records_details;
CREATE OR REPLACE VIEW public.view_records_details AS
SELECT r.*,
    -- Add the plot_coordinates to the view
    p_coordinates.center_location,
    p_bwi.federal_state,
    p_bwi.growth_district,
    p_bwi.forest_status AS forest_status_bwi2022,
    p_bwi.accessibility,
    p_bwi.forest_office,
    p_bwi.ffh_forest_type_field,
    p_bwi.property_type,
    p_ci2017.forest_status AS forest_status_ci2017,
    p_ci2012.forest_status AS forest_status_ci2012,
    -- Add cluster_status from inventory_archive.cluster
    c.cluster_status,
    c.cluster_situation,
    c.state_responsible,
    c.states_affected,
    c.is_training,
    c.grid_density
FROM public.records r
    LEFT JOIN inventory_archive.plot p_bwi ON r.plot_name = p_bwi.plot_name
    AND r.cluster_name = p_bwi.cluster_name
    AND p_bwi.interval_name = 'bwi2022'
    LEFT JOIN inventory_archive.plot_coordinates p_coordinates ON p_bwi.id = p_coordinates.plot_id
    LEFT JOIN inventory_archive.plot p_ci2017 ON p_bwi.plot_name = p_ci2017.plot_name
    AND p_bwi.cluster_name = p_ci2017.cluster_name
    AND p_ci2017.interval_name = 'ci2017'
    LEFT JOIN inventory_archive.plot p_ci2012 ON p_bwi.plot_name = p_ci2012.plot_name
    AND p_bwi.cluster_name = p_ci2012.cluster_name
    AND p_ci2012.interval_name = 'bwi2012'
    LEFT JOIN inventory_archive.cluster c ON r.cluster_name = c.cluster_name;
-- ============================================================================
-- PERMISSIONS: view_records_details
-- ============================================================================
-- Only authenticated users can access this view
REVOKE ALL ON public.view_records_details
FROM PUBLIC;
REVOKE ALL ON public.view_records_details
FROM anon;
GRANT SELECT ON public.view_records_details TO authenticated;
-- ============================================================================
-- INDEXES: Performance optimization for view_records_details
-- ============================================================================
-- Indexes on underlying tables to improve view query performance
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_records_responsible_administration ON public.records (responsible_administration);
CREATE INDEX IF NOT EXISTS idx_records_responsible_state ON public.records (responsible_state);
CREATE INDEX IF NOT EXISTS idx_records_responsible_provider ON public.records (responsible_provider);
CREATE INDEX IF NOT EXISTS idx_records_responsible_troop ON public.records (responsible_troop);
CREATE INDEX IF NOT EXISTS idx_records_cluster_id ON public.records (cluster_id);
CREATE INDEX IF NOT EXISTS idx_records_plot_id ON public.records (plot_id);
CREATE INDEX IF NOT EXISTS idx_plot_id_interval ON inventory_archive.plot (id, interval_name);
CREATE INDEX IF NOT EXISTS idx_plot_cluster_name ON inventory_archive.plot (cluster_name, plot_name, interval_name);
CREATE INDEX IF NOT EXISTS idx_cluster_id ON inventory_archive.cluster (id);
CREATE INDEX IF NOT EXISTS idx_plot_coordinates_plot_id ON inventory_archive.plot_coordinates (plot_id);
-- ============================================================================
-- FUNCTION: batch_update_records
-- ============================================================================
-- Updates previous_properties for records in batches
-- Processes records that are NULL, empty, or older than 1 day
-- Usage: SELECT public.batch_update_records(1000);
-- ============================================================================
DROP FUNCTION IF EXISTS public.batch_update_records;
CREATE OR REPLACE FUNCTION public.batch_update_records(batch_size INTEGER) RETURNS VOID AS $$
DECLARE processed INTEGER := 0;
rows_updated INTEGER;
BEGIN -- Disable the validation trigger to avoid unnecessary validation during batch update
ALTER TABLE public.records DISABLE TRIGGER trigger_validation_version_change;
LOOP -- Update only rows that have not yet been processed in previous runs
UPDATE public.records
SET previous_properties_updated_at = NOW(),
    plot_id = plot_id
WHERE id IN (
        SELECT id
        FROM public.records
        WHERE previous_properties IS NULL
            OR -- empty
            previous_properties = '{}'::jsonb
            OR -- empty
            previous_properties_updated_at IS NULL
            OR previous_properties_updated_at < NOW() - INTERVAL '1 day'
        ORDER BY id
        LIMIT batch_size
    );
GET DIAGNOSTICS rows_updated = ROW_COUNT;
IF rows_updated = 0 THEN EXIT;
END IF;
processed := processed + rows_updated;
RAISE NOTICE 'Processed % records total',
processed;
PERFORM pg_sleep(0.1);
END LOOP;
RAISE NOTICE 'Finished processing % records total',
processed;
-- Re-enable the validation trigger
ALTER TABLE public.records ENABLE TRIGGER trigger_validation_version_change;
END;
$$ LANGUAGE plpgsql;
-- Permissions for batch_update_records
REVOKE ALL ON FUNCTION public.batch_update_records(INTEGER)
FROM PUBLIC;
REVOKE ALL ON FUNCTION public.batch_update_records(INTEGER)
FROM anon;
REVOKE ALL ON FUNCTION public.batch_update_records(INTEGER)
FROM authenticated;
GRANT EXECUTE ON FUNCTION public.batch_update_records(INTEGER) TO postgres;
GRANT EXECUTE ON FUNCTION public.batch_update_records(INTEGER) TO service_role;
-- ============================================================================
-- FUNCTION: get_user_clusters
-- ============================================================================
-- Returns all clusters a user has access to based on their organization permissions
-- Checks against responsible_state and responsible_provider fields
-- ============================================================================
DROP FUNCTION IF EXISTS public.get_user_clusters;
CREATE OR REPLACE FUNCTION public.get_user_clusters() RETURNS TABLE (
        id UUID,
        cluster_name INTEGER,
        state_responsible INTEGER,
        grid_density INTEGER,
        states_affected INTEGER [],
        cluster_status INTEGER,
        cluster_situation INTEGER -- Add any other columns from the `inventory_archive.cluster` table here
    ) AS $$ BEGIN RETURN QUERY
SELECT DISTINCT c.id,
    c.cluster_name,
    c.state_responsible,
    c.grid_density,
    c.states_affected,
    c.cluster_status,
    c.cluster_situation -- Add any other columns you want to return here
FROM inventory_archive.cluster c
    JOIN inventory_archive.plot p ON c.id = p.cluster_id
    JOIN public.records r ON p.id = r.plot_id
    JOIN public.users_permissions up ON (
        up.user_id = auth.uid()
        AND (
            r.responsible_state = up.organization_id
            OR r.responsible_provider = up.organization_id
        )
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
-- Permissions for get_user_clusters
REVOKE ALL ON FUNCTION public.get_user_clusters()
FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_user_clusters()
FROM anon;
GRANT EXECUTE ON FUNCTION public.get_user_clusters() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_clusters() TO postgres;
GRANT EXECUTE ON FUNCTION public.get_user_clusters() TO service_role;
-- ============================================================================
-- VALIDATION FUNCTIONS AND TRIGGERS
-- ============================================================================
-- Functions to call external Edge Function for record validation
-- ============================================================================
-- ============================================================================
-- FUNCTION: call_validation_function
-- ============================================================================
-- Calls Supabase Edge Function to validate record properties
-- Returns validation_errors and plausibility_errors as JSONB
-- ============================================================================
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
BEGIN -- Construct the Edge Function URL
function_url := current_setting('app.settings.supabase_functions_url', true) || '/validate-record';
-- If the setting is not available, use a default (adjust as needed)
IF function_url IS NULL
OR function_url = '/validate-record' THEN function_url := 'https://ci.thuenen.de/functions/v1/validate-record';
END IF;
-- Get the Supabase service role key for authorization
service_role_key := current_setting('app.settings.service_role_key', true);
-- get public.schema.directory from p_schema_id First
SELECT directory INTO version_directory
FROM public.schemas
WHERE id = p_schema_id;
-- Prepare the payload as a JSON string
payload := jsonb_build_object(
    'properties',
    p_properties,
    'previous_properties',
    p_previous_properties,
    'validation_version',
    version_directory
)::text;
-- Call the Edge Function using http extension with correct signature
--SELECT * INTO response FROM http_post(
--    function_url,
--    payload,
--    'application/json'
--);
-- Call the Edge Function using http() with headers
SELECT * INTO response
FROM http(
        (
            'POST',
            function_url,
            ARRAY [
            http_header('Authorization', 'Bearer ' || COALESCE(service_role_key, ''))
        ],
            'application/json',
            payload
        )::http_request
    );
-- Check if the request was successful
IF response.status >= 200
AND response.status < 300 THEN validation_result := response.content::jsonb;
ELSE -- Handle HTTP errors
debug := format(
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
WHEN OTHERS THEN -- Capture the error message and debug information
debug := 'Error calling Edge Function: ' || SQLERRM;
-- Log the error for debugging purposes
RAISE NOTICE 'Validation function error: %',
debug;
-- Return error response if the function call fails
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
-- Permissions for call_validation_function
REVOKE ALL ON FUNCTION public.call_validation_function(jsonb, jsonb, uuid)
FROM PUBLIC;
REVOKE ALL ON FUNCTION public.call_validation_function(jsonb, jsonb, uuid)
FROM anon;
REVOKE ALL ON FUNCTION public.call_validation_function(jsonb, jsonb, uuid)
FROM authenticated;
GRANT EXECUTE ON FUNCTION public.call_validation_function(jsonb, jsonb, uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.call_validation_function(jsonb, jsonb, uuid) TO service_role;
-- ============================================================================
-- FUNCTION: handle_validation_version_change (TRIGGER FUNCTION)
-- ============================================================================
-- Triggers validation when schema_id or properties change
-- Updates validation_errors, is_valid, plausibility_errors, and is_plausible
-- ============================================================================
DROP TRIGGER IF EXISTS trigger_validation_version_change ON public.records;
DROP FUNCTION IF EXISTS public.handle_validation_version_change;
CREATE OR REPLACE FUNCTION public.handle_validation_version_change() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE validation_result jsonb;
BEGIN -- Only proceed if schema_id or properties have actually changed
IF OLD.schema_id IS DISTINCT
FROM NEW.schema_id
    OR OLD.properties IS DISTINCT
FROM NEW.properties THEN -- Call the validation function
SELECT public.call_validation_function(
        NEW.properties,
        NEW.previous_properties,
        NEW.schema_id -- assuming schema_id is used as validation_version uuid
    ) INTO validation_result;
-- Update the validation and plausibility errors
IF validation_result IS NOT NULL THEN NEW.validation_errors := validation_result->'validation_errors';
NEW.is_valid := (NEW.validation_errors = '{}'::jsonb);
-- Set is_valid based on validation_errors
NEW.plausibility_errors := validation_result->'plausibility_errors';
NEW.is_plausible := (NEW.plausibility_errors = '{}'::jsonb);
-- Set is_plausible based on plausibility_errors
END IF;
END IF;
RETURN NEW;
END;
$$;
-- ============================================================================
-- TRIGGER: trigger_validation_version_change
-- ============================================================================
-- Fires on schema_id, properties, or previous_properties updates
-- ============================================================================
CREATE TRIGGER trigger_validation_version_change BEFORE
UPDATE OF schema_id,
    properties,
    previous_properties ON public.records FOR EACH ROW EXECUTE FUNCTION public.handle_validation_version_change();
-- ============================================================================
-- FUNCTION: set_preliminary
-- ============================================================================
-- Sets preliminary properties from previous monitoring interval (bwi2022)
-- Copies field values from inventory_archive.plot to records.properties
-- Reference: https://github.com/Thuenen-Forest-Ecosystems/TFM-Documentation/issues/79
-- Usage: SELECT public.set_preliminary();
-- ============================================================================
DROP FUNCTION IF EXISTS public.set_preliminary;
CREATE OR REPLACE FUNCTION public.set_preliminary() RETURNS VOID LANGUAGE plpgsql AS $$ BEGIN -- Disable validation trigger to avoid unnecessary API calls during bulk update
ALTER TABLE public.records DISABLE TRIGGER trigger_validation_version_change;
-- Update records.properties with values from inventory_archive.plot
UPDATE public.records r
SET properties = jsonb_build_object(
        'ffh',
        p.ffh,
        'coast',
        p.coast,
        'sandy',
        p.sandy,
        'biotope',
        p.biotope,
        'histwald',
        p.histwald,
        'land_use',
        p.land_use,
        'plot_name',
        p.plot_name,
        'biosphaere',
        p.biosphaere,
        'natur_park',
        p.natur_park,
        'cluster_name',
        p.cluster_name,
        'terrain_form',
        p.terrain_form,
        'accessibility',
        p.accessibility,
        'federal_state',
        p.federal_state,
        'forest_office',
        p.forest_office,
        'forest_status',
        p.forest_status,
        'interval_name',
        p.interval_name,
        'marker_status',
        p.marker_status,
        'national_park',
        p.national_park,
        'property_type',
        p.property_type,
        'terrain_slope',
        p.terrain_slope,
        'marker_azimuth',
        p.marker_azimuth,
        'marker_profile',
        p.marker_profile,
        'elevation_level',
        p.elevation_level,
        'ffh_forest_type',
        p.ffh_forest_type,
        'growth_district',
        p.growth_district,
        'marker_distance',
        p.marker_distance,
        'forest_community',
        p.forest_community,
        'sampling_stratum',
        p.sampling_stratum,
        'terrain_exposure',
        p.terrain_exposure,
        'natur_schutzgebiet',
        p.natur_schutzgebiet,
        'vogel_schutzgebiet',
        p.vogel_schutzgebiet,
        'property_size_class',
        p.property_size_class,
        'protected_landscape',
        p.protected_landscape,
        'forest_community_field',
        p.forest_community_field,
        'biogeographische_region',
        p.biogeographische_region,
        'harvest_restriction_nature_reserve',
        p.harvest_restriction_nature_reserve,
        'harvest_restriction_protection_forest',
        p.harvest_restriction_protection_forest,
        'harvest_restriction_recreational_forest',
        p.harvest_restriction_recreational_forest,
        'harvest_restriction_scattered',
        p.harvest_restriction_scattered,
        'harvest_restriction_fragmented',
        p.harvest_restriction_fragmented,
        'harvest_restriction_insufficient_access',
        p.harvest_restriction_insufficient_access,
        'harvest_restriction_wetness',
        p.harvest_restriction_wetness,
        'harvest_restriction_low_yield',
        p.harvest_restriction_low_yield,
        'harvest_restriction_private_conservation',
        p.harvest_restriction_private_conservation,
        'harvest_restriction_other_internalcause',
        p.harvest_restriction_other_internalcause,
        'tree',
        COALESCE(
            (
                SELECT jsonb_agg(
                        jsonb_build_object(
                            'acquisition_date',
                            x.acquisition_date,
                            'interval_name',
                            x.interval_name
                        ) || (to_jsonb(x.t) - 'plot_id')
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
-- Re-enable validation trigger
ALTER TABLE public.records ENABLE TRIGGER trigger_validation_version_change;
END;
$$;
-- Permissions for set_preliminary
REVOKE ALL ON FUNCTION public.set_preliminary()
FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_preliminary()
FROM anon;
REVOKE ALL ON FUNCTION public.set_preliminary()
FROM authenticated;
GRANT EXECUTE ON FUNCTION public.set_preliminary() TO postgres;
GRANT EXECUTE ON FUNCTION public.set_preliminary() TO service_role;
-- ============================================================================
-- FUNCTION: populate_current_troop_members (TRIGGER FUNCTION)
-- ============================================================================
-- Automatically populates current_troop_members with users from the assigned troop
-- when completed_at_troop is set or changed
-- ============================================================================
CREATE OR REPLACE FUNCTION public.populate_current_troop_members() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE troop_user_ids uuid [];
BEGIN -- Only proceed if completed_at_troop is being set (NULL to NOT NULL or changed)
IF NEW.completed_at_troop IS NOT NULL
AND (
    OLD.completed_at_troop IS NULL
    OR OLD.completed_at_troop != NEW.completed_at_troop
)
AND NEW.responsible_troop IS NOT NULL THEN -- Get user_ids from the troop table
SELECT user_ids INTO troop_user_ids
FROM public.troop
WHERE id = NEW.responsible_troop
    AND deleted = false;
-- Update current_troop_members if we found users
IF troop_user_ids IS NOT NULL THEN NEW.current_troop_members := troop_user_ids;
END IF;
END IF;
RETURN NEW;
END;
$$;
-- ============================================================================
-- TRIGGER: trigger_populate_troop_members
-- ============================================================================
-- Fires before INSERT or UPDATE when completed_at_troop changes
-- ============================================================================
DROP TRIGGER IF EXISTS trigger_populate_troop_members ON public.records;
CREATE TRIGGER trigger_populate_troop_members BEFORE
INSERT
    OR
UPDATE OF completed_at_troop ON public.records FOR EACH ROW EXECUTE FUNCTION public.populate_current_troop_members();
-- ============================================================================
-- END OF MIGRATION
-- ============================================================================
-- Run once to populate preliminary data:
-- SELECT public.set_preliminary();