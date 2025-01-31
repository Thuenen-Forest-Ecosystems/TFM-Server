SET default_transaction_read_only = OFF;

-- SCHEMA inventory_archive
CREATE SCHEMA inventory_archive;
ALTER SCHEMA inventory_archive OWNER TO postgres;
COMMENT ON SCHEMA inventory_archive IS 'Kohlenstoffinventur 2027';
GRANT USAGE ON SCHEMA inventory_archive TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA inventory_archive TO anon, authenticated, service_role;
GRANT ALL ON ALL ROUTINES IN SCHEMA inventory_archive TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA inventory_archive TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA inventory_archive GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA inventory_archive GRANT ALL ON ROUTINES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA inventory_archive GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;


SET search_path TO inventory_archive;

CREATE TABLE IF NOT EXISTS table_TEMPLATE (
    intkey varchar(12) UNIQUE NULL, 
    id uuid UNIQUE DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL,
    modified_at TIMESTAMP DEFAULT NULL,
	modified_by uuid DEFAULT auth.uid() NULL,
    supervisor_id uuid DEFAULT auth.uid() NULL,
    selectable_by uuid[] DEFAULT ARRAY[]::uuid[] NULL,
    updatable_by uuid[] DEFAULT ARRAY[]::uuid[] NULL
);



------------------------------------------------- CLUSTER -------------------------------------------------
CREATE TABLE cluster (LIKE table_TEMPLATE INCLUDING ALL);
ALTER TABLE cluster 
    ADD COLUMN cluster_name integer NOT NULL,
	ADD COLUMN topo_map_sheet integer NULL,
	ADD COLUMN state_responsible text NULL,
	ADD COLUMN states_affected text[] NULL,
	ADD COLUMN grid_density text NULL,
	ADD COLUMN cluster_status text NULL,
	ADD COLUMN cluster_situation text NULL;

ALTER TABLE cluster ADD CONSTRAINT FK_cluster_ModifiedBy
    FOREIGN KEY (modified_by)
    REFERENCES auth.users (id);
ALTER TABLE cluster ADD CONSTRAINT FK_cluster_SupervisorId
    FOREIGN KEY (supervisor_id)
    REFERENCES auth.users (id);

ALTER TABLE cluster ADD CONSTRAINT FK_Cluster_Unique UNIQUE (cluster_name);

ALTER TABLE cluster ADD CONSTRAINT FK_Cluster_LookupStateResponsible
	FOREIGN KEY (state_responsible)
	REFERENCES lookup.lookup_state (abbreviation);

ALTER TABLE cluster ADD CONSTRAINT FK_Cluster_LookupGridDensity
    FOREIGN KEY (grid_density)
    REFERENCES lookup.lookup_grid_density (abbreviation);

ALTER TABLE cluster ADD CONSTRAINT FK_Cluster_LookupClusterStatus
    FOREIGN KEY (cluster_status)
    REFERENCES lookup.lookup_cluster_status (abbreviation);

ALTER TABLE cluster ADD CONSTRAINT FK_Cluster_LookupClusterSituation
    FOREIGN KEY (cluster_situation)
    REFERENCES lookup.lookup_cluster_situation (abbreviation);

