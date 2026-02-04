CREATE TEMP TABLE null_only_columns (
    table_name TEXT,
    column_name TEXT
);

DO $$
DECLARE
    rec RECORD;
    has_non_null BOOLEAN;
BEGIN
    FOR rec IN 
        SELECT c.table_name, c.column_name
        FROM information_schema.columns c
        INNER JOIN information_schema.tables t 
            ON c.table_name = t.table_name 
            AND c.table_schema = t.table_schema
        WHERE c.table_schema = 'inventory_archive'
          AND t.table_type = 'BASE TABLE'
          AND c.table_name NOT LIKE '%TEMPLATE%'
    LOOP
        EXECUTE format(
            'SELECT EXISTS(SELECT 1 FROM inventory_archive.%I WHERE %I IS NOT NULL LIMIT 1)',
            rec.table_name, rec.column_name
        ) INTO has_non_null;
        
        IF NOT has_non_null THEN
            INSERT INTO null_only_columns VALUES (rec.table_name, rec.column_name);
        END IF;
    END LOOP;
END $$;

SELECT * FROM null_only_columns ORDER BY table_name, column_name;
--DROP TABLE null_only_columns;