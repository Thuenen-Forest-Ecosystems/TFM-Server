-- ============================================================================
-- VIEW: plot_nested_json
-- ============================================================================
-- Creates a nested JSON view of plots with all related data (trees, deadwood, etc.)
-- Optimized using CTEs and subqueries for better performance
-- ============================================================================
-- Drop in dependency order to avoid locks: Triggers → Functions → Mat.View → View
DROP TRIGGER IF EXISTS before_record_insert_or_update ON public.records CASCADE;
DROP TRIGGER IF EXISTS on_record_updated ON public.records CASCADE;
DROP TRIGGER IF EXISTS trigger_validation_version_change ON public.records CASCADE;
DROP TRIGGER IF EXISTS trigger_populate_troop_members ON public.records CASCADE;
DROP FUNCTION IF EXISTS public.fill_previous_properties() CASCADE;
DROP FUNCTION IF EXISTS public.get_plot_nested_json_by_id(UUID, INTEGER, INTEGER) CASCADE;
DROP FUNCTION IF EXISTS public.refresh_plot_nested_json_cached() CASCADE;
DROP FUNCTION IF EXISTS public.fill_cluster_data(INTEGER) CASCADE;
DROP FUNCTION IF EXISTS public.update_records_cluster(INTEGER) CASCADE;
DROP FUNCTION IF EXISTS public.handle_record_changes() CASCADE;
DROP FUNCTION IF EXISTS public.validate_json_properties_by_schema(UUID, JSONB) CASCADE;
DROP FUNCTION IF EXISTS public.validate_record_properties() CASCADE;
DROP FUNCTION IF EXISTS public.add_plot_ids_to_records(UUID, INTEGER) CASCADE;
DROP FUNCTION IF EXISTS public.batch_update_records(INTEGER) CASCADE;
DROP FUNCTION IF EXISTS public.get_user_clusters() CASCADE;
DROP FUNCTION IF EXISTS public.handle_validation_version_change() CASCADE;
DROP FUNCTION IF EXISTS public.set_preliminary() CASCADE;
DROP FUNCTION IF EXISTS public.set_previous_properties(INTEGER) CASCADE;
DROP FUNCTION IF EXISTS public.set_previous_properties(INTEGER, INTEGER) CASCADE;
DROP FUNCTION IF EXISTS public.populate_current_troop_members() CASCADE;
DROP MATERIALIZED VIEW IF EXISTS public.plot_nested_json_cached CASCADE;
DROP VIEW IF EXISTS public.plot_nested_json CASCADE;
CREATE OR REPLACE VIEW public.plot_nested_json AS WITH base_plots AS (
        -- Use bwi2022 rows as the primary base; fall back to ci2027 for clusters
        -- that have no bwi2022 plot (e.g. new training clusters, ci2027-only plots).
        SELECT DISTINCT ON (cluster_name, plot_name) *
        FROM inventory_archive.plot
        WHERE interval_name IN ('bwi2022', 'ci2027')
        ORDER BY cluster_name,
            plot_name,
            CASE
                interval_name
                WHEN 'bwi2022' THEN 1
                ELSE 2
            END
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
                    SELECT json_agg(psp)
                    FROM inventory_archive.plot_support_points psp
                    WHERE psp.plot_id = p.id
                ),
                '[]'::json
            ) AS plot_support_points,
            COALESCE(
                (
                    SELECT json_agg(srp)
                    FROM inventory_archive.subplots_relative_position srp
                    WHERE srp.plot_id = p.id
                ),
                '[]'::json
            ) AS subplots_relative_position,
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
-- NOTE: The following functions have been moved to dedicated files:
--
-- 20250312143821_update_previoud_properties.sql:
--   fill_cluster_data, get_plot_nested_json_by_id, fill_previous_properties,
--   refresh_plot_nested_json_cached, reset_previous_properties,
--   set_previous_properties, update_records_cluster, batch_update_records
--
-- 20250312143822_update_properties.sql:
--   validate_json_properties_by_schema, validate_record_properties,
--   call_validation_function, handle_validation_version_change, set_preliminary
-- ============================================================================
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
    FROM (
            SELECT DISTINCT c.id
            FROM inventory_archive.plot p
                JOIN inventory_archive.cluster c ON p.cluster_id = c.id
            WHERE (
                    (
                        c.grid_density IN (64, 256)
                        AND p.federal_state IN (1, 2, 4, 8, 9, 13)
                    )
                    OR (
                        c.grid_density IN (16, 32, 64, 256)
                        AND p.federal_state IN (5, 6, 7, 10, 16)
                    )
                    OR (
                        c.grid_density IN (4, 8, 16, 32, 64, 256)
                        AND p.federal_state IN (11, 12, 14, 15)
                    )
                    OR p.sampling_stratum IN (308, 316)
                    OR c.is_training = TRUE
                )
                AND p.interval_name IN ('bwi2022', 'ci2027')
        ) cl
        JOIN inventory_archive.plot p ON cl.id = p.cluster_id
    WHERE p.interval_name IN ('bwi2022', 'ci2027') -- inkl. Testtrakte unter ci2027
        AND NOT EXISTS (
            -- Skip plots already in records — fixes offset-by-conflicts bug
            SELECT 1
            FROM public.records r
            WHERE r.cluster_name = p.cluster_name
                AND r.plot_name = p.plot_name
        )
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
FROM eligible_plots;
-- NOT EXISTS above ensures no duplicates; ON CONFLICT not needed
GET DIAGNOSTICS batch_count = ROW_COUNT;
IF batch_count = 0 THEN EXIT;
END IF;
total_processed := total_processed + batch_count;
RAISE NOTICE 'Processed % records in this batch (total: %)...',
batch_count,
total_processed;
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