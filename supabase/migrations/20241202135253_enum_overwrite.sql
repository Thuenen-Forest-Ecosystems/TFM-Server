SET search_path TO private_ci2027_001;
--DROP TYPE IF EXISTS enum_state;
--CREATE TYPE enum_state AS ENUM ('BW', 'BY', 'BE', 'BB', 'HB', 'HH', 'HE', 'MV', 'NI', 'NW', 'RP', 'SL', 'SN', 'ST', 'SH', 'TH'); -- x3_bl

--DROP TYPE IF EXISTS enum_sampling_strata;
--CREATE TYPE enum_sampling_strata AS ENUM ('0', '1', '4', '8', '16', '64', '128', '256', '512'); -- x3_net

DROP TYPE IF EXISTS enum_forest_status;
CREATE TYPE enum_forest_status AS ENUM('0', '1', '2', '3', '4', '5', '8', '9', '23', '24', '25');
-- x3_wa

DROP TYPE IF EXISTS enum_use_restriction_reason;
CREATE TYPE enum_use_restriction_reason AS ENUM ('nenschutz', 'neswald', 'neewald', 'nesabursach', 'nestreu', 'neunerschlies', 'negeleig', 'negerertrag', 'neeigenbin', 'nesibursach');
-- NEU

DROP TYPE IF EXISTS enum_harvesting_method;
CREATE TYPE enum_harvesting_method AS ENUM('0', '1', '2', '3', '4');
-- x3_ernte

DROP TYPE IF EXISTS enum_plot_location_parent_table;
CREATE TYPE enum_plot_location_parent_table AS ENUM('wzp_tree', 'deadwood', 'edges', 'position', 'sapling_1m', 'sapling_2m');
-- x3_plot

DROP TYPE IF EXISTS enum_interval_name;
CREATE TYPE enum_interval_name AS ENUM('bwi1987', 'bwi1992', 'bwi2002', 'ci2008', 'bwi2012', 'ci2017', 'ci2022', 'ci2027');
DROP TYPE IF EXISTS enum_regrole;
CREATE TYPE enum_regtype AS ENUM('int4', 'int8', 'float4', 'float8', 'text', 'varchar', 'date', 'timestamp', 'bool', 'regtype');
