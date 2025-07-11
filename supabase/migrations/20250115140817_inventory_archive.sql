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
    intkey varchar(50) UNIQUE NULL,
    id uuid UNIQUE DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL
    --modified_at TIMESTAMP DEFAULT NULL,
	--modified_by uuid DEFAULT auth.uid() NULL,
    --supervisor_id uuid DEFAULT auth.uid() NULL,
    --selectable_by uuid[] DEFAULT ARRAY[]::uuid[] NULL,
    --updatable_by uuid[] DEFAULT ARRAY[]::uuid[] NULL
);



------------------------------------------------- CLUSTER -------------------------------------------------
CREATE TABLE cluster (LIKE table_TEMPLATE INCLUDING ALL);
ALTER TABLE cluster 
    ADD COLUMN cluster_name INTEGER NOT NULL CHECK (cluster_name >= 1),
	ADD COLUMN topo_map_sheet INTEGER NULL,
	ADD COLUMN state_responsible INTEGER NULL, -- lookup_state
	ADD COLUMN states_affected INTEGER[] NULL, -- lookup_state
	ADD COLUMN grid_density INTEGER NULL, -- lookup_grid_density
	ADD COLUMN cluster_status INTEGER NULL, -- lookup_state
	ADD COLUMN cluster_situation INTEGER NULL,
	ADD COLUMN inspire_grid_cell TEXT NOT NULL; -- lookup_cluster_status

--ALTER TABLE cluster ADD CONSTRAINT FK_cluster_ModifiedBy
--    FOREIGN KEY (modified_by)
--    REFERENCES auth.users (id);
--ALTER TABLE cluster ADD CONSTRAINT FK_cluster_SupervisorId
--    FOREIGN KEY (supervisor_id)
--    REFERENCES auth.users (id);

ALTER TABLE cluster ADD CONSTRAINT FK_Cluster_Unique UNIQUE (cluster_name);

ALTER TABLE cluster ADD CONSTRAINT FK_Cluster_LookupStateResponsible
	FOREIGN KEY (state_responsible)
	REFERENCES lookup.lookup_state (code);

ALTER TABLE cluster ADD CONSTRAINT FK_Cluster_LookupGridDensity
    FOREIGN KEY (grid_density)
    REFERENCES lookup.lookup_grid_density (code);

ALTER TABLE cluster ADD CONSTRAINT FK_Cluster_LookupClusterStatus
    FOREIGN KEY (cluster_status)
    REFERENCES lookup.lookup_cluster_status (code);

ALTER TABLE cluster ADD CONSTRAINT FK_Cluster_LookupClusterSituation
    FOREIGN KEY (cluster_situation)
    REFERENCES lookup.lookup_cluster_situation (code);

