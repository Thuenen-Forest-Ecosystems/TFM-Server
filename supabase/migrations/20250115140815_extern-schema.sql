CREATE SCHEMA external_data;
ALTER SCHEMA external_data OWNER TO postgres;
COMMENT ON SCHEMA external_data IS 'Externe Daten';
GRANT USAGE ON SCHEMA external_data TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA external_data TO anon, authenticated, service_role;
GRANT ALL ON ALL ROUTINES IN SCHEMA external_data TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA external_data TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA external_data GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA external_data GRANT ALL ON ROUTINES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA external_data GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;

-- SCHEMA DEFINITION
SET search_path TO external_data;


CREATE TABLE lookup_ffh AS TABLE private_ci2027_001.lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_ffh ADD COLUMN id uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL;
--ALTER TABLE lookup_ffh ADD COLUMN abbreviation enum_browsing UNIQUE NOT NULL;

CREATE TABLE lookup_national_park AS TABLE private_ci2027_001.lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_national_park ADD COLUMN id uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL;

CREATE TABLE lookup_natur_park AS TABLE private_ci2027_001.lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_natur_park ADD COLUMN id uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL;

CREATE TABLE lookup_vogelschutzgebiete AS TABLE private_ci2027_001.lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_vogelschutzgebiete ADD COLUMN id uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL;

CREATE TABLE lookup_biogeographische_region AS TABLE private_ci2027_001.lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_biogeographische_region ADD COLUMN id uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL;

CREATE TABLE lookup_biosphaere AS TABLE private_ci2027_001.lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_biosphaere ADD COLUMN id uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL;

CREATE TABLE lookup_natur_schutzgebiet AS TABLE private_ci2027_001.lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_natur_schutzgebiet ADD COLUMN id uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL;