DROP VIEW IF EXISTS public.plot_nested_json;
CREATE VIEW public.plot_nested_json AS
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
)
SELECT
    p.*,
    COALESCE(pc.data, '[]'::json) AS plot_coordinates,
    COALESCE(tt.data, '[]'::json) AS trees,
    COALESCE(dw.data, '[]'::json) AS deadwoods,
    COALESCE(rg.data, '[]'::json) AS regenerations,
    COALESCE(sl.data, '[]'::json) AS structures_lt4m,
    COALESCE(ee.data, '[]'::json) AS edges
FROM inventory_archive.plot p
LEFT JOIN p_coords pc ON p.id = pc.plot_id
LEFT JOIN t_trees tt ON p.id = tt.plot_id
LEFT JOIN d_woods dw ON p.id = dw.plot_id
LEFT JOIN r_gens rg ON p.id = rg.plot_id
LEFT JOIN s_lt4m sl ON p.id = sl.plot_id
LEFT JOIN e_edges ee ON p.id = ee.plot_id;

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
DROP TRIGGER IF EXISTS on_record_updated ON records;
create trigger on_record_updated
  after update on records
  for each row execute procedure handle_record_changes();





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
CREATE OR REPLACE FUNCTION validate_record_properties()
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

-- Example: SELECT public.add_plot_ids_to_records('10cf8993-0190-4a9c-b135-111d8009f7b4'); // ci2027
-- Function to get all id from inventory_archive.plot and add one row to public.records (if exists do nothing)
DROP FUNCTION IF EXISTS public.add_plot_ids_to_records;
CREATE OR REPLACE FUNCTION public.add_plot_ids_to_records(p_schema_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, inventory_archive
AS $$
DECLARE
    inserted_count INTEGER;

BEGIN
    RAISE NOTICE 'Starting bulk insert of missing plot records...';

    -- Disable specific user-defined triggers to speed up the insert and avoid permission errors.
    RAISE NOTICE 'Disabling user triggers...';
    ALTER TABLE public.records DISABLE TRIGGER before_record_insert_or_update;
    ALTER TABLE public.records DISABLE TRIGGER on_record_updated;
    ALTER TABLE public.records DISABLE TRIGGER before_record_insert_update;
    

    -- schema_id
    
    -- Single bulk insert operation - much faster than loops
    WITH missing_plots AS (
        SELECT p.id, p.plot_name, p.cluster_name, p.cluster_id
        FROM inventory_archive.plot p
        WHERE p.id IS NOT NULL 
        AND p.interval_name = 'bwi2022'
        -- AND p.forest_status = 3, 4 or 5
        AND p.forest_status IN (3, 4, 5)
        AND NOT EXISTS (
            SELECT 1 FROM public.records r 
            WHERE r.plot_id = p.id
        )
    )
    INSERT INTO public.records (plot_id, schema_id, plot_name, cluster_name, cluster_id)
    SELECT id, p_schema_id, p.plot_name, p.cluster_name, p.cluster_id FROM missing_plots p;

    GET DIAGNOSTICS inserted_count = ROW_COUNT;

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


-- Update responsibility based on organizations_lose
-- function+trigger: if public.organizations_lose.record_ids array change add public.organizations_lose.organization_id to all records.responsible_provider where record.id in public.organizations_lose.record_ids and set null where records.responsible_provider=public.organizations_lose.organization_id and not in public.organizations_lose.record_ids
CREATE OR REPLACE FUNCTION public.update_records_responsible_provider()
RETURNS TRIGGER AS $$
DECLARE
    removed_ids uuid[];
    new_organization_type text;
    old_organization_type text;
BEGIN
    -- Handle when responsible_organization_id changes
    IF OLD.responsible_organization_id IS DISTINCT FROM NEW.responsible_organization_id THEN
        -- Get the type of the NEW responsible organization
        SELECT type INTO new_organization_type
        FROM organizations
        WHERE id = NEW.responsible_organization_id;

        -- Update all records in this lose with the new responsible organization
        IF array_length(NEW.cluster_ids, 1) > 0 THEN
            IF new_organization_type = 'country' THEN
                UPDATE records
                SET responsible_state = NEW.responsible_organization_id
                WHERE cluster_id = ANY(NEW.cluster_ids);
            ELSIF new_organization_type = 'provider' THEN
                UPDATE records
                SET responsible_provider = NEW.responsible_organization_id
                WHERE cluster_id = ANY(NEW.cluster_ids);
            END IF;
        END IF;

        -- Clear the old responsible organization from records (if it existed)
        IF OLD.responsible_organization_id IS NOT NULL AND array_length(NEW.cluster_ids, 1) > 0 THEN
            SELECT type INTO old_organization_type
            FROM organizations
            WHERE id = OLD.responsible_organization_id;

            IF old_organization_type = 'country' THEN
                UPDATE records
                SET responsible_state = NULL
                WHERE cluster_id = ANY(NEW.cluster_ids)
                  AND responsible_state = OLD.responsible_organization_id;
            ELSIF old_organization_type = 'provider' THEN
                UPDATE records
                SET responsible_provider = NULL
                WHERE cluster_id = ANY(NEW.cluster_ids)
                  AND responsible_provider = OLD.responsible_organization_id;
            END IF;
        END IF;
    END IF;

    -- Handle when cluster_ids array changes (existing logic)
    IF OLD.cluster_ids IS DISTINCT FROM NEW.cluster_ids THEN
        -- 1. Handle clusters being ADDED to the 'cluster_ids' array.
        IF array_length(NEW.cluster_ids, 1) > 0 AND NEW.responsible_organization_id IS NOT NULL THEN
            -- Get the type of the organization for the NEW cluster.
            SELECT type INTO new_organization_type
            FROM organizations
            WHERE id = NEW.responsible_organization_id;

            -- Update the appropriate 'responsible' column based on the organization's type.
            IF new_organization_type = 'country' THEN
                UPDATE records
                SET responsible_state = NEW.responsible_organization_id
                WHERE cluster_id = ANY(NEW.cluster_ids);
            ELSIF new_organization_type = 'provider' THEN
                UPDATE records
                SET responsible_provider = NEW.responsible_organization_id
                WHERE cluster_id = ANY(NEW.cluster_ids);
            END IF;
        END IF;

        -- 2. Handle clusters being REMOVED from the 'cluster_ids' array.
        SELECT array_agg(id) INTO removed_ids
        FROM unnest(OLD.cluster_ids) as id
        WHERE id <> ALL(NEW.cluster_ids);

        IF array_length(removed_ids, 1) > 0 AND OLD.responsible_organization_id IS NOT NULL THEN
            -- Get the type of the organization for the OLD cluster to know which column to nullify.
            SELECT type INTO old_organization_type
            FROM organizations
            WHERE id = OLD.responsible_organization_id;

            -- Nullify the appropriate 'responsible' column for the removed clusters.
            IF old_organization_type = 'country' THEN
                UPDATE records
                SET responsible_state = NULL
                WHERE cluster_id = ANY(removed_ids)
                  AND responsible_state = OLD.responsible_organization_id;
            ELSIF old_organization_type = 'provider' THEN
                UPDATE records
                SET responsible_provider = NULL
                WHERE cluster_id = ANY(removed_ids)
                  AND responsible_provider = OLD.responsible_organization_id;
            END IF;
        END IF;
    END IF;

    -- SET records.responsible_troop to organizations_lose.troop_id (for all records)
    IF NEW.troop_id IS NOT NULL AND array_length(NEW.cluster_ids, 1) > 0 THEN
        UPDATE records
        SET responsible_troop = NEW.troop_id
        WHERE cluster_id = ANY(NEW.cluster_ids);
    END IF;

    -- Clear responsible_troop if troop_id was removed
    IF OLD.troop_id IS NOT NULL AND NEW.troop_id IS NULL AND array_length(NEW.cluster_ids, 1) > 0 THEN
        UPDATE records
        SET responsible_troop = NULL
        WHERE cluster_id = ANY(NEW.cluster_ids)
          AND responsible_troop = OLD.troop_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Update the trigger to fire on changes to both columns
DROP TRIGGER IF EXISTS trg_update_records_responsible_provider ON public.organizations_lose;
CREATE TRIGGER trg_update_records_responsible_provider
AFTER UPDATE OF cluster_ids, responsible_organization_id, troop_id ON public.organizations_lose
FOR EACH ROW
EXECUTE FUNCTION public.update_records_responsible_provider();