------------------------------------------------- PLOT -------------------------------------------------
CREATE TABLE plot (LIKE table_TEMPLATE INCLUDING ALL);
ALTER TABLE plot 
	ADD COLUMN interval_name text default 'ci2027' references lookup.lookup_interval (code) NOT NULL,
    ADD COLUMN sampling_stratum INTEGER NULL,
    ADD COLUMN federal_state INTEGER NULL, -- lookup_state
    --ADD COLUMN center_location public.GEOMETRY(Point, 4326), -- move to plot_coordinates
	ADD COLUMN growth_district INTEGER  NULL, -- wb -- lookup_growth_district
	ADD COLUMN forest_status INTEGER NULL, -- wa -- lookup_forest_status
	ADD COLUMN accessibility INTEGER NULL, -- begehbar lookup_accessibility <- TODO: Lookup Table
	ADD COLUMN forest_office INTEGER NULL, -- fa -- lookup_forest_office
	ADD COLUMN elevation_level INTEGER NULL, -- nathoe -- lookup_elevation_level
	ADD COLUMN property_type INTEGER NULL, -- eg -- lookup_property_type
	ADD COLUMN property_size_class INTEGER NULL, -- eggrkl -- lookup_property_size_class
	ADD COLUMN forest_community INTEGER NULL, -- natwgv -- lookup_forest_community
	ADD COLUMN forest_community_field INTEGER NULL, -- natwg -- lookup_forest_community
	ADD COLUMN ffh_forest_type INTEGER NULL, -- wlt_v -- lookup_ffh_forest_type
	ADD COLUMN ffh_forest_type_field INTEGER NULL, --wlt -- lookup_ffh_forest_type
	ADD COLUMN land_use_before INTEGER NULL, -- lanu -- lookup_land_use
	ADD COLUMN land_use_after INTEGER NULL, -- lanu -- lookup_land_use
	ADD COLUMN coast BOOLEAN NULL DEFAULT FALSE, --kueste
	ADD COLUMN sandy BOOLEAN NULL DEFAULT FALSE, -- gestein
	ADD COLUMN protected_landscape BOOLEAN DEFAULT FALSE, -- lsg
	ADD COLUMN histwald BOOLEAN NULL DEFAULT FALSE, -- histwald
	ADD COLUMN harvest_restriction INTEGER NULL, -- ne TODO: Lookup Table & enum
	--ADD COLUMN harvest_restriction_source INTEGER NULL, -- NEU: NeUrsacheB
	ADD COLUMN marker_status INTEGER NULL, -- perm lookup_marker_status
	ADD COLUMN marker_azimuth INTEGER NULL CHECK (marker_azimuth >= 0 AND marker_azimuth <= 399), -- perm_azi: 
	ADD COLUMN marker_distance SMALLINT NULL CHECK (marker_distance >= 0 AND marker_distance <= 15000), -- perm_hori Zentimeter 
	ADD COLUMN marker_profile INTEGER NULL, -- perm_profil -- lookup_marker_profile
	ADD COLUMN terrain_form INTEGER NULL, -- gform -- lookup_terrain_form
	ADD COLUMN terrain_slope SMALLINT NULL CHECK (terrain_slope >= 0 AND terrain_slope <= 90), -- gneig [Grad]
	ADD COLUMN terrain_exposure SMALLINT NULL CHECK (terrain_exposure >= 0 AND terrain_exposure <= 399), -- gexp [Gon]
	ADD COLUMN management_type INTEGER NULL, -- be - lookup_management_type
	ADD COLUMN harvest_condition INTEGER NULL, -- ernte (x3_ernte) - lookup_harvest_condition
	ADD COLUMN biotope INTEGER NULL, -- biotop (x3_biotop) - lookup_biotope
	ADD COLUMN stand_structure INTEGER NULL, -- ab - lookup_stand_structure
	ADD COLUMN stand_age SMALLINT NULL, -- al_best 
	ADD COLUMN stand_development_phase SMALLINT NULL, -- phase - lookup_stand_dev_phase
	ADD COLUMN stand_layer_regeneration INTEGER NULL, -- b0_bs
	ADD COLUMN fence_regeneration BOOLEAN NULL DEFAULT FALSE, -- b0_zaun
	
	ADD COLUMN trees_greater_4meter_mirrored INTEGER NULL, -- schigt4_sp (gespiegelt) lookup_trees_less_4meter_mirrored
	ADD COLUMN trees_greater_4meter_basal_area_factor INTEGER NULL, -- schigt4_zf lookup_basal_area_factor
	
	ADD COLUMN trees_less_4meter_coverage SMALLINT NULL CHECK (trees_less_4meter_coverage >= 0 AND trees_less_4meter_coverage <= 100), -- schile4_bedg 
	ADD COLUMN trees_less_4meter_layer INTEGER NULL, -- lookup_trees_less_4meter_layer
	
	ADD COLUMN biogeographische_region INTEGER NULL, -- BiogeogrRegion lookup_biogeographische_region
	ADD COLUMN biosphaere INTEGER NULL, -- Biosphaere - lookup_biosphaere
	ADD COLUMN ffh INTEGER NULL, -- FFH - lookup_ffh
	ADD COLUMN national_park INTEGER NULL, -- NationalP lookup_national_park
	ADD COLUMN natur_park INTEGER NULL, -- NaturP lookup_natur_park
	ADD COLUMN vogel_schutzgebiet INTEGER NULL, -- VogelSG lookup_vogel_schutzgebiet
	ADD COLUMN natur_schutzgebiet INTEGER NULL, -- NaturSG lookup_natur_schutzgebiet

	ADD COLUMN harvest_restriction_nature_reserve boolean NULL DEFAULT FALSE, -- NeNSchutz - Naturschutz
	ADD COLUMN harvest_restriction_protection_forest boolean NULL DEFAULT FALSE, -- NeSWald - Schutzwald
	ADD COLUMN harvest_restriction_recreational_forest boolean NULL DEFAULT FALSE, -- NeEWald - Erholungswald
	--ADD COLUMN harvest_restriction_NeSABUrsach boolean NOT NULL DEFAULT FALSE, -- NeSABUrsach - Ursache der Nutzungseinschränkung 9-sonstige außerbetriebliche Ursachen
	ADD COLUMN harvest_restriction_scattered boolean NULL DEFAULT FALSE, -- NESplitter - Splitterbesitz - Ursache der Nutzungseinschränkung 11-Splitterbesitz mit unwirtschaftlicher Größe
	ADD COLUMN harvest_restriction_fragmented boolean NULL DEFAULT FALSE, -- NeStreu - Streulage - Ursache der Nutzungseinschränkung 12-Streulage
	ADD COLUMN harvest_restriction_insufficient_access boolean NULL DEFAULT FALSE, -- NeUnErschlies - unzur. Erschließung - Ursache der Nutzungseinschränkung 13-unzureichender Erschließung
	ADD COLUMN harvest_restriction_wetness boolean NULL DEFAULT FALSE, -- NeGelEig - Gelände - Ursache der Nutzungseinschränkung 14-Geländeeigenschaften, Nassstandort
	ADD COLUMN harvest_restriction_low_yield boolean NULL DEFAULT FALSE, -- NeGerErtrag - geringer Ertrag - Ursache der Nutzungseinschränkung 15-geringer Ertragserwartungen (dGZ < 1 m³/(ha*a))
	ADD COLUMN harvest_restriction_private_conservation boolean NULL DEFAULT FALSE, -- NeEigenbin - Eigenbindung - Ursache der Nutzungseinschränkung 16-Schutzflächen in Eigenbindung (z.B. Naturreservate)
	ADD COLUMN harvest_restriction_other_internalcause boolean NULL DEFAULT FALSE, -- NeSIBUrsach - s. innerbetriebl. Urs. - Ursache der Nutzungseinschränkung 19-sonstige innerbetriebliche Ursachen
	
	--ADD COLUMN usage_type INTEGER NULL -- NutzArt
	ADD COLUMN harvest_method INTEGER NULL REFERENCES lookup.lookup_harvest_method (code), -- NutzArt
	ADD COLUMN harvest_reason INTEGER NULL REFERENCES lookup.lookup_harvest_reason (code) -- Nutzursache
	;


