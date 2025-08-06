--DROP VIEW IF EXISTS public.plot_nested_json;
CREATE OR REPLACE VIEW public.plot_nested_json AS
WITH p_coords AS (
    SELECT plot_id, json_agg(row_to_json(pc.*)) as data FROM inventory_archive.plot_coordinates pc GROUP BY plot_id
), t_trees AS (
    SELECT plot_id, json_agg(row_to_json(t.*)) as data FROM inventory_archive.tree t GROUP BY plot_id
), d_woods AS (
    SELECT plot_id, json_agg(row_to_json(d.*)) as data FROM inventory_archive.deadwood d GROUP BY plot_id
), r_gens AS (
    SELECT plot_id, json_agg(row_to_json(r.*)) as data FROM inventory_archive.regeneration r GROUP BY plot_id
), s_lt4m AS (
    SELECT plot_id, json_agg(row_to_json(s.*)) as data FROM inventory_archive.structure_lt4m s GROUP BY plot_id
), e_edges AS (
    SELECT plot_id, json_agg(row_to_json(e.*)) as data FROM inventory_archive.edges e GROUP BY plot_id
), s_gt4m AS (
    SELECT plot_id, json_agg(row_to_json(gt4m.*)) as data FROM inventory_archive.structure_gt4m gt4m GROUP BY plot_id
), p_landmarks AS (
    SELECT plot_id, json_agg(row_to_json(pl.*)) as data FROM inventory_archive.plot_landmark pl GROUP BY plot_id
)
SELECT
    p.*,
    COALESCE(pc.data, '[]'::json) AS plot_coordinates,
    COALESCE(tt.data, '[]'::json) AS trees,
    COALESCE(dw.data, '[]'::json) AS deadwoods,
    COALESCE(rg.data, '[]'::json) AS regenerations,
    COALESCE(sl.data, '[]'::json) AS structures_lt4m,
    COALESCE(ee.data, '[]'::json) AS edges,
    COALESCE(s_gt4m.data, '[]'::json) AS structures_gt4m,
    COALESCE(pl.data, '[]'::json) AS landmarks
FROM inventory_archive.plot p
LEFT JOIN p_coords pc ON p.id = pc.plot_id
LEFT JOIN t_trees tt ON p.id = tt.plot_id
LEFT JOIN d_woods dw ON p.id = dw.plot_id
LEFT JOIN r_gens rg ON p.id = rg.plot_id
LEFT JOIN s_lt4m sl ON p.id = sl.plot_id
LEFT JOIN e_edges ee ON p.id = ee.plot_id
LEFT JOIN s_gt4m ON p.id = s_gt4m.plot_id
LEFT JOIN p_landmarks pl ON p.id = pl.plot_id
WHERE p.interval_name = 'bwi2022';

-- Revoke all permissions from public role to prevent access
REVOKE ALL ON public.plot_nested_json FROM PUBLIC;
REVOKE ALL ON public.plot_nested_json FROM anon;
REVOKE ALL ON public.plot_nested_json FROM authenticated;

