SET default_transaction_read_only = OFF;
-- SCHEMA lookup
CREATE SCHEMA IF NOT EXISTS lookup;
ALTER SCHEMA lookup OWNER TO postgres;
COMMENT ON SCHEMA lookup IS 'Lookup Tabellen';
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
ADD COLUMN IF NOT EXISTS growth_region smallint NULL REFERENCES lookup.lookup_growth_region (code);
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
ADD COLUMN IF NOT EXISTS abbreviation text NULL;
CREATE TABLE IF NOT EXISTS lookup_stem_breakage (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_stem_form (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_terrain_form (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_terrain (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_tree_size_class (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_tree_species_group (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_tree_species (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
ALTER TABLE lookup_tree_species
ADD COLUMN IF NOT EXISTS taxonomy_order varchar(1) NULL;
ALTER TABLE lookup_tree_species
ADD COLUMN IF NOT EXISTS height_group varchar(20) NULL;
ALTER TABLE lookup_tree_species
ADD COLUMN IF NOT EXISTS genus text NULL;
ALTER TABLE lookup_tree_species
ADD COLUMN IF NOT EXISTS species text NULL;
CREATE TABLE IF NOT EXISTS lookup_tree_status (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
INSERT INTO lookup.lookup_tree_status (code, name_de, name_en, interval, sort)
VALUES (
        2022,
        'schon 2022 (BWI2022) ausgefallen',
        'already failed during German National Forest Inventory 2022',
        ARRAY ['bwi2022', 'ci2027'],
        2022
    ),
    (
        2017,
        'schon 2017 (CI2017) ausgefallen',
        'already failed during GHG inventory 2017',
        ARRAY ['ci2017', 'bwi2022', 'ci2027'],
        2017
    );
CREATE TABLE IF NOT EXISTS lookup_basal_area_factor (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
-- was commented out before
--CREATE TABLE IF NOT EXISTS lookup_trees_less_4meter_layer (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_trees_greater_4meter_mirrored (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_trees_less_4meter_origin (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_harvest_restriction (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
--CREATE TABLE IF NOT EXISTS lookup_harvest_restriction_source (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_accessibility (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_biotope (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_damage_peel (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_bark_condition (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
-- External Lookup Tables
CREATE TABLE IF NOT EXISTS lookup_ffh (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_national_park (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_natur_park (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_vogel_schutzgebiet (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_biogeographische_region (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_biosphaere (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
ALTER TABLE lookup_biosphaere
ADD COLUMN bfn_code varchar(20) NULL;
CREATE TABLE lookup_natur_schutzgebiet (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
--CREATE TABLE lookup_forestry_office (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE lookup_district (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE lookup_municipality (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
ALTER TABLE lookup_municipality
ADD COLUMN IF NOT EXISTS code_district INTEGER NULL REFERENCES lookup.lookup_district (code);
--CREATE TABLE lookup_usage_type (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_interval (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
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
    ('ci2027', 'CI 2027', 'CI 2027', 9) ON CONFLICT (code) DO
UPDATE
SET name_de = EXCLUDED.name_de,
    name_en = EXCLUDED.name_en,
    interval = EXCLUDED.interval,
    sort = EXCLUDED.sort;
CREATE TABLE IF NOT EXISTS lookup_layer (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
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
    ) ON CONFLICT (code) DO
UPDATE
SET name_de = EXCLUDED.name_de,
    name_en = EXCLUDED.name_en,
    interval = EXCLUDED.interval,
    sort = EXCLUDED.sort;
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
CREATE TABLE IF NOT EXISTS lookup_edge_stand_difference (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
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
    ) ON CONFLICT (code) DO
UPDATE
SET name_de = EXCLUDED.name_de,
    name_en = EXCLUDED.name_en,
    interval = EXCLUDED.interval,
    sort = EXCLUDED.sort;
CREATE TABLE IF NOT EXISTS lookup.lookup_support_point_type (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
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
    ) ON CONFLICT (code) DO
UPDATE
SET name_de = EXCLUDED.name_de,
    name_en = EXCLUDED.name_en,
    interval = EXCLUDED.interval,
    sort = EXCLUDED.sort;
-- NEW Table: lookup_cover_percentage
CREATE TABLE IF NOT EXISTS lookup.lookup_cover_percentage (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
INSERT INTO lookup.lookup_cover_percentage (code, name_de, name_en, interval, sort)
VALUES (
        0,
        '< 10 %',
        '< 10 %',
        ARRAY ['bwi2002', 'bwi2012', 'bwi2022', 'ci2027'],
        1
    ),
    (
        1,
        'ca. 10 % (10 % bis 14 %)',
        'ca. 10 % (10 % to 14 %)',
        ARRAY ['bwi2002', 'bwi2012', 'bwi2022', 'ci2027'],
        2
    ),
    (
        2,
        'ca. 20 % (15 % bis 24 %)',
        'ca. 20 % (15 % to 24 %)',
        ARRAY ['bwi2002', 'bwi2012', 'bwi2022', 'ci2027'],
        3
    ),
    (
        3,
        'ca. 30 % (25 % bis 34 %)',
        'ca. 30 % (25 % to 34 %)',
        ARRAY ['bwi2002', 'bwi2012', 'bwi2022', 'ci2027'],
        4
    ),
    (
        4,
        'ca. 40 % (35 % bis 44 %)',
        'ca. 40 % (35 % to 44 %)',
        ARRAY ['bwi2002', 'bwi2012', 'bwi2022', 'ci2027'],
        5
    ),
    (
        5,
        'ca. 50 % (45 % bis 54 %)',
        'ca. 50 % (45 % to 54 %)',
        ARRAY ['bwi2002', 'bwi2012', 'bwi2022', 'ci2027'],
        6
    ),
    (
        6,
        'ca. 60 % (55 % bis 64 %)',
        'ca. 60 % (55 % to 64 %)',
        ARRAY ['bwi2002', 'bwi2012', 'bwi2022', 'ci2027'],
        7
    ),
    (
        7,
        'ca. 70 % (65 % bis 74 %)',
        'ca. 70 % (65 % to 74 %)',
        ARRAY ['bwi2002', 'bwi2012', 'bwi2022', 'ci2027'],
        8
    ),
    (
        8,
        'ca. 80 % (75 % bis 84 %)',
        'ca. 80 % (75 % to 84 %)',
        ARRAY ['bwi2002', 'bwi2012', 'bwi2022', 'ci2027'],
        9
    ),
    (
        9,
        'ca. 90 % (85 % bis 94 %)',
        'ca. 90 % (85 % to 94 %)',
        ARRAY ['bwi2002', 'bwi2012', 'bwi2022', 'ci2027'],
        10
    ),
    (
        10,
        'ca. 100 % (95 % bis 100 %)',
        'ca. 100 % (95 % to 100 %)',
        ARRAY ['bwi2002', 'bwi2012', 'bwi2022', 'ci2027'],
        11
    ) ON CONFLICT (code) DO
UPDATE
SET name_de = EXCLUDED.name_de,
    name_en = EXCLUDED.name_en,
    interval = EXCLUDED.interval,
    sort = EXCLUDED.sort;
CREATE TABLE IF NOT EXISTS lookup_gnss_quality (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
INSERT INTO lookup.lookup_gnss_quality (code, name_de, name_en, interval, sort)
VALUES (
        0,
        'Fix nicht gültig',
        'Fix not valid',
        ARRAY ['bwi2012', 'ci2017', 'bwi2022', 'ci2027'],
        9
    ),
    (
        1,
        'GNSS (1) - Viertbeste Qualität',
        'GPS fix',
        ARRAY ['bwi2012', 'ci2017', 'bwi2022', 'ci2027'],
        4
    ),
    (
        2,
        'DGNSS (2) - Drittbeste Qualität',
        'Differential GPS fix (DGNSS), SBAS, OmniSTAR VBS, Beacon, RTX in GVBS mode',
        ARRAY ['bwi2012', 'ci2017', 'bwi2022', 'ci2027'],
        3
    ),
    (
        3,
        'Nicht anwendbar',
        'Not applicable',
        ARRAY ['bwi2012', 'ci2017', 'bwi2022', 'ci2027'],
        10
    ),
    (
        4,
        'RTK fixed (4) - Beste Qualität',
        'RTK Fixed, xFill',
        ARRAY ['bwi2012', 'ci2017', 'bwi2022', 'ci2027'],
        1
    ),
    (
        5,
        'RTK floating (5) - Zweitbeste Qualität',
        'RTK Float, OmniSTAR XP/HP, Location RTK, RTX',
        ARRAY ['bwi2012', 'ci2017', 'bwi2022', 'ci2027'],
        2
    ),
    (
        6,
        'Koppelnavigation',
        'INS Dead reckoning',
        ARRAY ['bwi2012', 'ci2017', 'bwi2022', 'ci2027'],
        10
    ),
    (
        9,
        'GNSS (9) - Viertbeste Qualität',
        'GNSS - fourth best quality',
        ARRAY ['bwi2012', 'ci2017', 'bwi2022', 'ci2027'],
        5
    ),
    (
        91,
        'WGS84-Koordinatennachlieferung mit nachträglicher Umrechnung von WGS84 zu Gauß-Krüger',
        'External coordinates with transformation from WGS84 to Gauß-Krüger',
        ARRAY ['bwi2012', 'ci2017', 'bwi2022', 'ci2027'],
        7
    ),
    (
        92,
        'Gauß-Krüger-Koordinatennachlieferung mit nachträglicher Umrechnung von Gauß-Krüger zu WGS84',
        'External coordinates with transformation from Gauß-Krüger to WGS84',
        ARRAY ['bwi2012', 'ci2017', 'bwi2022', 'ci2027'],
        8
    ),
    (
        93,
        'Koordinaten aus Postprocessing. Qualität unbekannt',
        'External coordinates from post-processing, unknown quality',
        ARRAY ['bwi2012', 'ci2017', 'bwi2022', 'ci2027'],
        6
    ) ON CONFLICT (code) DO
UPDATE
SET name_de = EXCLUDED.name_de,
    name_en = EXCLUDED.name_en,
    interval = EXCLUDED.interval,
    sort = EXCLUDED.sort;
CREATE TABLE IF NOT EXISTS lookup_object_type (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
INSERT INTO lookup.lookup_object_type (code, name_de, name_en, interval, sort)
VALUES (
        0,
        'Aufnahmeland',
        'state responsible for inventory',
        ARRAY ['bwi2012', 'ci2017', 'bwi2022', 'ci2027'],
        1
    ),
    (
        1,
        'Trakt insgesamt',
        'cluster total',
        ARRAY ['bwi2012', 'ci2017', 'bwi2022', 'ci2027'],
        2
    ),
    (
        2,
        'Traktecke insgesamt',
        'plot total',
        ARRAY ['bwi2012', 'ci2017', 'bwi2022', 'ci2027'],
        3
    ),
    (
        3,
        'Forsteinrichtung',
        'forest management',
        ARRAY ['bwi2012', 'ci2017', 'bwi2022', 'ci2027'],
        4
    ),
    (
        9,
        'WZP/ZF4-Probebaum (WZP4)',
        'ACS/BAF4-sample tree (WZP4)',
        ARRAY ['bwi2012', 'ci2017', 'bwi2022', 'ci2027'],
        5
    ),
    (
        11,
        'Wald- oder Bestandesrand (RAN)',
        'forest or stand structure (RAN)',
        ARRAY ['bwi2012', 'ci2017', 'bwi2022', 'ci2027'],
        6
    ),
    (
        12,
        'Bäume der Baumgröße 1 bis 6 (früher P175, jetzt JUNG)',
        'trees of tree height 1 to 6 (earlier P175)',
        ARRAY ['bwi2012', 'ci2017', 'bwi2022', 'ci2027'],
        7
    ),
    (
        13,
        'Bäume der Baumgröße 0 (früher P100, jetzt JUNG)',
        'trees of tree height 0 (earlier P100)',
        ARRAY ['bwi2012', 'ci2017', 'bwi2022', 'ci2027'],
        8
    ),
    (
        14,
        'WZP/ZF1oder2-Probebaum (größer als 4 m, EBS)',
        'ACS/BAF1 or 2-sample tree (higher than 4 m, EBS)',
        ARRAY ['bwi2012', 'ci2017', 'bwi2022', 'ci2027'],
        9
    ),
    (
        15,
        '10m-Probebaum (kleiner gleich 4 m, EBS)',
        '10m sample tree (<= 4 m, EBS)',
        ARRAY ['bwi2012', 'ci2017', 'bwi2022', 'ci2027'],
        10
    ),
    (
        17,
        'Totholzstück (TOT)',
        'piece of deadwood (DEAD)',
        ARRAY ['bwi2012', 'ci2017', 'bwi2022', 'ci2027'],
        11
    ),
    (
        18,
        'Weg (WEG)',
        'path (WEG)',
        ARRAY ['bwi2012', 'ci2017', 'bwi2022', 'ci2027'],
        12
    ),
    (
        21,
        'forstlich bedeutsame Art (FBA)',
        'important forest species',
        ARRAY ['bwi2012', 'ci2017', 'bwi2022', 'ci2027'],
        13
    ),
    (
        22,
        'Vegetationsart (EWLT)',
        'vegetation type (EWLT)',
        ARRAY ['bwi2012', 'ci2017', 'bwi2022', 'ci2027'],
        14
    ),
    (
        29,
        'Bodenerhebung (BOD)',
        'soil survey',
        ARRAY ['bwi2012', 'ci2017', 'bwi2022', 'ci2027'],
        15
    ) ON CONFLICT (code) DO
UPDATE
SET name_de = EXCLUDED.name_de,
    name_en = EXCLUDED.name_en,
    interval = EXCLUDED.interval,
    sort = EXCLUDED.sort;