--ALTER TABLE plot ADD CONSTRAINT FK_plot_ModifiedBy
--    FOREIGN KEY (modified_by)
--    REFERENCES auth.users (id);
--ALTER TABLE plot ADD CONSTRAINT FK_plot_SupervisorId
--    FOREIGN KEY (supervisor_id)
--    REFERENCES auth.users (id);


--- make id unique
ALTER TABLE plot ADD COLUMN IF NOT EXISTS plot_name integer NOT NULL CHECK (plot_name >= 1 AND plot_name <= 4);
ALTER TABLE plot ADD COLUMN IF NOT EXISTS cluster_name integer NOT NULL; -- REFERENCES cluster (cluster_name);
ALTER TABLE plot ADD COLUMN IF NOT EXISTS cluster_id uuid NOT NULL REFERENCES cluster (id);
ALTER TABLE plot ADD CONSTRAINT FK_Plot_Unique UNIQUE (cluster_name, plot_name, interval_name);
--ALTER TABLE plot ADD CONSTRAINT FK_Plot_Cluster_Unique UNIQUE (cluster_name, plot_name);



ALTER TABLE plot ADD COLUMN IF NOT EXISTS federal_state INTEGER  NOT NULL;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupState
    FOREIGN KEY (federal_state)
    REFERENCES lookup.lookup_state (code);

