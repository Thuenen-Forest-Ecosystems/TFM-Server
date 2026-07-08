-- Grant permissions on lookup schema
GRANT USAGE ON SCHEMA lookup TO anon,
    authenticated,
    service_role;
-- Grant SELECT on all tables to everyone (read-only for anon and authenticated users)
GRANT SELECT ON ALL TABLES IN SCHEMA lookup TO anon,
    authenticated,
    service_role;
-- Grant full permissions to service_role and authenticated for data migration
GRANT INSERT,
    UPDATE,
    DELETE,
    TRUNCATE ON ALL TABLES IN SCHEMA lookup TO authenticated,
    service_role;
-- Grant USAGE on all sequences (needed for serial/auto-increment columns)
GRANT USAGE ON ALL SEQUENCES IN SCHEMA lookup TO authenticated,
    service_role;
-- Ensure future tables also get the same permissions
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA lookup
GRANT SELECT ON TABLES TO anon,
    authenticated,
    service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA lookup
GRANT INSERT,
    UPDATE,
    DELETE,
    TRUNCATE ON TABLES TO authenticated,
    service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA lookup
GRANT USAGE ON SEQUENCES TO authenticated,
    service_role;