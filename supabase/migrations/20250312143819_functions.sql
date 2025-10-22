--DROP VIEW IF EXISTS public.plot_nested_json;
CREATE OR REPLACE VIEW public.plot_nested_json AS
WITH base_plots AS (
    -- Filter plots first to reduce working set
    SELECT *
    FROM inventory_archive.plot 
    WHERE interval_name = 'bwi2022'
),
-- Use LATERAL joins for better performance with smaller result sets
nested_data AS (
    SELECT 
        p.*,
        -- Optimized aggregations using LATERAL joins
        COALESCE(
            (SELECT row_to_json(pc)
            FROM inventory_archive.plot_coordinates pc 
            WHERE pc.plot_id = p.id), 
            '{}'::json
        ) AS plot_coordinates,
        COALESCE(
            (SELECT json_agg(row_to_json(t.*))
             FROM inventory_archive.tree t 
             WHERE t.plot_id = p.id), 
            '[]'::json
        ) AS tree,
        COALESCE(
            (SELECT json_agg(row_to_json(d.*))
             FROM inventory_archive.deadwood d 
             WHERE d.plot_id = p.id), 
            '[]'::json
        ) AS deadwood,
        COALESCE(
            (SELECT json_agg(row_to_json(r.*))
             FROM inventory_archive.regeneration r 
             WHERE r.plot_id = p.id), 
            '[]'::json
        ) AS regeneration,
        COALESCE(
            (SELECT json_agg(row_to_json(s.*))
             FROM inventory_archive.structure_lt4m s 
             WHERE s.plot_id = p.id), 
            '[]'::json
        ) AS structure_lt4m,
        COALESCE(
            (SELECT json_agg(row_to_json(e.*))
             FROM inventory_archive.edges e 
             WHERE e.plot_id = p.id), 
            '[]'::json
        ) AS edges,
        COALESCE(
            (SELECT json_agg(row_to_json(gt4m.*))
             FROM inventory_archive.structure_gt4m gt4m 
             WHERE gt4m.plot_id = p.id), 
            '[]'::json
        ) AS structure_gt4m,
        COALESCE(
            (SELECT json_agg(row_to_json(pl.*))
             FROM inventory_archive.plot_landmark pl 
             WHERE pl.plot_id = p.id), 
            '[]'::json
        ) AS plot_landmark,
        COALESCE(
            (SELECT row_to_json(pos)
             FROM inventory_archive.position pos 
             WHERE pos.plot_id = p.id), 
            '{}'::json
        ) AS position
    FROM base_plots p
)
SELECT * FROM nested_data;

-- Revoke all permissions from public role to prevent access
REVOKE ALL ON public.plot_nested_json FROM PUBLIC;
REVOKE ALL ON public.plot_nested_json FROM anon;
REVOKE ALL ON public.plot_nested_json FROM authenticated;

GRANT SELECT ON public.plot_nested_json TO postgres;
GRANT SELECT ON public.plot_nested_json TO service_role;

-- Create materialized view for better performance
CREATE MATERIALIZED VIEW IF NOT EXISTS plot_nested_json_cached AS SELECT * FROM public.plot_nested_json;

-- Create better indexes on the materialized view
CREATE UNIQUE INDEX idx_plot_nested_json_cached_id ON plot_nested_json_cached (id);
CREATE INDEX idx_plot_nested_json_cached_cluster ON plot_nested_json_cached (cluster_id);
CREATE INDEX idx_plot_nested_json_cached_name ON plot_nested_json_cached (plot_name, cluster_name);

-- Grant permissions
REVOKE ALL ON plot_nested_json_cached FROM PUBLIC;
REVOKE ALL ON plot_nested_json_cached FROM anon;
REVOKE ALL ON plot_nested_json_cached FROM authenticated;
GRANT SELECT ON plot_nested_json_cached TO postgres;
GRANT SELECT ON plot_nested_json_cached TO service_role;

-- Add a function to refresh the materialized view efficiently
CREATE OR REPLACE FUNCTION public.refresh_plot_nested_json_cached()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW plot_nested_json_cached;
END;
$$;




