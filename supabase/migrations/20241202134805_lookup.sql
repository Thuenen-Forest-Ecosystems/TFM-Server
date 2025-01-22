SET default_transaction_read_only = OFF;
-- SCHEMA lookup
CREATE SCHEMA lookup;
ALTER SCHEMA lookup OWNER TO postgres;
COMMENT ON SCHEMA lookup IS 'Lookup Tabellen';
GRANT USAGE ON SCHEMA lookup TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA lookup TO anon, authenticated, service_role;
GRANT ALL ON ALL ROUTINES IN SCHEMA lookup TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA lookup TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA lookup GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA lookup GRANT ALL ON ROUTINES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA lookup GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;



SET search_path TO lookup;

CREATE TABLE IF NOT EXISTS lookup_TEMPLATE (
    abbreviation text UNIQUE NOT NULL,
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL,
    name_de text NOT NULL,
    name_en text NULL,
    interval text[] NULL,
    sort INTEGER NULL
);



CREATE TABLE IF NOT EXISTS lookup_browsing (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_cluster_situation (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_cluster_status (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_dead_wood_type (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_decomposition (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_edge_status (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_edge_type (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_elevation_level (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_exploration_instruction (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_ffh_forest_type_field (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_forest_community_field (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_forest_office (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_forest_status (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_gnss_quality (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_grid_density (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_growth_district (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_harvesting_method (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_land_use (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_management_type (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_marker_profile (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_marker_status (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_property_size_class (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_property_type (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_pruning (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_sampling_stratum (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_stand_dev_phase (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_stand_layer (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_stand_structure (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_state (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_stem_breakage (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_stem_form (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_terrain_form (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_terrain (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_tree_size_class (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_tree_species_group (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_tree_species (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
ALTER TABLE lookup_tree_species ADD COLUMN taxonomy_order varchar(1) NULL;
ALTER TABLE lookup_tree_species ADD COLUMN height_group varchar(20) NULL;

CREATE TABLE IF NOT EXISTS lookup_tree_status (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_trees_less_4meter_count_factor (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_trees_less_4meter_layer (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_trees_less_4meter_mirrored (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_trees_less_4meter_origin (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);
CREATE TABLE IF NOT EXISTS lookup_use_restriction (LIKE lookup.lookup_TEMPLATE INCLUDING ALL);