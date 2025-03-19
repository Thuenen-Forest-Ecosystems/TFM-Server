CREATE OR REPLACE FUNCTION public.enable_rls_for_schema(schema_name TEXT, username TEXT DEFAULT 'anon') RETURNS VOID AS $$
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
        EXECUTE format('CREATE POLICY default_select_%I ON %I.%I FOR SELECT TO %I USING (true)', username, schema_name, table_record.table_name, username);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

SELECT public.enable_rls_for_schema('inventory_archive', 'anon');
SELECT public.enable_rls_for_schema('lookup', 'anon');

SELECT public.enable_rls_for_schema('inventory_archive', 'ti_read');
SELECT public.enable_rls_for_schema('lookup', 'ti_read'); 



-- DROP SELECT ACCESS FOR ANON
DROP POLICY IF EXISTS default_select_anon ON inventory_archive.edges;
DROP POLICY IF EXISTS default_select_anon ON inventory_archive.position;
DROP POLICY IF EXISTS default_select_anon ON inventory_archive.plot_coordinates;
DROP POLICY IF EXISTS default_select_anon ON inventory_archive.plot_landmark;
DROP POLICY IF EXISTS default_select_anon ON inventory_archive.subplots_relative_position;
DROP POLICY IF EXISTS default_select_anon ON inventory_archive.tree_coordinates;