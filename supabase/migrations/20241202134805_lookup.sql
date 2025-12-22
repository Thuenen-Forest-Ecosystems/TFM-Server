SET default_transaction_read_only = OFF;
-- SCHEMA lookup
CREATE SCHEMA lookup;
ALTER SCHEMA lookup OWNER TO postgres;
COMMENT ON SCHEMA lookup IS 'Lookup Tabellen';
GRANT USAGE ON SCHEMA lookup TO anon,
    authenticated,
    service_role;
GRANT ALL ON ALL TABLES IN SCHEMA lookup TO anon,
    authenticated,
    service_role;
GRANT ALL ON ALL ROUTINES IN SCHEMA lookup TO anon,
    authenticated,
    service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA lookup TO anon,
    authenticated,
    service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA lookup
GRANT ALL ON TABLES TO anon,
    authenticated,
    service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA lookup
GRANT ALL ON ROUTINES TO anon,
    authenticated,
    service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA lookup
GRANT ALL ON SEQUENCES TO anon,
    authenticated,
    service_role;
SET search_path TO lookup;
CREATE TABLE IF NOT EXISTS lookup_TEMPLATE (
    --abbreviation text UNIQUE NOT NULL,
    code serial UNIQUE NOT NULL,
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL,
    name_de text NOT NULL,
    name_en text NULL,
    interval text [] NULL,
    sort INTEGER NULL
);
CREATE TABLE IF NOT EXISTS lookup_browsing (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_cluster_situation (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_cluster_status (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_dead_wood_type (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_decomposition (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_edge_status (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_elevation_level (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_exploration_instruction (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_ffh_forest_type (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_forest_community (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_forest_office (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_forest_status (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_gnss_quality (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_grid_density (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_growth_region (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_growth_district (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
-- Add growth_region reference to lookup_growth_district
ALTER TABLE lookup.lookup_growth_district
ADD COLUMN growth_region smallint NULL REFERENCES lookup.lookup_growth_region (code);
CREATE TABLE IF NOT EXISTS lookup_harvest_condition (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
-- formerly lookup_harvesting_method
CREATE TABLE IF NOT EXISTS lookup_harvest_method (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_harvest_reason (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_land_use (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_management_type (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_marker_profile (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_marker_status (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_property_size_class (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_property_type (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_pruning (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_sampling_stratum (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_stand_development_phase (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_stand_layer (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_stand_structure (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_state (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
ALTER TABLE lookup_state
ADD COLUMN abbreviation text NULL;
CREATE TABLE IF NOT EXISTS lookup_stem_breakage (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_stem_form (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_terrain_form (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_terrain (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_tree_size_class (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_tree_species_group (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_tree_species (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
ALTER TABLE lookup_tree_species
ADD COLUMN taxonomy_order varchar(1) NULL;
ALTER TABLE lookup_tree_species
ADD COLUMN height_group varchar(20) NULL;
ALTER TABLE lookup_tree_species
ADD COLUMN genus text NULL;
ALTER TABLE lookup_tree_species
ADD COLUMN species text NULL;
CREATE TABLE IF NOT EXISTS lookup_tree_status (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_basal_area_factor (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_trees_less_4meter_layer (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_trees_less_4meter_mirrored (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_trees_less_4meter_origin (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_harvest_restriction (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
--CREATE TABLE IF NOT EXISTS lookup_harvest_restriction_source (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_accessibility (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_biotope (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_damage_peel (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_bark_condition (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
-- External Lookup Tables
CREATE TABLE lookup_ffh (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE lookup_national_park (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE lookup_natur_park (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE lookup_vogel_schutzgebiet (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE lookup_biogeographische_region (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE lookup_biosphaere (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
ALTER TABLE lookup_biosphaere
ADD COLUMN bfn_code varchar(20) NULL;
CREATE TABLE lookup_natur_schutzgebiet (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE lookup_forestry_office (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE lookup_district (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE lookup_municipality (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
ALTER TABLE lookup_municipality
ADD COLUMN code_district INTEGER NULL REFERENCES lookup.lookup_district (code);
--CREATE TABLE lookup_usage_type (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE lookup_interval (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
-- change code to type text
ALTER TABLE lookup.lookup_interval
ALTER COLUMN code TYPE text USING code::text;
INSERT INTO lookup.lookup_interval (code, name_de, name_en, sort)
VALUES ('bwi1987', 'BWI 1987', 'BWI 1987', 1),
    ('bwi1992', 'BWI 1992', 'BWI 1992', 2),
    ('bwi2002', 'BWI 2002', 'BWI 2002', 3),
    ('ci2000', 'CI 2008', 'CI 2008', 4),
    ('bwi2012', 'BWI 2012', 'BWI 2012', 5),
    ('ci2012', 'CI 2012', 'CI 2012', 6),
    ('ci2017', 'CI 2017', 'CI 2017', 7),
    ('bwi2022', 'BWI 2022', 'BWI 2022', 8),
    ('ci2027', 'CI 2027', 'CI 2027', 9);
CREATE TABLE lookup_layer (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
-- 
CREATE TABLE IF NOT EXISTS lookup_edge_type (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
INSERT INTO lookup.lookup_edge_type (code, name_de, name_en, interval, sort)
VALUES (
        10,
        'neue, erstmals eingemessene Grenze zu Nichtwald',
        'New boundary to non-forest, measured for the first time',
        ARRAY ['ci2027'],
        10
    ),
    (
        11,
        'neue, erstmals eingemessene Grenze zu Nichtwald, welche auch für frühere Aufnahmen gilt',
        'New boundary to non-forest, measured for the first time, which also applies to earlier surveys',
        ARRAY ['ci2027'],
        11
    ),
    (
        12,
        'aus früherer Aufnahme übernommene, immer noch gültige Grenze zu Nichtwald',
        'Still valid boundary to non-forest, taken over from previous recording',
        ARRAY ['ci2027'],
        12
    ),
    (
        20,
        'neue, erstmals eingemessene Grenze zu Nichtholzboden',
        'New boundary to unstocked forest land, measured for the first time',
        ARRAY ['ci2027'],
        20
    ),
    (
        21,
        'neue, erstmals eingemessene Grenze zu Nichtholzboden, welche auch für frühere Aufnahmen gilt',
        'New boundary to unstocked forest land, measured for the first time, which also applies to earlier surveys',
        ARRAY ['ci2027'],
        21
    ),
    (
        22,
        'aus früherer Aufnahme übernommene, immer noch gültige Grenze zu Nichtholzboden',
        'Still valid boundary to unstocked forest land, taken over from previous recording',
        ARRAY ['ci2027'],
        22
    ),
    (
        30,
        'neue, erstmals eingemessene Grenze zu nicht begehbaren Holzboden',
        'New boundary to non-accessible forest floor measured for the first time',
        ARRAY ['ci2027'],
        30
    ),
    (
        31,
        'neue, erstmals eingemessene Grenze zu nicht begehbaren Holzboden, welche auch für frühere Aufnahmen gilt',
        'New boundary to non-accessible forest, measured for the first time, which also applies to earlier surveys',
        ARRAY ['ci2027'],
        31
    ),
    (
        32,
        'aus früherer Aufnahme übernommene, immer noch gültige Grenze zu nicht begehbaren Holzboden',
        'Still valid boundary to non-accessible forest, taken over from previous recording',
        ARRAY ['ci2027'],
        32
    ),
    (
        42,
        'aus früherer Aufnahme übernommene, immer noch gültige Bestandesgrenze',
        'Still valid boundary between different stands, taken over from previous recording',
        ARRAY ['ci2027'],
        42
    ),
    (
        99,
        'Grenze einer früheren Aufnahme, die zum aktuellen Inventurzeitpunkt nicht mehr auffindbar bzw. nicht mehr gültig ist',
        'Boundary of a previous inventory that can no longer be found or is no longer valid at the current survey',
        ARRAY ['ci2027'],
        99
    );
CREATE TABLE IF NOT EXISTS lookup_edge_type_deprecated (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
--INSERT INTO lookup.lookup_edge_type_deprecated (code, name_de, name_en, interval, sort)
--VALUES
--    (10, 'neue, erstmals eingemessene Grenze zu Nichtwald', 'New boundary to non-forest, measured for the first time', ARRAY['bwi2027'], 10),
--    (11, 'neue, erstmals eingemessene Grenze zu Nichtwald, welche auch für frühere Aufnahmen gilt', 'New boundary to non-forest, measured for the first time, which also applies to earlier surveys', ARRAY['bwi2027'], 11),
--    (12, 'aus früherer Aufnahme übernommene, immer noch gültige Grenze zu Nichtwald', 'Still valid boundary to non-forest, taken over from previous recording', ARRAY['bwi2027'], 12),
--    (20, 'neue, erstmals eingemessene Grenze zu Nichtholzboden', 'New boundary to unstocked forest land, measured for the first time', ARRAY['bwi2027'], 20),
--    (21, 'neue, erstmals eingemessene Grenze zu Nichtholzboden, welche auch für frühere Aufnahmen gilt', 'New boundary to unstocked forest land, measured for the first time, which also applies to earlier surveys', ARRAY['bwi2027'], 21),
--    (22, 'aus früherer Aufnahme übernommene, immer noch gültige Grenze zu Nichtholzboden', 'Still valid boundary to unstocked forest land, taken over from previous recording', ARRAY['bwi2027'], 22),
--    (30, 'neue, erstmals eingemessene Grenze zu nicht begehbaren Holzboden', 'New boundary to non-accessible forest floor measured for the first time', ARRAY['bwi2027'], 30),
--    (31, 'neue, erstmals eingemessene Grenze zu nicht begehbaren Holzboden, welche auch für frühere Aufnahmen gilt', 'New boundary to non-accessible forest, measured for the first time, which also applies to earlier surveys', ARRAY['bwi2027'], 31),
--    (32, 'aus früherer Aufnahme übernommene, immer noch gültige Grenze zu nicht begehbaren Holzboden', 'Still valid boundary to non-accessible forest, taken over from previous recording', ARRAY['bwi2027'], 32),
--    (42, 'aus früherer Aufnahme übernommene, immer noch gültige Bestandesgrenze', 'Still valid boundary between different stands, taken over from previous recording', ARRAY['bwi2027'], 42),
--    (99, 'Grenze einer früheren Aufnahme, die zum aktuellen Inventurzeitpunkt nicht mehr auffindbar bzw. nicht mehr gültig ist', 'Boundary of a previous inventory that can no longer be found or is no longer valid at the current survey', ARRAY['bwi2027'], 99);
CREATE TABLE lookup_edge_stand_difference (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
INSERT INTO lookup.lookup_edge_stand_difference (code, name_de, name_en, interval, sort)
VALUES (
        1,
        'mindestens 10m und maximal 20m geringere Bestandeshöhe (das kann auch eine Blöße oder Nichtholzboden sein)',
        'At least 10m and maximum 20m lower stand height (this can also be temporary unstocked area or unstocked forest land floor)',
        ARRAY ['bwi2027'],
        1
    ),
    (
        2,
        'mindestens 20m geringere Bestandeshöhe (das kann auch eine Blöße oder Nichtholzboden sein)',
        'At least 20m lower stand height (this can also be temporary unstocked area or unstocked forest land floor)',
        ARRAY ['bwi2027'],
        2
    ),
    (
        3,
        'mindestens 20%-ige Änderung der Baumartenanteile bei einem Höhenunterschied von weniger als 10m',
        'At least 20% change in the proportion of tree species with a height difference of less than 10 metres',
        ARRAY ['bwi2027'],
        3
    ),
    (
        4,
        'mindestens 20%-ige Änderung der Baumartenanteile bei einem Höhenunterschied bei mindestens 10m und maximal 20m',
        'At least 20% change in the proportion of tree species with a height difference of at least 10m and maximum 20m',
        ARRAY ['bwi2027'],
        4
    ),
    (
        9,
        'keiner der genannten Fälle',
        'None of the cases mentioned',
        ARRAY ['bwi2027'],
        9
    );
CREATE TABLE IF NOT EXISTS lookup_support_point_type (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
INSERT INTO lookup.lookup_support_point_type (code, name_de, name_en, interval, sort)
VALUES (
        1,
        'versetzte Markierung',
        'Displaced marker',
        ARRAY ['ci2027'],
        1
    ),
    (
        2,
        'markanter Geländepunkt',
        'Landmark',
        ARRAY ['ci2027'],
        2
    ),
    (
        3,
        'Startpunkt Trakteinmessung',
        'Starting point for cluster location',
        ARRAY ['ci2027'],
        3
    ),
    (
        4,
        'Sicherung Startpunkt',
        'Supporting point for cluster location start',
        ARRAY ['ci2027'],
        4
    ),
    (
        5,
        'Hilfspunkt GNSS',
        'Supporting point GNSS measurement',
        ARRAY ['ci2027'],
        5
    )