-- Create the function
CREATE OR REPLACE FUNCTION revoke_select_for_columns(
    schema_name TEXT,
    set_table_name TEXT,
    role_name TEXT,
    restricted_columns TEXT[]
) RETURNS VOID AS $$
DECLARE
    col TEXT;
    revoke_sql TEXT;
    grant_sql TEXT;
    column_list TEXT;
BEGIN
    -- Revoke SELECT on the restricted columns
    FOREACH col IN ARRAY restricted_columns LOOP
        revoke_sql := 'REVOKE SELECT (' || quote_ident(col) || ') ON TABLE ' || quote_ident(schema_name) || '.' || quote_ident(set_table_name) || ' FROM ' || quote_ident(role_name) || ';';
        EXECUTE revoke_sql;
    END LOOP;

    -- Build the list of columns to grant SELECT access
    column_list := '';
    FOR col IN
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = schema_name AND table_name = set_table_name
    LOOP
        IF col = ANY (restricted_columns) THEN
            CONTINUE;
        END IF;
        IF column_list <> '' THEN
            column_list := column_list || ', ';
        END IF;
        column_list := column_list || quote_ident(col);
    END LOOP;

    -- Grant SELECT on the allowed columns
    grant_sql := 'GRANT SELECT (' || column_list || ') ON TABLE ' || quote_ident(schema_name) || '.' || quote_ident(set_table_name) || ' TO ' || quote_ident(role_name) || ';';
    EXECUTE grant_sql;
END;
$$ LANGUAGE plpgsql;

-- Example usage
SELECT revoke_select_for_columns('private_ci2027_001', 'plot', 'anon', ARRAY['center_location']);