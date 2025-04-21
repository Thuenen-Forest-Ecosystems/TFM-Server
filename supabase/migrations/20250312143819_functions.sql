DROP VIEW IF EXISTS public.plot_nested_json;

CREATE VIEW public.plot_nested_json AS
SELECT
    plot.*,
    
    -- Use COALESCE to return an empty array ('[]'::json) if no rows are found
    COALESCE(
        (
            SELECT json_agg(row_to_json(plot_coordinates.*))
            FROM inventory_archive.plot_coordinates
            WHERE tree.plot_id = plot.id
        ),
        '[]'::json
    ) AS plot_coordinates,

    COALESCE(
        (
            SELECT json_agg(row_to_json(tree.*))
            FROM inventory_archive.tree
            WHERE tree.plot_id = plot.id
        ),
        '[]'::json
    ) AS trees,
    
    COALESCE(
        (
            SELECT json_agg(row_to_json(deadwood.*))
            FROM inventory_archive.deadwood
            WHERE deadwood.plot_id = plot.id
        ),
        '[]'::json
    ) AS deadwoods,
    
    COALESCE(
        (
            SELECT json_agg(row_to_json(regeneration.*))
            FROM inventory_archive.regeneration
            WHERE regeneration.plot_id = plot.id
        ),
        '[]'::json
    ) AS regenerations,
    
    COALESCE(
        (
            SELECT json_agg(row_to_json(structure_lt4m.*))
            FROM inventory_archive.structure_lt4m
            WHERE structure_lt4m.plot_id = plot.id
        ),
        '[]'::json
    ) AS structures_lt4m,
    
    COALESCE(
        (
            SELECT json_agg(row_to_json(edges.*))
            FROM inventory_archive.edges
            WHERE edges.plot_id = plot.id
        ),
        '[]'::json
    ) AS edges
        
FROM inventory_archive.plot;


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
    json_result jsonb;
BEGIN
    RAISE NOTICE 'Trigger firing for % on record with plot_id: %', TG_OP, NEW.plot_id;

    -- Always ensure previous_properties has a default value
    NEW.previous_properties := '{}'::jsonb;
    
    -- Attempt to get the plot data
    IF NEW.plot_id IS NOT NULL THEN
        BEGIN
            SELECT row_to_json(pnj)::jsonb INTO json_result
            FROM public.plot_nested_json pnj
            WHERE pnj.id = NEW.plot_id;
            
            IF json_result IS NOT NULL THEN
                NEW.previous_properties := json_result;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Error fetching plot data: %', SQLERRM;
            -- previous_properties already has default value
        END;
    END IF;
    
    -- Set state_responsible if needed (won't override existing value)
    IF NEW.state_responsible IS NULL THEN
        SELECT state_responsible INTO NEW.state_responsible
        FROM inventory_archive.cluster c
        JOIN inventory_archive.plot p ON p.cluster_id = c.id
        WHERE p.id = NEW.plot_id;
    END IF;

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Error in trigger: % %', SQLSTATE, SQLERRM;
    RETURN NEW; -- Still allow the operation to proceed
END;
$$;

-- Create or replace the trigger
DROP TRIGGER IF EXISTS before_record_insert_or_update ON public.records;
CREATE TRIGGER before_record_insert_or_update
BEFORE INSERT OR UPDATE ON public.records
FOR EACH ROW
EXECUTE FUNCTION fill_previous_properties();


-- Function to insert all plots with clusters having the same state_responsible into public.records
CREATE OR REPLACE FUNCTION public.insert_plots_by_cluster_state_responsible(p_state_responsible INTEGER)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO public.records (plot_id, state_responsible, created_at)
    SELECT p.id, c.state_responsible, NOW()
    FROM inventory_archive.plot p
    INNER JOIN inventory_archive.cluster c
    ON p.cluster_id = c.id
    WHERE c.state_responsible = p_state_responsible
    AND c.state_responsible IS NOT NULL;
END;
$$;

SELECT public.insert_plots_by_cluster_state_responsible(1);