------------------------------------------------- PLOT -------------------------------------------------
CREATE TABLE plot (LIKE table_TEMPLATE INCLUDING ALL);
ALTER TABLE plot 
    ADD COLUMN sampling_stratum INTEGER NOT NULL,
    ADD COLUMN federal_state text NULL,
    --ADD COLUMN center_location public.GEOMETRY(Point, 4326), -- geom NEU
	ADD COLUMN growth_district text  NULL, -- wb
	ADD COLUMN forest_status text NULL, -- wa
	ADD COLUMN accessibility smallint NULL, -- begehbar TODO: Lookup Table
	ADD COLUMN forest_office smallint NULL, -- fa
	ADD COLUMN elevation_level text NULL, -- nathoe
	ADD COLUMN property_type text NULL, -- eg
	ADD COLUMN property_size_class text NULL, -- eggrkl
	ADD COLUMN forest_community text NULL, -- natwgv
	ADD COLUMN forest_community_field text NULL, -- natwg
	ADD COLUMN ffh_forest_type text NULL, -- wlt_v
	ADD COLUMN ffh_forest_type_field text NULL, --wlt
	ADD COLUMN land_use_before text NULL, -- lanu
	ADD COLUMN land_use_after text NULL, -- lanu
	ADD COLUMN coast BOOLEAN NULL DEFAULT FALSE, --kueste
	ADD COLUMN sandy BOOLEAN NULL DEFAULT FALSE, -- gestein
	ADD COLUMN protected_landscape BOOLEAN NULL DEFAULT FALSE, -- lsg
	ADD COLUMN histwald BOOLEAN NULL DEFAULT FALSE, -- histwald
	ADD COLUMN harvest_restriction INTEGER NULL, -- ne TODO: Lookup Table & enum
	ADD COLUMN harvest_restriction_source INTEGER[] DEFAULT '{}', -- NEU: create enum_harvest_restriction_source Nutzungseinschränkungen als Array TODO: Lookup Table, inner- und außerbetrieblich zusammenführen
	ADD COLUMN landmark_azimuth integer NULL, -- mark_azi
	ADD COLUMN landmark_distance smallint NULL, -- mark_hori
	ADD COLUMN landmark_note varchar(12)  NULL, -- mark_beschreibung
	ADD COLUMN marker_status text NULL, -- perm: Das Feld bietet kein Mehrwert, da perm_profile die gleiche Information enthält
	ADD COLUMN marker_azimuth integer NULL, -- perm_azi: 
	ADD COLUMN marker_distance smallint NULL, -- perm_hori
	ADD COLUMN marker_profile text NULL, -- perm_profil -- TODO: enum_marker_profile + Lookup
	ADD COLUMN terrain_form text NULL, -- gform
	ADD COLUMN terrain_slope integer NULL, -- gneig [Grad]
	ADD COLUMN terrain_exposure integer NULL, -- gexp [Gon]
	ADD COLUMN management_type text NULL, -- be
	ADD COLUMN harvesting_method text NULL, -- ernte (x3_ernte)
	ADD COLUMN biotope integer NULL, -- biotop (x3_biotop)
	ADD COLUMN stand_structure text NULL, -- ab
	ADD COLUMN stand_age integer NULL, -- al_best
	ADD COLUMN stand_dev_phase text NULL, -- phase
	ADD COLUMN stand_layer_reg text NULL, -- b0_bs
	ADD COLUMN fence_reg BOOLEAN NULL DEFAULT FALSE, -- b0_zaun
	ADD COLUMN trees_greater_4meter_mirrored text NULL, -- schigt4_sp (gespiegelt)
	ADD COLUMN trees_greater_4meter_basal_area_factor text NULL, -- schigt4_zf
	ADD COLUMN trees_less_4meter_coverage smallint NULL, -- schile4_bedg
	ADD COLUMN trees_less_4meter_layer text NULL,
	
	ADD COLUMN biogeographische_region text NULL, -- BiogeogrRegion
	ADD COLUMN biosphaere text NULL, -- Biosphaere
	ADD COLUMN ffh text NULL, -- FFH
	ADD COLUMN national_park text NULL, -- NationalP
	ADD COLUMN natur_park text NULL, -- NaturP
	ADD COLUMN vogel_schutzgebiet text NULL, -- VogelSG
	ADD COLUMN natur_schutzgebiet text NULL -- NaturSG

	; -- schile4_schi


ALTER TABLE plot ADD CONSTRAINT FK_plot_ModifiedBy
    FOREIGN KEY (modified_by)
    REFERENCES auth.users (id);
ALTER TABLE plot ADD CONSTRAINT FK_plot_SupervisorId
    FOREIGN KEY (supervisor_id)
    REFERENCES auth.users (id);

ALTER TABLE plot ADD COLUMN IF NOT EXISTS plot_name integer NOT NULL;
ALTER TABLE plot ADD COLUMN IF NOT EXISTS cluster_id integer NOT NULL;
--- make id unique
ALTER TABLE plot ADD CONSTRAINT FK_Plot_Unique UNIQUE (cluster_id, plot_name);
ALTER TABLE plot ADD CONSTRAINT FK_Plot_Cluster_Unique UNIQUE (cluster_id, plot_name);



