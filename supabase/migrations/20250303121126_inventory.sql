-- SCHEMA inventory
CREATE SCHEMA inventory;
ALTER SCHEMA inventory OWNER TO postgres;
COMMENT ON SCHEMA inventory IS 'aktuelle Invenur';
GRANT USAGE ON SCHEMA inventory TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA inventory TO anon, authenticated, service_role;
GRANT ALL ON ALL ROUTINES IN SCHEMA inventory TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA inventory TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA inventory GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA inventory GRANT ALL ON ROUTINES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA inventory GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;

SET search_path TO inventory;