ALTER TABLE plot ADD CONSTRAINT FK_Plot_Cluster FOREIGN KEY (cluster_name)
	REFERENCES cluster (cluster_name) MATCH SIMPLE
	ON DELETE CASCADE;

ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupGrowthDistrict FOREIGN KEY (growth_district)
        REFERENCES lookup.lookup_growth_district (code) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION;

ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupForestStatus FOREIGN KEY (forest_status)
		REFERENCES lookup.lookup_forest_status (code) MATCH SIMPLE
		ON UPDATE NO ACTION
		ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupForestrOffice FOREIGN KEY (forest_office)
		REFERENCES lookup.lookup_forest_office (code) MATCH SIMPLE
		ON UPDATE NO ACTION
		ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupElevationLevel FOREIGN KEY (elevation_level) 
	REFERENCES lookup.lookup_elevation_level (code) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupPropertyType FOREIGN KEY (property_type)
	REFERENCES lookup.lookup_property_type (code) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupPropertySizeClass FOREIGN KEY (property_size_class)
	REFERENCES lookup.lookup_property_size_class (code) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupForestCommunity FOREIGN KEY (forest_community)
	REFERENCES lookup.lookup_forest_community (code) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupForestCommunityField FOREIGN KEY (forest_community_field)
	REFERENCES lookup.lookup_forest_community (code) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupFfhForestType FOREIGN KEY (ffh_forest_type)
	REFERENCES lookup.lookup_ffh_forest_type (code) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupFfhForestTypeField FOREIGN KEY (ffh_forest_type_field)
	REFERENCES lookup.lookup_ffh_forest_type (code) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;

ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupHarvestRestriction FOREIGN KEY (harvest_restriction)
	REFERENCES lookup.lookup_harvest_restriction (code) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;

ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupLandUseBefore FOREIGN KEY (land_use_before)
	REFERENCES lookup.lookup_land_use (code) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupLandUseAfter FOREIGN KEY (land_use_after)
	REFERENCES lookup.lookup_land_use (code) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;

ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupMarkerStatus FOREIGN KEY (marker_status)
	REFERENCES lookup.lookup_marker_status (code) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupMarkerProfile FOREIGN KEY (marker_profile)
	REFERENCES lookup.lookup_marker_profile (code) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupTerrainForm FOREIGN KEY (terrain_form)
	REFERENCES lookup.lookup_terrain_form (code) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupManagementType FOREIGN KEY (management_type)
	REFERENCES lookup.lookup_management_type (code) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupHarvestingMethod FOREIGN KEY (harvest_condition)
	REFERENCES lookup.lookup_harvest_condition (code) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupBiotope FOREIGN KEY (biotope)
	REFERENCES lookup.lookup_biotope (code) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;

ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupStandStructure FOREIGN KEY (stand_structure)
	REFERENCES lookup.lookup_stand_structure (code) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupStandDevPhase FOREIGN KEY (stand_development_phase)
	REFERENCES lookup.lookup_stand_development_phase (code) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupStandLayer FOREIGN KEY (stand_layer_regeneration)
	REFERENCES lookup.lookup_stand_layer (code) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupTreesLess4meterMirrored FOREIGN KEY (trees_greater_4meter_mirrored)
	REFERENCES lookup.lookup_trees_less_4meter_mirrored (code) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;

ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupBiosgeographischeRegion FOREIGN KEY (biogeographische_region)
	REFERENCES lookup.lookup_biogeographische_region (code) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupBiosphaere FOREIGN KEY (biosphaere)
	REFERENCES lookup.lookup_biosphaere (code) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupFfh FOREIGN KEY (ffh)
	REFERENCES lookup.lookup_ffh (code) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupNationalPark FOREIGN KEY (national_park)
	REFERENCES lookup.lookup_national_park (code) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupNaturePark FOREIGN KEY (natur_park)
	REFERENCES lookup.lookup_natur_park (code) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupVogelSchutzgebiet FOREIGN KEY (vogel_schutzgebiet)
	REFERENCES lookup.lookup_vogel_schutzgebiet (code) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupNatureSchutzgebiet FOREIGN KEY (natur_schutzgebiet)
	REFERENCES lookup.lookup_natur_schutzgebiet (code) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;

ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupTreesLess4meterCountFactor FOREIGN KEY (trees_greater_4meter_basal_area_factor)
	REFERENCES lookup.lookup_basal_area_factor (code) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupTreesLess4meterLayer FOREIGN KEY (trees_less_4meter_layer)
	REFERENCES lookup.lookup_trees_less_4meter_layer (code) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;

-- usage_type
--ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupUsageType FOREIGN KEY (usage_type)
--	REFERENCES lookup.lookup_usage_type (code) MATCH SIMPLE
--	ON UPDATE NO ACTION
--	ON DELETE NO ACTION;


------------------------------------------------- PLOT COORDINATES -------------------------------------------------

CREATE TABLE plot_coordinates (LIKE table_TEMPLATE INCLUDING ALL);
ALTER TABLE plot_coordinates
    ADD COLUMN plot_id uuid UNIQUE NOT NULL,
    ADD COLUMN center_location public.GEOMETRY(Point, 4326), -- bwi.koord.b0_ecke_soll
	ADD COLUMN cartesian_x float NOT NULL, -- bwi.koord.b0_ecke_soll.Soll_Hoch
	ADD COLUMN cartesian_y float NOT NULL; -- bwi.koord.b0_ecke_soll.Soll_Recht

--- remove column intkey due to does not exist in the new data model
ALTER TABLE plot_coordinates DROP COLUMN IF EXISTS intkey;

