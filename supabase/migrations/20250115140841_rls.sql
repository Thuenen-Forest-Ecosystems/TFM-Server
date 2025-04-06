CREATE OR REPLACE FUNCTION public.enable_rls_for_schema(
    schema_name TEXT, 
    usernames TEXT[] DEFAULT ARRAY['anon']
) RETURNS VOID AS $$
DECLARE
    table_record RECORD;
    policy_name TEXT;
    role_list TEXT;
BEGIN
    -- Convert the array of usernames to a comma-separated list for the SQL command
    SELECT string_agg(quote_ident(username), ', ') INTO role_list FROM unnest(usernames) AS username;
    
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
        
        -- Create a policy name based on the first role or a generic name
        policy_name := 'default_select_' || array_to_string(usernames, '_and_');
        
        -- Try to drop existing policy first to avoid conflicts
        BEGIN
            EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', 
                           policy_name, schema_name, table_record.table_name);
        EXCEPTION WHEN OTHERS THEN
            -- Ignore errors from non-existent policies
        END;
        
        -- Create a single policy that applies to all specified roles
        EXECUTE format('CREATE POLICY %I ON %I.%I FOR SELECT TO %s USING (true)', 
                      policy_name, schema_name, table_record.table_name, role_list);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

SELECT public.enable_rls_for_schema('inventory_archive', ARRAY['authenticated']);
SELECT public.enable_rls_for_schema('lookup', ARRAY['authenticated']);