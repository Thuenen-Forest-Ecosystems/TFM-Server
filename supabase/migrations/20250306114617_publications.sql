-- Create publication for powersync
DROP PUBLICATION IF EXISTS powersync;
CREATE PUBLICATION powersync;
CREATE OR REPLACE FUNCTION add_all_tables_to_publication(publication_name TEXT, schema_name TEXT) RETURNS void AS $$
DECLARE table_name_to_be_added TEXT;
BEGIN -- Loop through all tables in the specified schema
FOR table_name_to_be_added IN
SELECT table_name
FROM information_schema.tables
WHERE table_schema = schema_name LOOP -- Dynamically generate and execute the ALTER PUBLICATION statement
    EXECUTE format(
        'ALTER PUBLICATION %I ADD TABLE %I.%I',
        publication_name,
        schema_name,
        table_name_to_be_added
    );
END LOOP;
END $$ LANGUAGE plpgsql;
-- SELECT add_all_tables_to_publication('powersync', 'inventory');
SELECT add_all_tables_to_publication('powersync', 'inventory_archive');
SELECT add_all_tables_to_publication('powersync', 'lookup');
ALTER PUBLICATION powersync
ADD TABLE public.organizations;
ALTER PUBLICATION powersync
ADD TABLE public.troop;
ALTER PUBLICATION powersync
ADD TABLE public.schemas;
ALTER PUBLICATION powersync
ADD TABLE public.users_profile;
ALTER PUBLICATION powersync
ADD TABLE public.records;
ALTER PUBLICATION powersync
ADD TABLE public.troop_members;