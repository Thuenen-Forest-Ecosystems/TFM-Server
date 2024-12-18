SET default_transaction_read_only = OFF;

-- SCHEMA DEFINITION
CREATE SCHEMA private_ci2027_001;
ALTER SCHEMA private_ci2027_001 OWNER TO postgres;
COMMENT ON SCHEMA private_ci2027_001 IS 'Kohlenstoffinventur 2027';

GRANT USAGE ON SCHEMA private_ci2027_001 TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA private_ci2027_001 TO anon, authenticated, service_role;
GRANT ALL ON ALL ROUTINES IN SCHEMA private_ci2027_001 TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA private_ci2027_001 TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA private_ci2027_001 GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA private_ci2027_001 GRANT ALL ON ROUTINES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA private_ci2027_001 GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;