CREATE OR REPLACE FUNCTION set_column_privileges(
    schema_name TEXT,
    selected_table_name TEXT,
    role_name TEXT,
    restricted_columns TEXT[],
    privileges TEXT[]
) RETURNS VOID AS $$
DECLARE
    col TEXT;
    priv TEXT;
    revoke_sql TEXT;
    grant_sql TEXT;
    column_list TEXT;
BEGIN
    -- Revoke specified privileges on the restricted columns
    FOREACH col IN ARRAY restricted_columns LOOP
        FOREACH priv IN ARRAY privileges LOOP
            revoke_sql := 'REVOKE ' || priv || ' (' || quote_ident(col) || ') ON TABLE ' || quote_ident(schema_name) || '.' || quote_ident(selected_table_name) || ' FROM ' || quote_ident(role_name) || ';';
            EXECUTE revoke_sql;
        END LOOP;
    END LOOP;

    -- Build the list of columns to grant specified privileges
    column_list := '';
    FOR col IN
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = schema_name AND table_name = selected_table_name
    LOOP
        IF col = ANY (restricted_columns) THEN
            CONTINUE;
        END IF;
        IF column_list <> '' THEN
            column_list := column_list || ', ';
        END IF;
        column_list := column_list || quote_ident(col);
    END LOOP;

    -- Grant specified privileges on the allowed columns
    FOREACH priv IN ARRAY privileges LOOP
        grant_sql := 'GRANT ' || priv || ' (' || column_list || ') ON TABLE ' || quote_ident(schema_name) || '.' || quote_ident(selected_table_name) || ' TO ' || quote_ident(role_name) || ';';
        EXECUTE grant_sql;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Example usage
SELECT set_column_privileges('private_ci2027_001', 'plot', 'anon', ARRAY['center_location'], ARRAY['SELECT']);
SELECT set_column_privileges('private_ci2027_001', 'cluster', 'anon', ARRAY['selectable_by', 'updatable_by'], ARRAY['SELECT']);