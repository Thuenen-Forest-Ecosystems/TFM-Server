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

GRANT CONNECT ON DATABASE postgres TO ti_read;

GRANT USAGE ON SCHEMA inventory_archive TO ti_read;
GRANT SELECT ON ALL TABLES IN SCHEMA inventory_archive TO ti_read;

GRANT USAGE ON SCHEMA lookup TO ti_read;
GRANT SELECT ON ALL TABLES IN SCHEMA lookup TO ti_read;

-- Grant access to the public schema
GRANT USAGE ON SCHEMA public TO ti_read;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO ti_read;

-- Ensure future tables in public are accessible
ALTER DEFAULT PRIVILEGES FOR ROLE postgres
GRANT SELECT ON TABLES TO ti_read;