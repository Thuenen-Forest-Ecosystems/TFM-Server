-- Create publication for powersync
DROP PUBLICATION IF EXISTS powersync;
CREATE PUBLICATION powersync;

-- Dynamically add all tables from the private_ci2027_001 schema to the publication
DO $$
DECLARE
    table_name_to_be_added TEXT;
BEGIN
    -- Loop through all tables in the specified schema
    FOR table_name_to_be_added IN
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = 'private_ci2027_001'
    LOOP
        -- Dynamically generate and execute the ALTER PUBLICATION statement
        EXECUTE format('ALTER PUBLICATION powersync ADD TABLE private_ci2027_001.%I', table_name_to_be_added);
    END LOOP;
END $$;

ALTER PUBLICATION powersync ADD TABLE public.users_profile, public.users_access, public.comanies, public.schemas;