ALTER TABLE plot ADD COLUMN IF NOT EXISTS federal_state INTEGER  NOT NULL;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupState
    FOREIGN KEY (federal_state)
    REFERENCES lookup.lookup_state (abbreviation);

ALTER TABLE plot ADD CONSTRAINT FK_Plot_Cluster FOREIGN KEY (cluster_id)
	REFERENCES cluster (cluster_name) MATCH SIMPLE
	ON DELETE CASCADE;

ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupGrowthDistrict FOREIGN KEY (growth_district)
        REFERENCES lookup.lookup_growth_district (abbreviation) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION;

ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupForestStatus FOREIGN KEY (forest_status)
		REFERENCES lookup.lookup_forest_status (abbreviation) MATCH SIMPLE
		ON UPDATE NO ACTION
		ON DELETE NO ACTION;
--ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupForestrOffice FOREIGN KEY (forestry_office) --TODO
--		REFERENCES lookup_forestry_office (abbreviation) MATCH SIMPLE
--		ON UPDATE NO ACTION
--		ON DELETE NO ACTION;

ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupElevationLevel FOREIGN KEY (elevation_level) 
	REFERENCES lookup.lookup_elevation_level (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupPropertyType FOREIGN KEY (property_type)
	REFERENCES lookup.lookup_property_type (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupPropertySizeClass FOREIGN KEY (property_size_class)
	REFERENCES lookup.lookup_property_size_class (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
--ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupForestCommunity FOREIGN KEY (forest_community)
--	REFERENCES lookup_forest_community (abbreviation) MATCH SIMPLE
--	ON UPDATE NO ACTION
--	ON DELETE NO ACTION;

--ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupFfhForestType FOREIGN KEY (ffh_forest_type)
--	REFERENCES lookup_ffh_forest_type (abbreviation) MATCH SIMPLE
--	ON UPDATE NO ACTION
--	ON DELETE NO ACTION;
--
--ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupFfhForestTypeSource FOREIGN KEY (ffh_forest_type_source)
--	REFERENCES lookup_ffh_forest_type_source (abbreviation) MATCH SIMPLE
--	ON UPDATE NO ACTION
--	ON DELETE NO ACTION;
--
--ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupHarvestRestriction FOREIGN KEY (harvest_restriction)
--	REFERENCES lookup_harvest_restriction (abbreviation) MATCH SIMPLE
--	ON UPDATE NO ACTION
--	ON DELETE NO ACTION;
--
--ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupLandUse FOREIGN KEY (land_use_before)
--	REFERENCES lookup_land_use (abbreviation) MATCH SIMPLE
--	ON UPDATE NO ACTION
--	ON DELETE NO ACTION;

ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupLandUse FOREIGN KEY (land_use_after)
	REFERENCES lookup.lookup_land_use (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
--ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupHarvestRestrictionSource FOREIGN KEY (harvest_restriction_source)
--	REFERENCES lookup_use_restriction_source (abbreviation) MATCH SIMPLE
--	ON UPDATE NO ACTION
--	ON DELETE NO ACTION;

ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupMarkerStatus FOREIGN KEY (marker_status)
	REFERENCES lookup.lookup_marker_status (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupMarkerProfile FOREIGN KEY (marker_profile)
	REFERENCES lookup.lookup_marker_profile (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupTerrainForm FOREIGN KEY (terrain_form)
	REFERENCES lookup.lookup_terrain_form (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupManagementType FOREIGN KEY (management_type)
	REFERENCES lookup.lookup_management_type (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupHarvestingMethod FOREIGN KEY (harvesting_method)
	REFERENCES lookup.lookup_harvesting_method (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
--ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupBiotope FOREIGN KEY (biotope)
--	REFERENCES lookup_biotope (abbreviation) MATCH SIMPLE
--	ON UPDATE NO ACTION
--	ON DELETE NO ACTION;

ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupStandStructure FOREIGN KEY (stand_structure)
	REFERENCES lookup.lookup_stand_structure (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupStandDevPhase FOREIGN KEY (stand_dev_phase)
	REFERENCES lookup.lookup_stand_dev_phase (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupStandLayer FOREIGN KEY (stand_layer_reg)
	REFERENCES lookup.lookup_stand_layer (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupTreesLess4meterMirrored FOREIGN KEY (trees_greater_4meter_mirrored)
	REFERENCES lookup.lookup_trees_less_4meter_mirrored (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;

ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupBiosgeographischeRegion FOREIGN KEY (biogeographische_region)
	REFERENCES lookup_external.lookup_biogeographische_region (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupBiosphaere FOREIGN KEY (biosphaere)
	REFERENCES lookup_external.lookup_biosphaere (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupFfh FOREIGN KEY (ffh)
	REFERENCES lookup_external.lookup_ffh (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupNationalPark FOREIGN KEY (national_park)
	REFERENCES lookup_external.lookup_national_park (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupNaturePark FOREIGN KEY (natur_park)
	REFERENCES lookup_external.lookup_natur_park (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupVogelSchutzgebiet FOREIGN KEY (vogel_schutzgebiet)
	REFERENCES lookup_external.lookup_vogel_schutzgebiet (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupNatureSchutzgebiet FOREIGN KEY (natur_schutzgebiet)
	REFERENCES lookup_external.lookup_natur_schutzgebiet (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;

--ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupTreesLess4meterCountFactor FOREIGN KEY (trees_less_4meter_count_factor)
--	REFERENCES lookup_trees_less_4meter_count_factor (abbreviation) MATCH SIMPLE
--	ON UPDATE NO ACTION
--	ON DELETE NO ACTION;
--
--ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupTreesLess4meterLayer FOREIGN KEY (trees_less_4meter_layer)
--	REFERENCES lookup_trees_less_4meter_layer (abbreviation) MATCH SIMPLE
--	ON UPDATE NO ACTION
--	ON DELETE NO ACTION;
--

--CONSTRAINT FK_Plot_Lookupgrid FOREIGN KEY (grid)
--        REFERENCES lookup_grid (abbreviation) MATCH SIMPLE
--        ON UPDATE NO ACTION
--        ON DELETE NO ACTION,
--CONSTRAINT FK_Plot_LookupStateAdministration FOREIGN KEY (state_administration)
--        REFERENCES lookup_states (abbreviation) MATCH SIMPLE
--        ON UPDATE NO ACTION
--        ON DELETE NO ACTION,	
--CONSTRAINT FK_Plot_LookupStateCollect FOREIGN KEY (state_collect)
--        REFERENCES lookup_states (abbreviation) MATCH SIMPLE
--        ON UPDATE NO ACTION
--        ON DELETE NO ACTION,;

CREATE TABLE plot_coordinates (LIKE table_TEMPLATE INCLUDING ALL);
ALTER TABLE plot_coordinates 
    ADD COLUMN plot_id uuid UNIQUE NOT NULL,
    ADD COLUMN center_location public.GEOMETRY(Point, 4326), -- bwi.koord.b0_ecke_soll
	ADD COLUMN cartesian_x float NOT NULL, -- bwi.koord.b0_ecke_soll.Soll_Hoch
	ADD COLUMN cartesian_y float NOT NULL; -- bwi.koord.b0_ecke_soll.Soll_Recht

ALTER TABLE plot_coordinates ADD CONSTRAINT FK_PlotPosition_Plot FOREIGN KEY (plot_id)
	REFERENCES plot (id) MATCH SIMPLE
	ON DELETE CASCADE;

------------------------------------------------- TREE -------------------------------------------------
CREATE TABLE tree (LIKE table_TEMPLATE INCLUDING ALL);
ALTER TABLE tree 
    ADD COLUMN tree_number smallint NOT NULL,
    ADD COLUMN plot_id uuid NOT NULL,
	ADD COLUMN tree_marked boolean NOT NULL DEFAULT false,
	ADD COLUMN tree_status text NULL,
	ADD COLUMN azimuth SMALLINT NOT NULL,
	ADD COLUMN distance smallint NOT NULL,
	ADD COLUMN geometry public.GEOMETRY(POINT, 4326) NULL,
	ADD COLUMN tree_species text NULL,
	ADD COLUMN dbh smallint NULL,
	ADD COLUMN dbh_height smallint NULL DEFAULT 130,
	ADD COLUMN tree_height smallint NULL,
	ADD COLUMN stem_height smallint NULL,
	ADD COLUMN tree_height_azimuth smallint NULL,
	ADD COLUMN tree_height_distance smallint NULL,
	ADD COLUMN tree_age smallint NULL,
	ADD COLUMN stem_breakage text NULL DEFAULT '0', -- Kh
	ADD COLUMN stem_form text NULL DEFAULT '0', --Kst
	ADD COLUMN pruning text NULL, -- Ast
	ADD COLUMN pruning_height smallint NULL, -- Ast_Hoe (Astungungshöhe [dm])
	ADD COLUMN within_stand BOOLEAN NULL DEFAULT false, -- Bz https://git-dmz.thuenen.de/datenerfassunginventory_archive/inventory_archive_datenerfassung/inventory_archive-db-structure/-/issues/3#note_24310
	ADD COLUMN stand_layer text NULL, -- Bs //saplings_layer
	ADD COLUMN damage_dead boolean NULL DEFAULT false, -- Tot
	ADD COLUMN damage_peel_new boolean NULL DEFAULT false, -- jSchael
	ADD COLUMN damage_peel_old boolean NULL DEFAULT false, -- aeSchael
	ADD COLUMN damage_logging boolean NULL DEFAULT false, -- Ruecke
	ADD COLUMN damage_fungus boolean NULL DEFAULT false, -- Pilz
	ADD COLUMN damage_resin boolean NULL DEFAULT false, -- Harz
	ADD COLUMN damage_beetle boolean NULL DEFAULT false, -- Kaefer
	ADD COLUMN damage_other boolean NULL DEFAULT false, -- sStamm
	ADD COLUMN cave_tree boolean NULL DEFAULT false, -- Hoehle
	ADD COLUMN crown_dead_wood boolean NULL DEFAULT false, -- Bizarr
	ADD COLUMN tree_top_drought boolean NULL DEFAULT false, -- Uralt
	ADD COLUMN bark_pocket boolean NULL DEFAULT false, -- Rindentaschen
	ADD COLUMN biotope_marked boolean NULL DEFAULT false,
	ADD COLUMN bark_condition smallint NULL;

ALTER TABLE tree ADD CONSTRAINT FK_Tree_Plot_Unique UNIQUE (plot_id, tree_number);
ALTER TABLE tree ADD CONSTRAINT FK_Tree_Plot FOREIGN KEY (plot_id)
	REFERENCES plot (id) MATCH SIMPLE
	ON DELETE CASCADE;

ALTER TABLE tree ADD CONSTRAINT FK_WzpTree_TreeStatus FOREIGN KEY (tree_status)
	REFERENCES lookup.lookup_tree_status (abbreviation) MATCH SIMPLE;
ALTER TABLE tree ADD CONSTRAINT FK_WzpTree_TreeSpecies FOREIGN KEY (tree_species)
	REFERENCES lookup.lookup_tree_species (abbreviation) MATCH SIMPLE;
ALTER TABLE tree ADD CONSTRAINT FK_WzpTree_StemBreakage FOREIGN KEY (stem_breakage)
	REFERENCES lookup.lookup_stem_breakage (abbreviation) MATCH SIMPLE;
ALTER TABLE tree ADD CONSTRAINT FK_WzpTree_StemForm FOREIGN KEY (stem_form)
	REFERENCES lookup.lookup_stem_form (abbreviation) MATCH SIMPLE;
ALTER TABLE tree ADD CONSTRAINT FK_WzpTree_Prunging FOREIGN KEY (pruning)
	REFERENCES lookup.lookup_pruning (abbreviation) MATCH SIMPLE;
ALTER TABLE tree ADD CONSTRAINT FK_WzpTree_StandLayer FOREIGN KEY (stand_layer)
	REFERENCES lookup.lookup_stand_layer (abbreviation) MATCH SIMPLE;


------------------------------------------------- POSITION -------------------------------------------------
CREATE TABLE position (LIKE table_TEMPLATE INCLUDING ALL);
ALTER TABLE position
	ADD COLUMN plot_id uuid NOT NULL,
    ADD COLUMN position_median public.GEOMETRY(Point, 4326) NOT NULL,
	ADD COLUMN position_mean public.GEOMETRY(Point, 4326) NOT NULL,
	ADD COLUMN hdop_mean float NOT NULL, -- HDOP  MEAN OR MEDIAN ???
	ADD COLUMN pdop_mean float NOT NULL, -- PDOP  MEAN OR MEDIAN ???
	ADD COLUMN satellites_count_mean float NOT NULL, -- NumSat MEAN OR MEDIAN ???
	ADD COLUMN measurement_count smallint NOT NULL, -- AnzahlMessungen
	ADD COLUMN rtcm_age float NULL, -- RTCMAlter
	ADD COLUMN start_measurement timestamp NOT NULL, -- UTCStartzeit
	ADD COLUMN stop_measurement timestamp NOT NULL, -- UTCStopzeit
	ADD COLUMN device_gnss text NULL, -- Geraet (smallint) || ToDo: Ist hier ein freies Eingabefeld nicht sinnvoller ???
	ADD COLUMN quality text NULL; -- GNSS_Qualitaet

ALTER TABLE position ADD CONSTRAINT FK_Position_Plot FOREIGN KEY (plot_id)
	REFERENCES plot (id)
	ON DELETE CASCADE;
ALTER TABLE position ADD CONSTRAINT FK_Position_LookupGnssQuality FOREIGN KEY (quality)
	REFERENCES lookup.lookup_gnss_quality (abbreviation);

------------------------------------------------- POSITION -------------------------------------------------
CREATE TABLE edges (LIKE table_TEMPLATE INCLUDING ALL);
ALTER TABLE edges
	ADD COLUMN plot_id uuid NOT NULL,
	ADD COLUMN edge_number INTEGER NULL, -- NEU: Kanten-ID || ToDo: Welchen Mehrwert hat diese ID gegenüber der ID?
	ADD COLUMN edge_status text NULL, --Rk
	ADD COLUMN edge_type text NULL, --Rart
	ADD COLUMN terrain text NULL, --Rterrain
	ADD COLUMN edges JSONB NOT NULL, -- NEU: GeoJSON
	ADD COLUMN geometry_edges public.GEOMETRY(LineString, 4326) NULL; -- NEU: Geometrie

ALTER TABLE edges ADD CONSTRAINT FK_Edges_Plot FOREIGN KEY (plot_id)
	REFERENCES plot (id)
	ON DELETE CASCADE;
ALTER TABLE edges ADD CONSTRAINT FK_Edge_LookupEdgeStatus FOREIGN KEY (edge_status)
	REFERENCES lookup.lookup_edge_status (abbreviation);
ALTER TABLE edges ADD CONSTRAINT FK_Edge_LookupEdgeType FOREIGN KEY (edge_type)
	REFERENCES lookup.lookup_edge_type (abbreviation);
ALTER TABLE edges ADD CONSTRAINT FK_Edge_LookupTerrain FOREIGN KEY (terrain)
	REFERENCES lookup.lookup_terrain (abbreviation);

------------------------------------------------- REGENERATION -------------------------------------------------
CREATE TABLE regeneration (LIKE table_TEMPLATE INCLUDING ALL);
ALTER TABLE regeneration
    ADD COLUMN plot_id uuid NOT NULL,
	ADD COLUMN tree_species text NULL, --Ba
	ADD COLUMN browsing text NULL, --Biss
	ADD COLUMN tree_size_class text NULL, --Gr
	ADD COLUMN damage_peel smallint NULL, --Schael
	ADD COLUMN protection_individual boolean NULL, --Schu
	ADD COLUMN tree_count smallint NOT NULL; --Anz

ALTER TABLE regeneration ADD CONSTRAINT FK_Saplings2m_Plot FOREIGN KEY (plot_id) REFERENCES plot(id) MATCH SIMPLE
	ON DELETE CASCADE;
ALTER TABLE regeneration ADD CONSTRAINT FK_Saplings2m_LookupTreeSpecies FOREIGN KEY (tree_species)
    REFERENCES lookup.lookup_tree_species (abbreviation);
ALTER TABLE regeneration ADD CONSTRAINT FK_Saplings2m_LookupBrowsing FOREIGN KEY (browsing)
    REFERENCES lookup.lookup_browsing (abbreviation);
ALTER TABLE regeneration ADD CONSTRAINT FK_Saplings2m_LookupTreeSizeClass FOREIGN KEY (tree_size_class)
    REFERENCES lookup.lookup_tree_size_class (abbreviation);

------------------------------------------------- STRUCTURE LESS THAN 4 METER -------------------------------------------------
CREATE TABLE structure_lt4m (LIKE table_TEMPLATE INCLUDING ALL);
ALTER TABLE structure_lt4m
	ADD COLUMN plot_id uuid NOT NULL,
	ADD COLUMN tree_species text NULL, --Ba
	ADD COLUMN coverage INTEGER NOT NULL, --Anteil TODO: enum_coverage NEU
	ADD COLUMN regeneration_type INTEGER NULL; --Vart TODO: enum_reg_type NEU

ALTER TABLE structure_lt4m ADD CONSTRAINT FK_StructureLt4m_Plot FOREIGN KEY (plot_id) REFERENCES plot(id)
	ON DELETE CASCADE;
ALTER TABLE structure_lt4m ADD CONSTRAINT FK_StructureLt4m_LookupTreeSpecies FOREIGN KEY (tree_species)
    REFERENCES lookup.lookup_tree_species (abbreviation);


------------------------------------------------- DEADWOOD -------------------------------------------------
CREATE TABLE deadwood (LIKE table_TEMPLATE INCLUDING ALL);
ALTER TABLE deadwood
	ADD COLUMN plot_id uuid NOT NULL,
	ADD COLUMN tree_species_group text NULL, -- Tbagr
	ADD COLUMN dead_wood_type text NULL, -- Tart
	ADD COLUMN decomposition text NULL, -- Tzg
	ADD COLUMN length_height smallint NULL, -- Tl
	ADD COLUMN diameter_butt smallint NOT NULL, -- Tbd
	ADD COLUMN diameter_top smallint NULL, -- Tsd
	ADD COLUMN count smallint NULL, -- Anz
	ADD COLUMN bark_pocket smallint NULL; -- TRinde

ALTER TABLE deadwood ADD CONSTRAINT FK_Deadwood_Plot FOREIGN KEY (plot_id)
	REFERENCES plot (id)
	ON DELETE CASCADE;
ALTER TABLE deadwood ADD CONSTRAINT FK_Deadwood_LookupTreeSpeciesGroup FOREIGN KEY (tree_species_group)
	REFERENCES lookup.lookup_tree_species_group (abbreviation);
ALTER TABLE deadwood ADD CONSTRAINT FK_Deadwood_LookupDeadWoodType FOREIGN KEY (dead_wood_type)
	REFERENCES lookup.lookup_dead_wood_type (abbreviation);
ALTER TABLE deadwood ADD CONSTRAINT FK_Deadwood_LookupDecomposition FOREIGN KEY (decomposition)
	REFERENCES lookup.lookup_decomposition (abbreviation);


------------------------------------------------- PLOT LOCATION -------------------------------------------------
CREATE TABLE plot_location (LIKE table_TEMPLATE INCLUDING ALL);
ALTER TABLE plot_location
	ADD COLUMN parent_table text NOT NULL,
	ADD COLUMN azimuth smallint NOT NULL, -- Azimuth (Gon) NEU
    ADD COLUMN distance smallint NOT NULL  DEFAULT 500, -- Distance (cm) NEU
    ADD COLUMN radius smallint NOT NULL DEFAULT 100, -- Radius (cm) NEU
    -- ADD COLUMN geometry public.GEOMETRY(POINT, 4326) NULL, -- Geometry (Polygon) NEU
    ADD COLUMN no_entities BOOLEAN DEFAULT FALSE -- Sub Plot is marked as "has no entities". 
