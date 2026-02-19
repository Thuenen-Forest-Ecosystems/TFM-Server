-- Find all columns in a schema that contain only NULL values
-- Replace 'inventory_archive' with your schema name

DO $$
DECLARE
    schema_name TEXT := 'inventory_archive';
    table_rec RECORD;
    column_rec RECORD;
    row_count BIGINT;
    non_null_count BIGINT;
    sql_query TEXT;
    results_table TEXT := '';
BEGIN
    -- Create a temporary table to store results
    DROP TABLE IF EXISTS temp_null_only_columns;
    CREATE TEMP TABLE temp_null_only_columns (
        table_name TEXT,
        column_name TEXT,
        data_type TEXT,
        total_rows BIGINT
    );

    -- Loop through all tables in the schema
    FOR table_rec IN 
        SELECT t.table_name
        FROM information_schema.tables t
        WHERE t.table_schema = schema_name
        AND t.table_type = 'BASE TABLE'
        ORDER BY t.table_name
    LOOP
        -- Get row count for the table
        sql_query := format('SELECT COUNT(*) FROM %I.%I', schema_name, table_rec.table_name);
        EXECUTE sql_query INTO row_count;

        -- Skip empty tables
        IF row_count = 0 THEN
            CONTINUE;
        END IF;

        -- Loop through all columns in the table
        FOR column_rec IN
            SELECT c.column_name, c.data_type
            FROM information_schema.columns c
            WHERE c.table_schema = schema_name
            AND c.table_name = table_rec.table_name
            ORDER BY c.ordinal_position
        LOOP
            -- Count non-null values in the column
            sql_query := format(
                'SELECT COUNT(*) FROM %I.%I WHERE %I IS NOT NULL',
                schema_name,
                table_rec.table_name,
                column_rec.column_name
            );
            
            EXECUTE sql_query INTO non_null_count;

            -- If all values are NULL, add to results
            IF non_null_count = 0 THEN
                INSERT INTO temp_null_only_columns (table_name, column_name, data_type, total_rows)
                VALUES (table_rec.table_name, column_rec.column_name, column_rec.data_type, row_count);
                
                RAISE NOTICE 'Table: %.%, Column: %, Type: %, Rows: %', 
                    schema_name, table_rec.table_name, column_rec.column_name, column_rec.data_type, row_count;
            END IF;
        END LOOP;
    END LOOP;

    -- Display summary
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Summary: Found % columns with only NULL values', (SELECT COUNT(*) FROM temp_null_only_columns);
    RAISE NOTICE '========================================';
END $$;

-- Query the results
SELECT 
    table_name,
    column_name,
    data_type,
    total_rows,
    'ALTER TABLE inventory_archive.' || table_name || ' DROP COLUMN IF EXISTS ' || column_name || ';' as drop_statement
FROM temp_null_only_columns
ORDER BY table_name, column_name;