--CREATE VIEW public.plot_nested_json AS
--SELECT
--    plot.*,
--    
--    -- Use COALESCE to return an empty array ('[]'::json) if no rows are found
--    COALESCE(
--        (
--            SELECT json_agg(row_to_json(plot_coordinates.*))
--            FROM inventory_archive.plot_coordinates
--            WHERE plot_coordinates.plot_id = plot.id
--        ),
--        '[]'::json
--    ) AS plot_coordinates,
--
--    COALESCE(
--        (
--            SELECT json_agg(row_to_json(tree.*))
--            FROM inventory_archive.tree
--            WHERE tree.plot_id = plot.id
--        ),
--        '[]'::json
--    ) AS trees,
--    
--    COALESCE(
--        (
--            SELECT json_agg(row_to_json(deadwood.*))
--            FROM inventory_archive.deadwood
--            WHERE deadwood.plot_id = plot.id
--        ),
--        '[]'::json
--    ) AS deadwoods,
--    
--    COALESCE(
--        (
--            SELECT json_agg(row_to_json(regeneration.*))
--            FROM inventory_archive.regeneration
--            WHERE regeneration.plot_id = plot.id
--        ),
--        '[]'::json
--    ) AS regenerations,
--    
--    COALESCE(
--        (
--            SELECT json_agg(row_to_json(structure_lt4m.*))
--            FROM inventory_archive.structure_lt4m
--            WHERE structure_lt4m.plot_id = plot.id
--        ),
--        '[]'::json
--    ) AS structures_lt4m,
--    
--    COALESCE(
--        (
--            SELECT json_agg(row_to_json(edges.*))
--            FROM inventory_archive.edges
--            WHERE edges.plot_id = plot.id
--        ),
--        '[]'::json
--    ) AS edges
--        
--FROM inventory_archive.plot;




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
    FROM public.plot_nested_json t
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
    RAISE NOTICE 'Trigger firing for % on record with plot_id: %', TG_OP, NEW.plot_id;

    NEW.message := COALESCE(NEW.message, '') || 'Trigger fired for ' || TG_OP || ' operation';

    -- Always ensure previous_properties has a default value
    NEW.previous_properties := '{}'::jsonb;
    
    -- Attempt to get the plot data
    IF NEW.plot_id IS NOT NULL THEN

        BEGIN
            SELECT row_to_json(pnj)::jsonb
            INTO plot_data  -- Missing INTO clause
            FROM public.plot_nested_json pnj
            WHERE pnj.id = NEW.plot_id;

            
            IF plot_data IS NOT NULL THEN
                NEW.previous_properties := plot_data;
                NEW.message := 'Plot data found and set in previous_properties';
            ELSE
                NEW.message := 'No plot data found';
                RAISE NOTICE 'No plot data found for plot_id: %', NEW.plot_id;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Error fetching plot data: %', SQLERRM;
            NEW.message := 'Error fetching plot data: ' || SQLERRM;
            -- previous_properties already has default value
        END;
    ELSE
        NEW.message := 'NEW.plot_id IS NULL';
    END IF;
    
    -- Set state_responsible if needed (won't override existing value)
    --IF NEW.state_responsible IS NULL THEN
    --    SELECT state_responsible INTO NEW.state_responsible
    --    FROM inventory_archive.cluster c
    --    JOIN inventory_archive.plot p ON p.cluster_id = c.id
    --    WHERE p.id = NEW.plot_id;
    --END IF;

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Error in trigger: % %', SQLSTATE, SQLERRM;
    RETURN NEW; -- Still allow the operation to proceed
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
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- only if is_valid change and old is_valid exists
  if new.is_valid != old.is_valid and old.is_valid then
    -- Check if the new properties are different from the old properties
    if new.properties IS DISTINCT FROM old.properties 
       AND new.properties IS NOT NULL 
       AND new.properties != '{}'::jsonb 
       AND jsonb_typeof(new.properties) = 'object'
       AND jsonb_object_keys(new.properties) IS NOT NULL then
      -- Insert a record into the record_changes table
      INSERT INTO public.record_changes (updated_by, properties, schema_name, previous_properties, previous_properties_updated_at, is_valid, supervisor_id, plot_id, troop_id, schema_id)
      VALUES (NEW.updated_by, NEW.properties, NEW.schema_name, OLD.properties, OLD.previous_properties_updated_at, OLD.is_valid, OLD.supervisor_id, OLD.plot_id, OLD.troop_id, OLD.schema_id);
    end if;
  end if;
  return new;
end;
$$;

-- trigger the function every time a plot is updated
DROP TRIGGER IF EXISTS on_record_updated ON public.records;
create trigger on_record_updated
  after update on public.records
  for each row execute procedure public.handle_record_changes();





-- First, create a function to validate JSON against schema
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

-- Create trigger function to validate records and set is_valid flag
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
DROP TRIGGER IF EXISTS before_record_insert_update ON public.records;
CREATE TRIGGER before_record_insert_update
    BEFORE INSERT OR UPDATE ON public.records
    FOR EACH ROW EXECUTE FUNCTION public.validate_record_properties();


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
    ALTER TABLE public.records DISABLE TRIGGER before_record_insert_update;

    LOOP
        -- Insert a batch of missing plots
        WITH missing_plots AS (

            SELECT p.id, p.plot_name, p.cluster_name, p.cluster_id
            FROM inventory_archive.plot p
            JOIN inventory_archive.cluster c ON p.cluster_id = c.id
            WHERE ((c.grid_density in (64, 256) and p.federal_state in (1, 2, 4, 8, 9, 13)) -- SH, HH, BB, BW, BY, MV
                or (c.grid_density in (16, 32, 64, 256) and p.federal_state in (5, 6, 7, 10, 16)) -- NW, HE, RP, SL, TH
                or (c.grid_density in (4, 8, 16, 32, 64, 256) and p.federal_state in (11, 12, 14, 15)) -- BE, BB, SN, ST
                or p.sampling_stratum  in (308, 316)) AND p.interval_name = 'bwi2022'
            AND NOT EXISTS (
                SELECT 1 FROM public.records r 
                WHERE r.plot_id = p.id
            )
            LIMIT p_batch_size

        )
        INSERT INTO public.records (plot_id, schema_id, plot_name, cluster_name, cluster_id)
        SELECT id, p_schema_id, plot_name, cluster_name, cluster_id FROM missing_plots;

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
    ALTER TABLE public.records ENABLE TRIGGER before_record_insert_update;

    RAISE NOTICE 'Bulk insert completed: % records inserted', inserted_count;
    RETURN inserted_count;

EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Error in bulk insert: %', SQLERRM;
    RAISE;
END;
$$;


-- If organizations_lose.responsible_organization_id inserted or updates set records.administration_los, records.state_los, records.provider_los, records.troop_los based on organizations.type
-- Function to update records when organizations_lose responsible_organization_id changes
DROP TRIGGER IF EXISTS trg_update_records_from_organizations_lose_changes ON public.organizations_lose;
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
                    SET responsible_state =  NULL
                    WHERE administration_los = NEW.id;
                    
                WHEN 'country' THEN
                    UPDATE records
                    SET responsible_state = NULL
                    WHERE state_los = NEW.id;
                    
                WHEN 'provider' THEN
                    UPDATE records
                    SET responsible_provider = NULL
                    WHERE provider_los = NEW.id;
                    
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
                    SET responsible_state = NEW.responsible_organization_id, responsible_troop = NULL
                    WHERE administration_los = OLD.id;
                    
                WHEN 'country' THEN
                    UPDATE records
                    SET responsible_provider = NEW.responsible_organization_id, responsible_troop = NULL
                    WHERE state_los = OLD.id;
                    
                WHEN 'provider' THEN
                    UPDATE records
                    SET responsible_provider = NEW.responsible_organization_id, responsible_troop = NULL
                    WHERE provider_los = OLD.id;
                    
                ELSE
                    -- Handle unknown organization types or do nothing
                    NULL;
            END CASE;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to fire only on responsible_organization_id changes
-- UPDATE LOS information in Records

CREATE TRIGGER trg_update_records_from_organizations_lose_changes
AFTER UPDATE OF responsible_organization_id ON public.organizations_lose
FOR EACH ROW
EXECUTE FUNCTION public.update_records_from_organizations_lose_changes();


-- If update organizations_lose.responsible_organization_id changes or update responsible_state and/or responsible_provider of records where administration_los, state_los or provider_los is equal id

-- Function to update responsible_state and responsible_provider based on organizations_lose changes
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
            SET responsible_state = NEW.responsible_organization_id
            WHERE administration_los = NEW.id;
        END IF;
        
        -- For state_los matches  
        IF org_type = 'country' THEN
            UPDATE records
            SET responsible_state = NEW.responsible_organization_id
            WHERE state_los = NEW.id;
        END IF;
        
        -- For provider_los matches
        IF org_type = 'provider' THEN
            UPDATE records
            SET responsible_provider = NEW.responsible_organization_id
            WHERE provider_los = NEW.id;
        END IF;
        
        -- For troop_los matches (if troop type exists)
        IF org_type = 'troop' THEN
            UPDATE records
            SET responsible_troop = NEW.responsible_organization_id
            WHERE troop_los = NEW.id;
        END IF;
        
        -- If responsible_organization_id is set to NULL, clear the corresponding responsible fields
        IF NEW.responsible_organization_id IS NULL THEN
            CASE org_type
                WHEN 'root' THEN
                    UPDATE records
                    SET responsible_state = NULL
                    WHERE administration_los = NEW.id;
                    
                WHEN 'country' THEN
                    UPDATE records
                    SET responsible_state = NULL
                    WHERE state_los = NEW.id;
                    
                WHEN 'provider' THEN
                    UPDATE records
                    SET responsible_provider = NULL
                    WHERE provider_los = NEW.id;
                    
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
$$ LANGUAGE plpgsql;

-- Create trigger to fire on responsible_organization_id changes in organizations_lose
-- UPDATES Responsible
--DROP TRIGGER IF EXISTS trg_update_records_responsible_fields_from_organizations_lose ON public.organizations_lose;
--CREATE TRIGGER trg_update_records_responsible_fields_from_organizations_lose
--AFTER UPDATE OF responsible_organization_id ON public.organizations_lose
--FOR EACH ROW
--EXECUTE FUNCTION public.update_records_responsible_fields_from_organizations_lose();

-- Function to update responsible fields when los fields in records are updated
CREATE OR REPLACE FUNCTION public.update_records_responsible_fields_from_los_changes()
RETURNS TRIGGER AS $$
DECLARE
    org_type text;
    responsible_org_id uuid;
BEGIN
    -- Handle administration_los changes
    IF NEW.administration_los IS DISTINCT FROM OLD.administration_los THEN
        -- If administration_los changes, set state_los and provider_los to NULL
        NEW.state_los := NULL;
        NEW.provider_los := NULL;
        NEW.troop_los := NULL;
        
        IF NEW.administration_los IS NOT NULL THEN
            -- Get responsible_organization_id from organizations_lose
            SELECT ol.responsible_organization_id INTO responsible_org_id
            FROM organizations_lose ol
            WHERE ol.id = NEW.administration_los;
            
            -- Update responsible_state
            NEW.responsible_state := responsible_org_id;
        ELSE
            -- Clear responsible_state if administration_los is set to NULL
            NEW.responsible_state := NULL;
        END IF;
    END IF;
    
    -- Handle state_los changes
    IF NEW.state_los IS DISTINCT FROM OLD.state_los THEN
        -- If state_los changes, set provider_los to NULL
        NEW.provider_los := NULL;
        NEW.troop_los := NULL;
        
        IF NEW.state_los IS NOT NULL THEN
            -- Get responsible_organization_id from organizations_lose
            SELECT ol.responsible_organization_id INTO responsible_org_id
            FROM organizations_lose ol
            WHERE ol.id = NEW.state_los;
            
            -- Update responsible_state
            NEW.responsible_state := responsible_org_id;
        ELSE
            -- Clear responsible_state if state_los is set to NULL
            NEW.responsible_state := NULL;
        END IF;
    END IF;
    
    -- Handle provider_los changes
    IF NEW.provider_los IS DISTINCT FROM OLD.provider_los THEN
        IF NEW.provider_los IS NOT NULL THEN
            -- Get responsible_organization_id from organizations_lose
            SELECT ol.responsible_organization_id INTO responsible_org_id
            FROM organizations_lose ol
            WHERE ol.id = NEW.provider_los;
            
            -- Update responsible_provider
            NEW.responsible_provider := responsible_org_id;
        ELSE
            -- Clear responsible_provider if provider_los is set to NULL
            NEW.responsible_provider := NULL;
        END IF;
    END IF;
    
    -- Handle troop_los changes (if applicable)
    IF NEW.troop_los IS DISTINCT FROM OLD.troop_los THEN
        IF NEW.troop_los IS NOT NULL THEN
            -- Get responsible_organization_id from organizations_lose
            SELECT ol.responsible_organization_id INTO responsible_org_id
            FROM organizations_lose ol
            WHERE ol.id = NEW.troop_los;
            
            -- Update responsible_troop
            NEW.responsible_troop := responsible_org_id;
        ELSE
            -- Clear responsible_troop if troop_los is set to NULL
            NEW.responsible_troop := NULL;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to fire on los field changes in records
DROP TRIGGER IF EXISTS trg_update_records_responsible_fields_from_los_changes ON public.records;
CREATE TRIGGER trg_update_records_responsible_fields_from_los_changes
BEFORE UPDATE OF administration_los, state_los, provider_los, troop_los ON public.records
FOR EACH ROW
EXECUTE FUNCTION public.update_records_responsible_fields_from_los_changes();















-- Function to update responsible_state based on administration_los changes
CREATE OR REPLACE FUNCTION public.update_records_responsible_state_from_admin_los()
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
$$ LANGUAGE plpgsql;

-- Create trigger to fire on administration_los changes
DROP TRIGGER IF EXISTS trg_update_responsible_state_from_admin_los ON public.records;
CREATE TRIGGER trg_update_responsible_state_from_admin_los
AFTER UPDATE OF administration_los ON public.records
FOR EACH ROW
EXECUTE FUNCTION public.update_records_responsible_state_from_admin_los();



DROP VIEW IF EXISTS public.view_records_details;
CREATE OR REPLACE VIEW public.view_records_details AS
SELECT 
    r.*,
    p_bwi.federal_state,
    p_bwi.growth_district,
    p_bwi.forest_status AS forest_status_bwi2022,
    p_bwi.accessibility,
    p_bwi.forest_office,
    p_bwi.ffh_forest_type_field,
    p_bwi.property_type,
    p_ci2017.forest_status AS forest_status_ci2017,
    p_ci2012.forest_status AS forest_status_ci2012
FROM public.records r
LEFT JOIN inventory_archive.plot p_bwi 
    ON r.plot_id = p_bwi.id AND p_bwi.interval_name = 'bwi2022'
LEFT JOIN inventory_archive.plot p_ci2017 
    ON p_bwi.plot_name = p_ci2017.plot_name AND p_bwi.cluster_name = p_ci2017.cluster_name AND p_ci2017.interval_name = 'ci2017'
LEFT JOIN inventory_archive.plot p_ci2012 
    ON p_bwi.plot_name = p_ci2012.plot_name AND p_bwi.cluster_name = p_ci2012.cluster_name AND p_ci2012.interval_name = 'bwi2012';

-- Only authenticated users can access this view
REVOKE ALL ON public.view_records_details FROM PUBLIC;
GRANT SELECT ON public.view_records_details TO authenticated;
