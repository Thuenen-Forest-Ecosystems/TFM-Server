-- Ensure the role exists
DO $$ BEGIN
    -- Create the role again
    CREATE ROLE ti_read WITH LOGIN PASSWORD 'qjze5aruuR9vJz';
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

-- Ensure future tables in public are not accessible
ALTER DEFAULT PRIVILEGES FOR ROLE postgres
REVOKE SELECT ON TABLES FROM ti_read;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

GRANT CONNECT ON DATABASE postgres TO ti_read;

GRANT USAGE ON SCHEMA inventory_archive TO ti_read;
GRANT SELECT ON ALL TABLES IN SCHEMA inventory_archive TO ti_read;

GRANT USAGE ON SCHEMA lookup TO ti_read;
GRANT SELECT ON ALL TABLES IN SCHEMA lookup TO ti_read;

