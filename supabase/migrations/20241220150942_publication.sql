-- Create publication for powersync
DROP PUBLICATION IF EXISTS powersync;
CREATE PUBLICATION powersync FOR TABLES IN SCHEMA private_ci2027_001;
