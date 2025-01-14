--DECLARE
--    row record;
--BEGIN
--    FOR row IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' -- and other conditions, if needed
--    LOOP
--        EXECUTE format('ALTER TABLE public.%I SET SCHEMA [new_schema];', row.tablename);
--    END LOOP;
--END;

CREATE OR REPLACE FUNCTION public.enable_rls_for_schema(schema_name TEXT) RETURNS VOID AS $$
DECLARE
    table_record RECORD;
BEGIN
    -- Loop through all tables in the specified schema
    FOR table_record IN
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = schema_name
        AND table_type = 'BASE TABLE'
    LOOP
        -- Enable RLS for each table
        EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', schema_name, table_record.table_name);
        EXECUTE format('ALTER TABLE %I.%I FORCE ROW LEVEL SECURITY', schema_name, table_record.table_name);
        
        -- Optionally, add a default policy (e.g., allow all access for demonstration purposes)
        -- Replace this with your actual policy requirements
        EXECUTE format('CREATE POLICY default_policy ON %I.%I FOR SELECT to authenticated USING (true)', schema_name, table_record.table_name);
    END LOOP;
END;
$$ LANGUAGE plpgsql;
-- Example call to enable RLS for all tables in the schema 'private_ci2027_001'
SELECT public.enable_rls_for_schema('private_ci2027_001');


-- Create the trigger function to copy select_access_by from cluster to plot
CREATE OR REPLACE FUNCTION private_ci2027_001.copy_select_access_by_to_plot()
RETURNS TRIGGER AS $$
DECLARE
    plot_row RECORD;
BEGIN
   

    FOR plot_row IN
        SELECT id
        FROM private_ci2027_001.plot
        WHERE cluster_id = NEW.cluster_name::int4
    LOOP
        UPDATE private_ci2027_001.plot
        SET selectable_by = NEW.selectable_by
        WHERE id = plot_row.id;

        UPDATE private_ci2027_001.tree
        SET selectable_by = NEW.selectable_by
        WHERE plot_id =  plot_row.id;

        UPDATE private_ci2027_001.deadwood
        SET selectable_by = NEW.selectable_by
        WHERE plot_id =  plot_row.id;

    END LOOP;
    
    

    -- Update the tree table
    

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- Create the trigger to call the trigger function after an update on the cluster table
CREATE OR REPLACE TRIGGER update_select_access_by
AFTER UPDATE ON private_ci2027_001.cluster
FOR EACH ROW
WHEN (OLD.selectable_by IS DISTINCT FROM NEW.selectable_by)
EXECUTE FUNCTION private_ci2027_001.copy_select_access_by_to_plot();