ALTER TABLE plot_coordinates ADD CONSTRAINT FK_PlotPosition_Plot FOREIGN KEY (plot_id)
	REFERENCES plot (id) MATCH SIMPLE
	ON DELETE CASCADE;

------------------------------------------------- PLOT LANDMARK -------------------------------------------------

CREATE TABLE plot_landmark (LIKE table_TEMPLATE INCLUDING ALL);
ALTER TABLE plot_landmark 
    ADD COLUMN plot_id uuid NOT NULL,
	ADD COLUMN landmark_azimuth SMALLINT NOT NULL CHECK (landmark_azimuth >= 0 AND landmark_azimuth <= 399), -- mark_azi [Gon]
	ADD COLUMN landmark_distance SMALLINT NOT NULL CHECK (landmark_distance > 0), -- mark_hori [cm]
	ADD COLUMN landmark_note TEXT NOT NULL; -- mark_beschreibung

--- remove column intkey due to does not exist in the new data model

ALTER TABLE plot_landmark ADD CONSTRAINT FK_PlotLandmark_Plot FOREIGN KEY (plot_id)
	REFERENCES plot (id) MATCH SIMPLE
	ON DELETE CASCADE;

------------------------------------------------- TREE -------------------------------------------------
CREATE TABLE tree (LIKE table_TEMPLATE INCLUDING ALL);
ALTER TABLE tree 
    ADD COLUMN tree_number smallint NOT NULL,
    ADD COLUMN plot_id uuid NOT NULL,
	ADD COLUMN tree_marked boolean DEFAULT false,
	ADD COLUMN tree_status INTEGER NULL,
	ADD COLUMN azimuth SMALLINT NOT NULL CHECK (azimuth >= 0 AND azimuth <= 399), -- [Gon]
	ADD COLUMN distance smallint NULL CHECK (distance >= 0), -- [cm]
	-- ADD COLUMN geometry public.GEOMETRY(POINT, 4326) NULL,
	ADD COLUMN tree_species INTEGER NULL,
	ADD COLUMN dbh smallint NULL,
	ADD COLUMN dbh_height smallint NULL DEFAULT 130,
	ADD COLUMN tree_height smallint NULL,
	ADD COLUMN stem_height smallint NULL,
	ADD COLUMN tree_height_azimuth smallint NULL CHECK (tree_height_azimuth >= 0 AND tree_height_azimuth <= 399), -- MPos_Azi [Gon]
	ADD COLUMN tree_height_distance smallint NULL CHECK (tree_height_distance >= 200 AND tree_height_distance <= 7500), -- MPos_Hori [cm] 
	ADD COLUMN tree_age smallint NULL CHECK (tree_age > 0 AND tree_age <= 1000), -- Alter in Jahren
	ADD COLUMN stem_breakage INTEGER NULL DEFAULT 0, -- Kh
	ADD COLUMN stem_form INTEGER NULL DEFAULT 0, --Kst
	ADD COLUMN pruning INTEGER NULL, -- Ast
	-- ADD COLUMN pruning_height smallint NULL, -- Ast_Hoe (Astungungshöhe [dm]) Deprecated
	ADD COLUMN within_stand BOOLEAN NULL DEFAULT false, -- Bz https://git-dmz.thuenen.de/datenerfassunginventory_archive/inventory_archive_datenerfassung/inventory_archive-db-structure/-/issues/3#note_24310
	ADD COLUMN stand_layer INTEGER NULL, -- Bs //saplings_layer
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
	ADD COLUMN bark_condition smallint NULL,
	ADD COLUMN deadwood_used BOOLEAN DEFAULT FALSE;

ALTER TABLE tree ADD CONSTRAINT FK_Tree_Plot_Unique UNIQUE (plot_id, tree_number);
ALTER TABLE tree ADD CONSTRAINT FK_Tree_Plot FOREIGN KEY (plot_id)
	REFERENCES plot (id) MATCH SIMPLE
	ON DELETE CASCADE;

ALTER TABLE tree ADD CONSTRAINT FK_WzpTree_TreeStatus FOREIGN KEY (tree_status)
	REFERENCES lookup.lookup_tree_status (code) MATCH SIMPLE;
ALTER TABLE tree ADD CONSTRAINT FK_WzpTree_TreeSpecies FOREIGN KEY (tree_species)
	REFERENCES lookup.lookup_tree_species (code) MATCH SIMPLE;
ALTER TABLE tree ADD CONSTRAINT FK_WzpTree_StemBreakage FOREIGN KEY (stem_breakage)
	REFERENCES lookup.lookup_stem_breakage (code) MATCH SIMPLE;
