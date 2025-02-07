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
        EXECUTE format('CREATE POLICY default_select ON %I.%I FOR SELECT to anon USING (true)', schema_name, table_record.table_name);
    END LOOP;
END;
$$ LANGUAGE plpgsql;


SELECT public.enable_rls_for_schema('inventory_archive');
SELECT public.enable_rls_for_schema('lookup');
SELECT public.enable_rls_for_schema('lookup_external');


-- DROP SELECT ACCESS FOR ANON
DROP POLICY IF EXISTS default_select ON inventory_archive.position;