-- Example: SELECT public.get_plot_nested_json_by_id('8e30e974-3e52-4a9a-8046-08efca2ccae4'); // ci2027
CREATE OR REPLACE FUNCTION public.get_plot_nested_json_by_id(p_plot_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, inventory_archive
AS $$
DECLARE
    result jsonb;
BEGIN

    SELECT row_to_json(t)::jsonb
    INTO result
    FROM public.plot_nested_json_cached t
    WHERE t.id = p_plot_id;

    RETURN result;
    
END;
$$;

-- Create or replace the trigger function
CREATE OR REPLACE FUNCTION fill_previous_properties()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, inventory_archive
AS $$
DECLARE
    plot_data jsonb;
BEGIN
    NEW.message := COALESCE(NEW.message, '') || 'Trigger fired for ' || TG_OP || ' operation';
    NEW.previous_properties := '{}'::jsonb;
    
    IF NEW.plot_id IS NOT NULL THEN
        BEGIN
            -- Use the function instead of direct view query for better caching
            SELECT public.get_plot_nested_json_by_id(NEW.plot_id) INTO plot_data;
            
            IF plot_data IS NOT NULL THEN
                NEW.previous_properties := plot_data;
                NEW.message := 'Plot data found and set';
            ELSE
                NEW.message := 'No plot data found';
            END IF;
        EXCEPTION WHEN OTHERS THEN
            NEW.message := 'Error: ' || SQLERRM;
            RAISE NOTICE 'Error fetching plot data for %: %', NEW.plot_id, SQLERRM;
        END;
    ELSE
        NEW.message := 'plot_id IS NULL';
    END IF;

    RETURN NEW;
END;
$$;

-- Create trigger that fires on INSERT or UPDATE of specific columns
DROP TRIGGER IF EXISTS before_record_insert_or_update ON public.records;
CREATE TRIGGER before_record_insert_or_update
    BEFORE INSERT OR UPDATE OF previous_properties_updated_at, plot_id ON public.records
    FOR EACH ROW
    EXECUTE FUNCTION fill_previous_properties();


--- Backout plot to backup_changes every time plot updates
CREATE OR REPLACE FUNCTION public.handle_record_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Insert a record into the record_changes table
    INSERT INTO public.record_changes (
        id, created_at, updated_by, properties, previous_properties, previous_properties_updated_at,
        is_valid, plot_id, schema_id, schema_name, responsible_administration, responsible_state,
        responsible_provider, responsible_troop, validated_at, message, cluster_id, cluster_name,
        plot_name, completed_at_troop,
        completed_at_state, completed_at_administration, updated_at, record_id
    )
    VALUES (
        gen_random_uuid(), NOW(), OLD.updated_by, OLD.properties, OLD.previous_properties, OLD.previous_properties_updated_at,
        OLD.is_valid, OLD.plot_id, OLD.schema_id, OLD.schema_name, OLD.responsible_administration, OLD.responsible_state,
        OLD.responsible_provider, OLD.responsible_troop, OLD.validated_at, OLD.message, OLD.cluster_id, OLD.cluster_name,
        OLD.plot_name, OLD.completed_at_troop,
        OLD.completed_at_state, OLD.completed_at_administration, OLD.updated_at, OLD.id
    );

    RETURN NEW;
END;
$$;

-- trigger the function every time a plot is updated
DROP TRIGGER IF EXISTS on_record_updated ON public.records;
CREATE TRIGGER on_record_updated
AFTER UPDATE OF is_valid, completed_at_troop, completed_at_state, completed_at_administration, responsible_administration, responsible_state, responsible_provider, responsible_troop, record_changes_id ON public.records
FOR EACH ROW
EXECUTE FUNCTION public.handle_record_changes();





-- First, create a function to validate JSON against schema (deprecated)
CREATE OR REPLACE FUNCTION public.validate_json_properties_by_schema(schema_id uuid, properties jsonb)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    schema_def json; -- Changed to jsonb
BEGIN
    -- Get the schema definition
    SELECT schema INTO schema_def FROM public.schemas WHERE id = schema_id; -- Cast to jsonb
    -- Check if schema_def is null (schema not found) before calling jsonb_matches_schema
    IF schema_def IS NULL THEN
        RETURN FALSE; -- Or handle the error as needed (e.g., RAISE EXCEPTION)
    END IF;
    
    -- Check if properties is null or empty
    IF properties IS NULL OR properties = '{}'::jsonb THEN
        RETURN TRUE; -- Or FALSE, depending on your requirements
    END IF;

    return extensions.jsonb_matches_schema(schema := schema_def, instance := properties);

END;
$$;

-- Create trigger function to validate records and set is_valid flag (deprecated)
CREATE OR REPLACE FUNCTION public.validate_record_properties()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN

    SELECT id INTO NEW.schema_id 
    FROM public.schemas 
    WHERE interval_name = NEW.schema_name AND is_visible = true
    ORDER BY created_at DESC
    LIMIT 1;
    -- Only validate if both schema_id and properties are present
    IF NEW.schema_name IS NOT NULL AND NEW.properties IS NOT NULL AND jsonb_typeof(NEW.properties) = 'object' THEN
        -- Get Schema ID from interval_name, selecting the latest
        SELECT id INTO NEW.schema_id 
        FROM public.schemas 
        WHERE interval_name = NEW.schema_name AND is_visible = true
        ORDER BY created_at DESC
        LIMIT 1;
        -- Check if the JSON data is valid against the schema
        NEW.is_valid := public.validate_json_properties_by_schema(NEW.schema_id, NEW.properties);
    ELSE
        -- If either schema_id or properties is missing, mark as invalid
        NEW.is_valid := FALSE;
    END IF;

    RETURN NEW;
END;
$$;

-- Create or replace the trigger
-- DROP TRIGGER IF EXISTS before_record_insert_update ON public.records;
--CREATE TRIGGER before_record_insert_update
--    BEFORE INSERT OR UPDATE ON public.records
--    FOR EACH ROW EXECUTE FUNCTION public.validate_record_properties();


-- ADD RECORDS

-- Example: SELECT public.add_plot_ids_to_records('79a571c5-e128-4bef-bead-954d9426ae97'); // ci2027
-- Function to get all id from inventory_archive.plot and add one row to public.records (if exists do nothing)
DROP FUNCTION IF EXISTS public.add_plot_ids_to_records;
CREATE OR REPLACE FUNCTION public.add_plot_ids_to_records(p_schema_id UUID, p_batch_size INTEGER DEFAULT 1000)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, inventory_archive
AS $$
DECLARE
    inserted_count INTEGER := 0;
    batch_count INTEGER := 0;
BEGIN
    RAISE NOTICE 'Starting bulk insert of missing plot records...';

    -- Disable specific user-defined triggers to speed up the insert and avoid permission errors.
    RAISE NOTICE 'Disabling user triggers...';
    ALTER TABLE public.records DISABLE TRIGGER before_record_insert_or_update;
    ALTER TABLE public.records DISABLE TRIGGER on_record_updated;
    --ALTER TABLE public.records DISABLE TRIGGER before_record_insert_update;

    LOOP
        -- Insert a batch of missing plots
        WITH missing_plots AS (

            SELECT p.id, p.plot_name, p.cluster_name, p.cluster_id
            FROM inventory_archive.plot p
            JOIN inventory_archive.cluster c ON p.cluster_id = c.id
            WHERE (
                (c.grid_density in (64, 256) and p.federal_state in (1, 2, 4, 8, 9, 13)) -- SH, HH, BB, BW, BY, MV
                or (c.grid_density in (16, 32, 64, 256) and p.federal_state in (5, 6, 7, 10, 16)) -- NW, HE, RP, SL, TH
                or (c.grid_density in (4, 8, 16, 32, 64, 256) and p.federal_state in (11, 12, 14, 15)) -- BE, BB, SN, ST
                or p.sampling_stratum  in (308, 316)
                or c.is_training = true
                ) AND p.interval_name = 'bwi2022'
            AND NOT EXISTS (
                SELECT 1 FROM public.records r 
                WHERE r.plot_id = p.id
            )
            LIMIT p_batch_size

        )
        INSERT INTO public.records (plot_id, schema_id, plot_name, cluster_name, cluster_id)
        SELECT id, p_schema_id, plot_name, cluster_name, cluster_id
        FROM missing_plots
        ON CONFLICT (plot_id) DO NOTHING;

        GET DIAGNOSTICS batch_count = ROW_COUNT;

        -- Exit the loop if no more rows are inserted
        IF batch_count = 0 THEN
            EXIT;
        END IF;

        inserted_count := inserted_count + batch_count;
        RAISE NOTICE 'Inserted % records in this batch...', batch_count;
    END LOOP;

    -- Re-enable triggers after the insert
    RAISE NOTICE 'Re-enabling user triggers...';
    ALTER TABLE public.records ENABLE TRIGGER before_record_insert_or_update;
    ALTER TABLE public.records ENABLE TRIGGER on_record_updated;
    --ALTER TABLE public.records ENABLE TRIGGER before_record_insert_update;

    RAISE NOTICE 'Bulk insert completed: % records inserted', inserted_count;
    RETURN inserted_count;

EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Error in bulk insert: %', SQLERRM;
    RAISE;
END;
$$;

-- If organizations_lose.responsible_organization_id inserted or updates set records.administration_los, records.state_los, records.provider_los, records.troop_los based on organizations.type
-- Function to update records when organizations_lose responsible_organization_id changes
/* 
DROP TRIGGER IF EXISTS trg_update_records_from_organizations_lose ON public.organizations_lose;
DROP FUNCTION IF EXISTS public.update_records_from_organizations_lose_changes;

CREATE OR REPLACE FUNCTION public.update_records_from_organizations_lose_changes()
RETURNS TRIGGER AS $$
DECLARE
    org_type text;
BEGIN
    -- Handle when responsible_organization_id is changed
    IF NEW.responsible_organization_id IS DISTINCT FROM OLD.responsible_organization_id THEN
        -- If NEW.responsible_organization_id is NULL, clear the appropriate los fields
        IF NEW.responsible_organization_id IS NULL THEN
            -- Get the old organization type to know which field to clear
            SELECT type INTO org_type
            FROM organizations
            WHERE id = OLD.organization_id;
            
            -- Clear the appropriate los field based on old organization type
            CASE org_type
                WHEN 'root' THEN
                    UPDATE records
                    SET responsible_state = NULL, responsible_provider = NULL, responsible_troop = NULL, state_los = NULL, provider_los = NULL, troop_los = NULL
                    WHERE administration_los = OLD.id;

                WHEN 'country' THEN --state
                    UPDATE records
                    SET responsible_provider = NULL, responsible_troop = NULL, provider_los = NULL, troop_los = NULL
                    WHERE state_los = OLD.id;

                WHEN 'provider' THEN
                    UPDATE records
                    SET responsible_troop = NULL, troop_los = NULL
                    WHERE provider_los = OLD.id;

                ELSE
                    -- Handle unknown organization types or do nothing
                    NULL;
            END CASE;
        ELSE
            -- Get the new organization type
            SELECT type INTO org_type
            FROM organizations
            WHERE id = NEW.organization_id;
            
            -- Update records based on new organization type
            CASE org_type
                WHEN 'root' THEN
                    UPDATE records
                    --SET administration_los = NEW.id
                    SET responsible_state = NEW.responsible_organization_id, responsible_provider = NULL, responsible_troop = NULL,
                        state_los = NULL, provider_los = NULL, troop_los = NULL
                    WHERE administration_los = OLD.id;

                WHEN 'country' THEN
                    UPDATE records
                    SET responsible_provider = NEW.responsible_organization_id, responsible_troop = NULL, provider_los = NULL, troop_los = NULL
                    WHERE state_los = OLD.id;

                WHEN 'provider' THEN
                    UPDATE records
                    SET responsible_troop = NEW.troop_id, troop_los = NULL
                    WHERE provider_los = OLD.id;

                ELSE
                    -- Handle unknown organization types or do nothing
                    NULL;
            END CASE;
        END IF;
    END IF;

    IF NEW.troop_id IS DISTINCT FROM OLD.troop_id THEN
        SELECT type INTO org_type
        FROM organizations
        WHERE id = NEW.organization_id;
        
        -- Update records based on new organization type
        CASE org_type
            WHEN 'root' THEN
                UPDATE records
                SET responsible_troop = NEW.troop_id
                WHERE administration_los = NEW.id;

            WHEN 'country' THEN
                UPDATE records
                SET responsible_troop = NEW.troop_id
                WHERE state_los = NEW.id;

            WHEN 'provider' THEN
                UPDATE records
                SET responsible_troop = NEW.troop_id
                WHERE provider_los = NEW.id;

            ELSE
                -- Handle unknown organization types or do nothing
                NULL;
        END CASE;
        
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATE LOS information in Records

CREATE TRIGGER trg_update_records_from_organizations_lose_changes
AFTER UPDATE OF responsible_organization_id, troop_id ON public.organizations_lose
FOR EACH ROW
 EXECUTE FUNCTION public.update_records_from_organizations_lose_changes();*/


-- If update organizations_lose.responsible_organization_id changes or update responsible_state and/or responsible_provider of records where administration_los, state_los or provider_los is equal id
-- on change organizations_lose
-- Function to update responsible_state and responsible_provider based on organizations_lose changes
/*
CREATE OR REPLACE FUNCTION public.update_records_responsible_fields_from_organizations_lose()
RETURNS TRIGGER AS $$
DECLARE
    org_type text;
BEGIN
    -- Handle when responsible_organization_id is changed
    IF NEW.responsible_organization_id IS DISTINCT FROM OLD.responsible_organization_id THEN
        -- Get the organization type from the organizations_lose record's organization_id
        SELECT o.type INTO org_type
        FROM organizations o
        WHERE o.id = NEW.organization_id;
        
        -- Update records based on which los field matches this organizations_lose id
        -- and set the appropriate responsible field based on organization type
        
        -- For administration_los matches
        IF org_type = 'root' THEN
            UPDATE records
            SET responsible_state = NEW.responsible_organization_id, responsible_provider = NULL, responsible_troop = NULL
            WHERE administration_los = NEW.id;

        END IF;
        
        -- For state_los matches  
        IF org_type = 'country' THEN
            UPDATE records
            SET responsible_provider = NEW.responsible_organization_id, responsible_troop = NULL
            WHERE state_los = NEW.id;
        END IF;
        
        -- For troop_los matches (if troop type exists)
        IF org_type = 'troop' THEN
            UPDATE records
            SET responsible_troop = NEW.troop_id, troop_los = NULL
            WHERE troop_los = OLD.id;
        END IF;
        
        -- If responsible_organization_id is set to NULL, clear the corresponding responsible fields
        IF NEW.responsible_organization_id IS NULL THEN
            CASE org_type
                WHEN 'root' THEN
                    UPDATE records
                    SET responsible_state = NULL, responsible_provider = NULL, responsible_troop = NULL
                    WHERE administration_los = NEW.id;

                WHEN 'country' THEN
                    UPDATE records
                    SET responsible_provider = NULL, responsible_troop = NULL
                    WHERE state_los = NEW.id;
                    
                WHEN 'troop' THEN
                    UPDATE records
                    SET responsible_troop = NULL
                    WHERE troop_los = NEW.id;
                ELSE
                    -- Handle unknown organization types or do nothing
                    NULL;
            END CASE;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;*/

-- Create trigger to fire on responsible_organization_id changes in organizations_lose
-- UPDATES Responsible
--DROP TRIGGER IF EXISTS trg_update_records_responsible_fields_from_organizations_lose ON public.organizations_lose;
--CREATE TRIGGER trg_update_records_responsible_fields_from_organizations_lose
--AFTER UPDATE OF responsible_organization_id ON public.organizations_lose
--FOR EACH ROW
--EXECUTE FUNCTION public.update_records_responsible_fields_from_organizations_lose();

-- Function to update responsible fields when los fields in records are updated
/*CREATE OR REPLACE FUNCTION public.update_records_responsible_fields_from_los_changes()
RETURNS TRIGGER AS $$
DECLARE
    org_type text;
    responsible_org_id uuid;
BEGIN
    -- Handle administration_los changes
    IF NEW.administration_los IS DISTINCT FROM OLD.administration_los THEN
        -- If administration_los changes, set state_los and provider_los to NULL
        NEW.state_los := NULL;
        NEW.responsible_state := NULL;
        NEW.provider_los := NULL;
        NEW.responsible_provider := NULL;
        NEW.troop_los := NULL;
        NEW.responsible_troop := NULL;

        IF NEW.administration_los IS NOT NULL THEN
            -- Get responsible_organization_id from organizations_lose
            SELECT ol.responsible_organization_id INTO responsible_org_id
            FROM organizations_lose ol
            WHERE ol.id = NEW.administration_los;
            
            -- Update responsible_state
            NEW.responsible_state := responsible_org_id;
        END IF;
    END IF;
    
    -- Handle state_los changes
    IF NEW.state_los IS DISTINCT FROM OLD.state_los THEN
        -- If state_los changes, set provider_los to NULL
        NEW.provider_los := NULL;
        NEW.responsible_provider := NULL;
        NEW.troop_los := NULL;
        NEW.responsible_troop := NULL;

        IF NEW.state_los IS NOT NULL THEN
            -- Get responsible_organization_id from organizations_lose
            SELECT ol.responsible_organization_id INTO responsible_org_id
            FROM organizations_lose ol
            WHERE ol.id = NEW.state_los;
            
            -- Update responsible_state
            NEW.responsible_provider := responsible_org_id;
            --NEW.responsible_state := responsible_org_id;
        END IF;
    END IF;
    
    -- Handle provider_los changes
    IF NEW.provider_los IS DISTINCT FROM OLD.provider_los THEN

        NEW.responsible_troop := NULL;

        IF NEW.provider_los IS NOT NULL THEN
            -- Get responsible_organization_id from organizations_lose
            SELECT ol.troop_id INTO responsible_org_id
            FROM organizations_lose ol
            WHERE ol.id = NEW.provider_los;
            
            -- Update responsible_provider
            NEW.responsible_troop := responsible_org_id;
        END IF;
    END IF;
    
    -- Handle troop_los changes (if applicable)
    --IF NEW.troop_los IS DISTINCT FROM OLD.troop_los THEN
    --    IF NEW.troop_los IS NOT NULL THEN
    --        -- Get responsible_organization_id from organizations_lose
    --        SELECT ol.responsible_organization_id INTO responsible_org_id
    --        FROM organizations_lose ol
    --        WHERE ol.id = NEW.troop_los;
    --        
    --        -- Update responsible_troop
    --        NEW.responsible_troop := responsible_org_id;
    --    ELSE
    --        -- Clear responsible_troop if troop_los is set to NULL
    --        NEW.responsible_troop := NULL;
    --    END IF;
    --END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to fire on los field changes in records
DROP TRIGGER IF EXISTS trg_update_records_responsible_fields_from_los_changes ON public.records;
CREATE TRIGGER trg_update_records_responsible_fields_from_los_changes
BEFORE UPDATE OF administration_los, state_los, provider_los, troop_los ON public.records
FOR EACH ROW
EXECUTE FUNCTION public.update_records_responsible_fields_from_los_changes();*/


-- Function to update responsible_state based on administration_los changes
/*CREATE OR REPLACE FUNCTION public.update_records_responsible_state_from_admin_los()
RETURNS TRIGGER AS $$
BEGIN
    -- Handle when administration_los is added or changed
    IF NEW.administration_los IS NOT NULL AND NEW.administration_los IS DISTINCT FROM OLD.administration_los THEN
        -- First try to update responsible_state if responsible_organization_id exists
        UPDATE records
        SET responsible_state = ol.responsible_organization_id
        FROM organizations_lose ol
        WHERE ol.id = NEW.administration_los
          AND records.id = NEW.id
          AND ol.responsible_organization_id IS NOT NULL;
        
        -- If responsible_organization_id is null, check for troop_id and update responsible_troop
        UPDATE records
        SET responsible_troop = ol.troop_id
        FROM organizations_lose ol
        WHERE ol.id = NEW.administration_los
          AND records.id = NEW.id
          AND ol.responsible_organization_id IS NULL
          AND ol.troop_id IS NOT NULL;
    END IF;
    
    -- Handle when administration_los is removed (set to NULL)
    IF OLD.administration_los IS NOT NULL AND NEW.administration_los IS NULL THEN
        -- Clear the responsible_state that was set by the old administration_los
        UPDATE records
        SET responsible_state = NULL
        FROM organizations_lose ol
        WHERE ol.id = OLD.administration_los
          AND records.id = NEW.id
          AND records.responsible_state = ol.responsible_organization_id;
          
        -- Clear the responsible_troop that was set by the old administration_los
        UPDATE records
        SET responsible_troop = NULL
        FROM organizations_lose ol
        WHERE ol.id = OLD.administration_los
          AND records.id = NEW.id
          AND records.responsible_troop = ol.troop_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;*/

-- Create trigger to fire on administration_los changes
--DROP TRIGGER IF EXISTS trg_update_responsible_state_from_admin_los ON public.records;
--CREATE TRIGGER trg_update_responsible_state_from_admin_los
--AFTER UPDATE OF administration_los ON public.records
--FOR EACH ROW
--EXECUTE FUNCTION public.update_records_responsible_state_from_admin_los();



DROP VIEW IF EXISTS public.view_records_details;
CREATE OR REPLACE VIEW public.view_records_details AS
SELECT 
    r.*,
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
LEFT JOIN inventory_archive.plot p_bwi 
    ON r.plot_id = p_bwi.id AND p_bwi.interval_name = 'bwi2022'
LEFT JOIN inventory_archive.plot_coordinates p_coordinates 
    ON r.plot_id = p_coordinates.plot_id
LEFT JOIN inventory_archive.plot p_ci2017 
    ON p_bwi.plot_name = p_ci2017.plot_name AND p_bwi.cluster_name = p_ci2017.cluster_name AND p_ci2017.interval_name = 'ci2017'
LEFT JOIN inventory_archive.plot p_ci2012 
    ON p_bwi.plot_name = p_ci2012.plot_name AND p_bwi.cluster_name = p_ci2012.cluster_name AND p_ci2012.interval_name = 'bwi2012'
LEFT JOIN inventory_archive.cluster c
    ON r.cluster_id = c.id;

-- add indexes for better performance
-- Indexes for view_records_details performance
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

-- Only authenticated users can access this view
REVOKE ALL ON public.view_records_details FROM PUBLIC;
REVOKE ALL ON public.view_records_details FROM anon;
GRANT SELECT ON public.view_records_details TO authenticated;


DROP FUNCTION IF EXISTS public.batch_update_records;
CREATE OR REPLACE FUNCTION public.batch_update_records(batch_size INTEGER)
RETURNS VOID AS $$
DECLARE
    processed INTEGER := 0;
    rows_updated INTEGER;
BEGIN
    LOOP
        -- Update only rows that have not yet been processed in previous runs
        UPDATE public.records
        SET previous_properties_updated_at = NOW(),
            plot_id = plot_id
        WHERE id IN (
            SELECT id
            FROM public.records
            WHERE previous_properties IS NULL OR -- empty
                  previous_properties = '{}'::jsonb OR -- empty
                  previous_properties_updated_at IS NULL
            ORDER BY id
            LIMIT batch_size
        );

        GET DIAGNOSTICS rows_updated = ROW_COUNT;

        IF rows_updated = 0 THEN
            EXIT;
        END IF;

        processed := processed + rows_updated;
        RAISE NOTICE 'Processed % records total', processed;

        PERFORM pg_sleep(0.1);
    END LOOP;

    RAISE NOTICE 'Finished processing % records total', processed;
END;
$$ LANGUAGE plpgsql;


-- SELECT public.batch_update_records(1000);


-- Function to get all clusters a user has access to based on their permissions
DROP FUNCTION IF EXISTS public.get_user_clusters;
CREATE OR REPLACE FUNCTION public.get_user_clusters()
RETURNS TABLE (
    id UUID,
    cluster_name INTEGER,
    state_responsible INTEGER,
    grid_density INTEGER,
    states_affected INTEGER[],
    cluster_status INTEGER,
    cluster_situation INTEGER
    -- Add any other columns from the `inventory_archive.cluster` table here
) AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT
        c.id,
        c.cluster_name,
        c.state_responsible,
        c.grid_density,
        c.states_affected,
        c.cluster_status,
        c.cluster_situation
        -- Add any other columns you want to return here
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



--------- Trigger and function to call Supabase Edge Function on validation_version change

-- Create function to call Supabase Edge Function for validation
DROP FUNCTION IF EXISTS public.call_validation_function;
CREATE OR REPLACE FUNCTION public.call_validation_function(
    p_properties jsonb,
    p_previous_properties jsonb,
    p_schema_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    validation_result jsonb;
    function_url text;
    payload text;
    response record;
    version_directory text;
    debug text;
    service_role_key text;
BEGIN
    -- Construct the Edge Function URL
    function_url := current_setting('app.settings.supabase_functions_url', true) || '/validate-record';
    
    -- If the setting is not available, use a default (adjust as needed)
    IF function_url IS NULL OR function_url = '/validate-record' THEN
        function_url := 'https://ci.thuenen.de/functions/v1/validate-record';
    END IF;

    -- Get the Supabase service role key for authorization
    service_role_key := current_setting('app.settings.service_role_key', true);

    -- get public.schema.directory from p_schema_id First
    SELECT directory INTO version_directory FROM public.schemas WHERE id = p_schema_id;

    -- Prepare the payload as a JSON string
    payload := jsonb_build_object(
        'properties', p_properties,
        'previous_properties', p_previous_properties,
        'validation_version', version_directory
    )::text;

    -- Call the Edge Function using http extension with correct signature
    --SELECT * INTO response FROM http_post(
    --    function_url,
    --    payload,
    --    'application/json'
    --);
    -- Call the Edge Function using http() with headers
    SELECT * INTO response FROM http((
        'POST',
        function_url,
        ARRAY[
            http_header('Authorization', 'Bearer ' || COALESCE(service_role_key, ''))
        ],
        'application/json',
        payload
    )::http_request);

    -- Check if the request was successful
    IF response.status >= 200 AND response.status < 300 THEN
        validation_result := response.content::jsonb;
    ELSE
        -- Handle HTTP errors
        debug := format('HTTP Error %s: %s', response.status, response.content);
        RAISE NOTICE 'HTTP request failed: %', debug;
        
        RETURN jsonb_build_object(
            'validation_errors', jsonb_build_object('error', 'HTTP request failed', 'debug', debug),
            'plausibility_errors', jsonb_build_object('error', 'HTTP request failed', 'debug', debug)
        );
    END IF;

    RETURN validation_result;

EXCEPTION WHEN OTHERS THEN
    -- Capture the error message and debug information
    debug := 'Error calling Edge Function: ' || SQLERRM;

    -- Log the error for debugging purposes
    RAISE NOTICE 'Validation function error: %', debug;

    -- Return error response if the function call fails
    RETURN jsonb_build_object(
        'validation_errors', jsonb_build_object('error', 'Validation service unavailable', 'debug', debug),
        'plausibility_errors', jsonb_build_object('error', 'Plausibility service unavailable', 'debug', debug)
    );
END;
$$;

-- Create the trigger
DROP TRIGGER IF EXISTS trigger_validation_version_change ON public.records;

-- Create the trigger function
DROP FUNCTION IF EXISTS public.handle_validation_version_change;
CREATE OR REPLACE FUNCTION public.handle_validation_version_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    validation_result jsonb;
BEGIN
    -- Only proceed if validation_version has actually changed
    IF OLD.schema_id IS DISTINCT FROM NEW.schema_id THEN
        
        -- Call the validation function
        SELECT public.call_validation_function(
            NEW.properties,
            NEW.previous_properties,
            NEW.schema_id -- assuming schema_id is used as validation_version uuid
        ) INTO validation_result;

        -- Update the validation and plausibility errors
        IF validation_result IS NOT NULL THEN
            NEW.validation_errors := validation_result->'validation_errors';
            NEW.is_valid := (NEW.validation_errors = '{}'::jsonb); -- Set is_valid based on validation_errors
            NEW.plausibility_errors := validation_result->'plausibility_errors';
            NEW.is_plausible := (NEW.plausibility_errors = '{}'::jsonb); -- Set is_plausible based on plausibility_errors
        END IF;

    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_validation_version_change
    BEFORE UPDATE OF schema_id, properties, previous_properties ON public.records
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_validation_version_change();



-- SET subgroup of previous monitoring to current monitoring in properties
-- https://github.com/Thuenen-Forest-Ecosystems/TFM-Documentation/issues/79
DROP FUNCTION IF EXISTS public.set_preliminary;
CREATE OR REPLACE FUNCTION public.set_preliminary()
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    -- Update records.properties with values from inventory_archive.plot
    UPDATE public.records r
    SET properties = jsonb_build_object(
        'ffh', p.ffh,
        'coast', p.coast,
        'sandy', p.sandy,
        'biotope', p.biotope,
        'histwald', p.histwald,
        'land_use', p.land_use,
        'plot_name', p.plot_name,
        'biosphaere', p.biosphaere,
        'natur_park', p.natur_park,
        'cluster_name', p.cluster_name,
        'terrain_form', p.terrain_form,
        'accessibility', p.accessibility,
        'federal_state', p.federal_state,
        'forest_office', p.forest_office,
        'forest_status', p.forest_status,
        'interval_name', p.interval_name,
        'marker_status', p.marker_status,
        'national_park', p.national_park,
        'property_type', p.property_type,
        'terrain_slope', p.terrain_slope,
        'marker_azimuth', p.marker_azimuth,
        'marker_profile', p.marker_profile,
        'elevation_level', p.elevation_level,
        'ffh_forest_type', p.ffh_forest_type,
        'growth_district', p.growth_district,
        'marker_distance', p.marker_distance,
        'forest_community', p.forest_community,
        'sampling_stratum', p.sampling_stratum,
        'terrain_exposure', p.terrain_exposure,
        'natur_schutzgebiet', p.natur_schutzgebiet,
        'vogel_schutzgebiet', p.vogel_schutzgebiet,
        'property_size_class', p.property_size_class,
        'protected_landscape', p.protected_landscape,
        'forest_community_field', p.forest_community_field,
        'biogeographische_region', p.biogeographische_region,
        'harvest_restriction_nature_reserve', p.harvest_restriction_nature_reserve,
        'harvest_restriction_protection_forest', p.harvest_restriction_protection_forest,
        'harvest_restriction_recreational_forest', p.harvest_restriction_recreational_forest,
        'harvest_restriction_scattered', p.harvest_restriction_scattered,
        'harvest_restriction_fragmented', p.harvest_restriction_fragmented,
        'harvest_restriction_insufficient_access', p.harvest_restriction_insufficient_access,
        'harvest_restriction_wetness', p.harvest_restriction_wetness,
        'harvest_restriction_low_yield', p.harvest_restriction_low_yield,
        'harvest_restriction_private_conservation', p.harvest_restriction_private_conservation,
        'harvest_restriction_other_internalcause', p.harvest_restriction_other_internalcause
    )
    FROM inventory_archive.plot p
    WHERE r.plot_id = p.id
      AND r.properties = '{}'::jsonb; -- Only update if properties is empty
END;
$$;

-- run once
-- SELECT public.set_preliminary();