ALTER TABLE tree ADD CONSTRAINT FK_WzpTree_StemForm FOREIGN KEY (stem_form)
	REFERENCES lookup.lookup_stem_form (code) MATCH SIMPLE;
ALTER TABLE tree ADD CONSTRAINT FK_WzpTree_Prunging FOREIGN KEY (pruning)
	REFERENCES lookup.lookup_pruning (code) MATCH SIMPLE;
ALTER TABLE tree ADD CONSTRAINT FK_WzpTree_StandLayer FOREIGN KEY (stand_layer)
	REFERENCES lookup.lookup_stand_layer (code) MATCH SIMPLE;

------------------------------------------------- Tree Coordinates -------------------------------------------------

CREATE TABLE tree_coordinates (LIKE table_TEMPLATE INCLUDING ALL);
ALTER TABLE tree_coordinates
	ADD COLUMN tree_id uuid NOT NULL REFERENCES tree (id) UNIQUE,
	ADD COLUMN tree_location public.GEOMETRY(Point, 4326) NOT NULL;

-- remove intkey column
ALTER TABLE tree_coordinates DROP COLUMN IF EXISTS intkey;


------------------------------------------------- POSITION -------------------------------------------------
CREATE TABLE position (LIKE table_TEMPLATE INCLUDING ALL);
ALTER TABLE position
	ADD COLUMN plot_id uuid NOT NULL,
    ADD COLUMN position_median public.GEOMETRY(Point, 4326) NOT NULL,
	ADD COLUMN position_mean public.GEOMETRY(Point, 4326) NOT NULL,
	ADD COLUMN hdop_mean float NOT NULL CHECK (hdop_mean >= 0), -- HDOP  MEAN OR MEDIAN ???
	ADD COLUMN pdop_mean float NULL CHECK (pdop_mean IS NULL OR pdop_mean >= 0), -- PDOP  MEAN OR MEDIAN ???
	ADD COLUMN satellites_count_mean float NOT NULL CHECK (satellites_count_mean >= 1), -- NumSat MEAN OR MEDIAN ???
	ADD COLUMN measurement_count smallint NOT NULL CHECK (measurement_count >= 1), -- AnzahlMessungen
	ADD COLUMN rtcm_age float NULL, -- RTCMAlter
	ADD COLUMN start_measurement timestamp NOT NULL, -- UTCStartzeit
	ADD COLUMN stop_measurement timestamp NOT NULL, -- UTCStopzeit
	ADD COLUMN device_gnss text NULL, -- Geraet (smallint) || ToDo: Ist hier ein freies Eingabefeld nicht sinnvoller ???
	ADD COLUMN quality INTEGER NULL; -- GNSS_Qualitaet

ALTER TABLE position ADD CONSTRAINT FK_Position_Plot FOREIGN KEY (plot_id)
	REFERENCES plot (id)
	ON DELETE CASCADE;
ALTER TABLE position ADD CONSTRAINT FK_Position_LookupGnssQuality FOREIGN KEY (quality)
	REFERENCES lookup.lookup_gnss_quality (code);

------------------------------------------------- EDGES -------------------------------------------------
CREATE TABLE edges (LIKE table_TEMPLATE INCLUDING ALL);
ALTER TABLE edges
	ADD COLUMN plot_id uuid NOT NULL,
	ADD COLUMN edge_number INTEGER NULL CHECK (edge_number >= 1), -- NEU: Kanten-ID || ToDo: Welchen Mehrwert hat diese ID gegenüber der ID?
	ADD COLUMN edge_status INTEGER NULL, --Rk
	ADD COLUMN edge_type INTEGER NULL, --Rart
	ADD COLUMN edge_type_deprecated INTEGER NULL REFERENCES lookup.lookup_edge_type_deprecated (code), --Rart_Alt
	ADD COLUMN terrain INTEGER NULL, --Rterrain
	ADD COLUMN edges JSONB NOT NULL, -- NEU: GeoJSON
	ADD COLUMN geometry_edges public.GEOMETRY(LineString, 4326) NULL,
	ADD COLUMN id_stand_differences_rows INTEGER NULL REFERENCES lookup.lookup_id_stand_differences_rows(code); -- NEU: Geometrie

ALTER TABLE edges ADD CONSTRAINT FK_Edges_Plot FOREIGN KEY (plot_id)
	REFERENCES plot (id)
	ON DELETE CASCADE;
