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
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- On INSERT:
        IF NEW.plot_id IS NOT NULL THEN
            SELECT row_to_json(pnj)::jsonb INTO NEW.previous_properties
            FROM public.plot_nested_json pnj
            WHERE pnj.id = NEW.plot_id;
        ELSE
            NEW.previous_properties := '{}'::jsonb;
        END IF;
    ELSIF TG_OP = 'UPDATE' THEN
        -- On UPDATE:
        IF NEW.previous_properties_updated_at IS NOT NULL AND OLD.previous_properties_updated_at IS NOT NULL AND NEW.previous_properties_updated_at >= OLD.previous_properties_updated_at THEN
            -- If plot_id is the same, get the previous properties from the old record
            SELECT row_to_json(pnj)::jsonb INTO NEW.previous_properties
            FROM public.plot_nested_json pnj
            WHERE pnj.id = NEW.plot_id;
            
        ELSIF NEW.plot_id IS NOT NULL THEN
            -- If plot_id has changed, get the properties from the new plot
            NEW.previous_properties := OLD.properties;
        ELSE
            -- If plot_id is null, set previous_properties to empty JSON
            NEW.previous_properties := '{}'::jsonb;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- Create or replace the trigger
DROP TRIGGER IF EXISTS before_record_insert_or_update ON public.records;
CREATE TRIGGER before_record_insert_or_update
BEFORE INSERT OR UPDATE ON public.records
FOR EACH ROW
EXECUTE FUNCTION fill_previous_properties();