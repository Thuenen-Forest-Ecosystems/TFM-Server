CREATE SCHEMA lookup_external;
ALTER SCHEMA lookup_external OWNER TO postgres;
COMMENT ON SCHEMA lookup_external IS 'Externe Daten';
GRANT USAGE ON SCHEMA lookup_external TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA lookup_external TO anon, authenticated, service_role;
GRANT ALL ON ALL ROUTINES IN SCHEMA lookup_external TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA lookup_external TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA lookup_external GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA lookup_external GRANT ALL ON ROUTINES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA lookup_external GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;

-- SCHEMA DEFINITION
SET search_path TO lookup_external;


CREATE TABLE lookup_ffh (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE lookup_national_park (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE lookup_natur_park (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE lookup_vogelschutzgebiete (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE lookup_biogeographische_region (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE lookup_biosphaere (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE lookup_natur_schutzgebiet (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE lookup_forestry_office (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE lookup_gemeinde (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);