ALTER TABLE edges ADD CONSTRAINT FK_Edge_LookupEdgeStatus FOREIGN KEY (edge_status)
	REFERENCES lookup.lookup_edge_status (code);
ALTER TABLE edges ADD CONSTRAINT FK_Edge_LookupEdgeType FOREIGN KEY (edge_type)
	REFERENCES lookup.lookup_edge_type (code);
ALTER TABLE edges ADD CONSTRAINT FK_Edge_LookupTerrain FOREIGN KEY (terrain)
	REFERENCES lookup.lookup_terrain (code);

	------------------------------------------------- EDGES -------------------------------------------------
CREATE TABLE edges_coordinates (LIKE table_TEMPLATE INCLUDING ALL);
ALTER TABLE edges_coordinates
	ADD COLUMN edge_id uuid NOT NULL REFERENCES edges (id) UNIQUE,
	ADD COLUMN geometry_edges public.GEOMETRY(LineString, 4326) NULL;


------------------------------------------------- REGENERATION -------------------------------------------------
CREATE TABLE regeneration (LIKE table_TEMPLATE INCLUDING ALL);
ALTER TABLE regeneration
    ADD COLUMN plot_id uuid NOT NULL,
	ADD COLUMN tree_species INTEGER NULL, --Ba
	ADD COLUMN browsing INTEGER NULL, --Biss
	ADD COLUMN tree_size_class INTEGER NULL, --Gr
	ADD COLUMN damage_peel smallint NULL, --Schael
	ADD COLUMN protection_individual boolean NULL, --Schu
	ADD COLUMN tree_count smallint NOT NULL CHECK (tree_count >= 1 AND tree_count <= 350); --Anz

ALTER TABLE regeneration ADD CONSTRAINT FK_Saplings2m_Plot FOREIGN KEY (plot_id) REFERENCES plot(id) MATCH SIMPLE
	ON DELETE CASCADE;
ALTER TABLE regeneration ADD CONSTRAINT FK_Saplings2m_LookupTreeSpecies FOREIGN KEY (tree_species)
    REFERENCES lookup.lookup_tree_species (code);
ALTER TABLE regeneration ADD CONSTRAINT FK_Saplings2m_LookupBrowsing FOREIGN KEY (browsing)
    REFERENCES lookup.lookup_browsing (code);
ALTER TABLE regeneration ADD CONSTRAINT FK_Saplings2m_LookupTreeSizeClass FOREIGN KEY (tree_size_class)
    REFERENCES lookup.lookup_tree_size_class (code);

------------------------------------------------- STRUCTURE LESS THAN 4 METER -------------------------------------------------
CREATE TABLE structure_lt4m (LIKE table_TEMPLATE INCLUDING ALL);
ALTER TABLE structure_lt4m
	ADD COLUMN plot_id uuid NOT NULL,
	ADD COLUMN tree_species INTEGER NULL, --Ba
	ADD COLUMN coverage INTEGER NOT NULL CHECK (coverage >= 1 AND coverage <= 100), --Anteil TODO: enum_coverage NEU
	ADD COLUMN regeneration_type INTEGER NULL; --Vart lookup_trees_less_4meter_origin

ALTER TABLE structure_lt4m ADD CONSTRAINT FK_StructureLt4m_Plot FOREIGN KEY (plot_id) REFERENCES plot(id)
	ON DELETE CASCADE;
ALTER TABLE structure_lt4m ADD CONSTRAINT FK_StructureLt4m_LookupTreeSpecies FOREIGN KEY (tree_species)
    REFERENCES lookup.lookup_tree_species (code);
ALTER TABLE structure_lt4m ADD CONSTRAINT FK_StructureLt4m_LookupLess4Origin FOREIGN KEY (regeneration_type)
    REFERENCES lookup.lookup_trees_less_4meter_origin (code);

------------------------------------------------- STRUCTURE GREATER THAN 8 METER -------------------------------------------------
CREATE TABLE structure_gt4m (LIKE table_TEMPLATE INCLUDING ALL);
ALTER TABLE structure_gt4m 
    ADD COLUMN plot_id uuid NOT NULL,
	ADD COLUMN tree_species SMALLINT NOT NULL, --Ba
  	ADD COLUMN stock_layer SMALLINT NOT NULL, --Schi, see lookup table bwi.xyk.x_Schi, ungleich stand_layer (vormals Bs)
	ADD COLUMN count SMALLINT NOT NULL, -- Anz,
  	ADD COLUMN is_mirrored BOOLEAN; --Sp


COMMENT ON TABLE structure_gt4m IS 'Winkelzählprobe mit Zählfaktor 1 oder 2 für die Bestockungsaufnahme - Bäume ab 4 m Höhe';

COMMENT ON COLUMN structure_gt4m.id IS 'Primary Key';
COMMENT ON COLUMN structure_gt4m.plot_id IS 'Foreign Key to Plot.id';
COMMENT ON COLUMN structure_gt4m.tree_species IS 'Baumart';
COMMENT ON COLUMN structure_gt4m.stock_layer IS 'Bestockungsschicht';
COMMENT ON COLUMN structure_gt4m.count IS 'Anzahl gleichartiger Bäume nach Baumart und Bestockungsschicht';
COMMENT ON COLUMN structure_gt4m.is_mirrored IS 'Manuelle Spiegelung bei WZP1/2  (Bäume über 4 m Höhe)';

ALTER TABLE structure_gt4m ADD CONSTRAINT FK_StructureGt4m_Plot FOREIGN KEY (plot_id) REFERENCES plot(id)
	ON DELETE CASCADE;

ALTER TABLE structure_gt4m ADD CONSTRAINT FK_StructureGt4m_LookupTreeSpecies FOREIGN KEY (tree_species)
    REFERENCES lookup.lookup_tree_species (code);

------------------------------------------------- DEADWOOD -------------------------------------------------
CREATE TABLE deadwood (LIKE table_TEMPLATE INCLUDING ALL);
ALTER TABLE deadwood
	ADD COLUMN plot_id uuid NOT NULL,
	ADD COLUMN tree_species_group INTEGER NULL, -- Tbagr
	ADD COLUMN dead_wood_type INTEGER NULL, -- Tart
	ADD COLUMN decomposition INTEGER NULL, -- Tzg
	ADD COLUMN length_height smallint NULL CHECK (length_height >= 1 AND length_height <= 800), -- Tl [cm]
	ADD COLUMN diameter_butt smallint NOT NULL CHECK (diameter_butt >= 10 AND diameter_butt <= 300), -- Tbd [cm]
	ADD COLUMN diameter_top smallint NULL CHECK (diameter_top >= 0 AND diameter_top <= 300), -- Tsd [cm]
	ADD COLUMN count smallint NULL CHECK (count >= 1 AND count <= 100), -- Anz
	ADD COLUMN bark_pocket BOOLEAN DEFAULT FALSE; -- TRinde

ALTER TABLE deadwood ADD CONSTRAINT FK_Deadwood_Plot FOREIGN KEY (plot_id)
	REFERENCES plot (id)
	ON DELETE CASCADE;
ALTER TABLE deadwood ADD CONSTRAINT FK_Deadwood_LookupTreeSpeciesGroup FOREIGN KEY (tree_species_group)
	REFERENCES lookup.lookup_tree_species_group (code);
ALTER TABLE deadwood ADD CONSTRAINT FK_Deadwood_LookupDeadWoodType FOREIGN KEY (dead_wood_type)
	REFERENCES lookup.lookup_dead_wood_type (code);
ALTER TABLE deadwood ADD CONSTRAINT FK_Deadwood_LookupDecomposition FOREIGN KEY (decomposition)
	REFERENCES lookup.lookup_decomposition (code);


------------------------------------------------- PLOT LOCATION -------------------------------------------------
CREATE TABLE subplots_relative_position (LIKE table_TEMPLATE INCLUDING ALL);
ALTER TABLE subplots_relative_position
	ADD COLUMN plot_id uuid NOT NULL,
	ADD COLUMN plot_coordinates_id uuid NOT NULL,
	ADD COLUMN parent_table text NOT NULL,
	ADD COLUMN azimuth smallint NOT NULL CHECK (azimuth >= 0 AND azimuth <= 399), -- Azimuth (Gon) NEU
    ADD COLUMN distance smallint NOT NULL  DEFAULT 500 CHECK (distance >= 0 AND distance <= 1000), -- Distance (cm) NEU
    ADD COLUMN radius smallint NOT NULL DEFAULT 100 CHECK (radius >= 1 AND radius <= 1000), -- Radius (cm) NEU
    ADD COLUMN has_entities BOOLEAN DEFAULT TRUE,
	ADD COLUMN center_location public.GEOMETRY(Polygon, 4326) NULL;


ALTER TABLE subplots_relative_position ADD CONSTRAINT FK_SubplotRelativePosition_Plot FOREIGN KEY (plot_id)
	REFERENCES plot (id)
	ON DELETE CASCADE;