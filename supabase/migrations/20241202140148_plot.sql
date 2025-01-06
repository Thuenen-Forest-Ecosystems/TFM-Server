SET search_path TO private_ci2027_001, public;
CREATE TABLE IF NOT EXISTS plot (

	intkey varchar(12) UNIQUE NULL,

    id uuid UNIQUE DEFAULT gen_random_uuid() PRIMARY KEY,
	
    cluster_id INTEGER NOT NULL,
	plot_name CK_PLOT_NAME NOT NULL, -- Unique human readable name

	created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
	modified_at TIMESTAMP DEFAULT NULL,
	modified_by uuid DEFAULT auth.uid() NOT NULL,

	interval_name enum_interval_name NOT NULL DEFAULT 'ci2027', -- Intervall

	sampling_stratum INTEGER NOT NULL, -- ToDo: create enum_sampling_stratum + Lookup from bwineu.Vbl 
	federal_state enum_state NOT NULL,

	center_location GEOMETRY(Point, 4326), -- geom NEU

	--state_responsible enum_state NOT NULL, -- AufnBl

	growth_district integer  NULL, -- wb

	forest_status enum_forest_status NULL, -- wa
	accessibility smallint NULL, -- begehbar TODO: Lookup Table
	
	-- ags varchar(8)  NULL, -- ags Wird das noch gebraucht?  (Amtlicher Gemeindeschlüssel (8-stellig, Pos 1+2=Bl, 3=RegBez, 4-5=Kreis, 6-7=Gemeinde), aus Karte 1:250.000 (31.12.2008)) Alternative: reverse lookup ??
	-- kreis smallint NULL, -- kreis Ist das für Trupps eine relevante Information? (Land-/Stadtkreis) Alternative: reverse lookup ??
	-- gemeinde int NULL, -- gemeinde Ist das für Trupps eine relevante Information? (Gemeinde) Alternative: reverse lookup ??


	---- MAY BE REPLACED BY SEPERATE GEO-TABLES created from shape files
    -- biogeogrregion smallint NULL, -- biogeogrregion Ist das für Trupps eine relevante/änderbare Information? (atlantisch, kontinental, alpin)
	-- ffh smallint NULL, -- ffh Ist das für Trupps eine relevante/änderbare Information und aktuell? (z.B. DE2735301 | Alte Elde zwischen Wanzlitz und Krohn)
	-- vogelsg smallint NULL, -- vogelsg (vgl. ffh)
	-- nationalp smallint NULL, -- nationalp (vgl. ffh)
    -- naturp smallint NULL, -- naturp (vgl. ffh)
	-- biosphaere smallint NULL, -- biosphaere (vgl. ffh)
	-- natursg smallint NULL, -- natursg (vgl. ffh)

	forest_office smallint NULL, -- fa
	elevation_level enum_elevation_level NULL, -- nathoe
	property_type enum_property_type NULL, -- eg
	property_size_class enum_property_size_class NULL, -- eggrkl

	forest_community enum_forest_community_field NULL, -- natwgv
	forest_community_field enum_forest_community_field NULL, -- natwg
	ffh_forest_type enum_ffh_forest_type_field NULL, -- wlt_v
	ffh_forest_type_field enum_ffh_forest_type_field NULL, --wlt

	
	
	land_use_before enum_land_use NULL, -- lanu
	land_use_after enum_land_use NULL, -- lanu

	-- ez1 smallint NULL, -- ez1 --Wird in Rücksprache mit TS anders erfasst (TODO)
    -- ez2 smallint NULL, -- ez2
	-- ez3 smallint NULL, -- ez3
	-- ez4 smallint NULL, -- ez4

	-- exploration_instruction smallint NULL, -- st_methode ?? finde ich nicht in z3_col
	-- st_quelle smallint NULL, -- st_quelle Länderspezifisch: finde ich nur in x3_bl
	-- st_b smallint NULL, --st_b Länderspezifisch: finde ich nur in x3_bl
	-- st_ks_hs smallint NULL, --st_ks_hs Länderspezifisch: finde ich nur in x3_bl
	-- st_ks_fs smallint NULL, --st_ks_fs Länderspezifisch: finde ich nur in x3_bl
	-- st_n smallint NULL, -- st_n Länderspezifisch: finde ich nur in x3_bl
	-- st_nz smallint NULL, --st_nz Länderspezifisch: finde ich nur in x3_bl
	-- st_wh_fg smallint NULL, --st_wh_fg Länderspezifisch: finde ich nur in x3_bl
	-- st_wh_fz smallint NULL, --st_wh_fz Länderspezifisch: finde ich nur in x3_bl
	-- st_wh_e smallint NULL, --st_wh_e Länderspezifisch: finde ich nur in x3_bl
	-- st_var varchar(18)  NULL, -- st_var Länderspezifisch: finde ich nur in x3_bl

	coast BOOLEAN NULL DEFAULT FALSE, --kueste
	sandy BOOLEAN NULL DEFAULT FALSE, -- gestein
	protected_landscape BOOLEAN NULL DEFAULT FALSE, -- lsg
	histwald BOOLEAN NULL DEFAULT FALSE, -- histwald

	harvest_restriction INTEGER NULL, -- ne TODO: Lookup Table & enum
	harvest_restriction_source INTEGER[] DEFAULT '{}', -- NEU: create enum_harvest_restriction_source Nutzungseinschränkungen als Array TODO: Lookup Table, inner- und außerbetrieblich zusammenführen

    -- wfkt1 smallint NOT NULL, -- wfkt1  --Wird in Rücksprache mit TS anders erfasst (TODO)
	-- wfkt2 smallint NULL, -- wfkt2
	-- wfkt3 smallint NULL, -- wfkt3
	-- wfkt4 smallint NULL, -- wfkt4
	-- wfkt5 smallint NULL, -- wfkt5
	-- wfkt6 smallint NULL, -- wfkt6
	-- wfkt7 smallint NULL, -- wfkt7
	-- wfkt8 smallint NULL, -- wfkt8
	-- wfkt9 smallint NULL, -- wfkt9

	landmark_azimuth CK_GON NULL, -- mark_azi
	landmark_distance smallint NULL, -- mark_hori
	landmark_note varchar(12)  NULL, -- mark_beschreibung

	marker_status enum_marker_status NULL, -- perm: Das Feld bietet kein Mehrwert, da perm_profile die gleiche Information enthält
	marker_azimuth CK_GON NULL, -- perm_azi: 
	marker_distance smallint NULL, -- perm_hori
	marker_profile enum_marker_profile NULL, -- perm_profil -- TODO: enum_marker_profile + Lookup

	terrain_form enum_terrain_form NULL, -- gform
	terrain_slope CK_SLOPE_DEGREE NULL, -- gneig [Grad]
	terrain_exposure CK_GON NULL, -- gexp [Gon]

	management_type enum_management_type NULL, -- be
	harvesting_method enum_harvesting_method NULL, -- ernte (x3_ernte)
	biotope CK_BIOTOPE NULL, -- biotop (x3_biotop)
	stand_structure enum_stand_structure NULL, -- ab
	stand_age CK_STAND_AGE NULL, -- al_best
	stand_dev_phase enum_stand_dev_phase NULL, -- phase

	stand_layer_reg enum_stand_layer NULL, -- b0_bs
	fence_reg BOOLEAN NULL DEFAULT FALSE, -- b0_zaun

	trees_greater_4meter_mirrored enum_trees_less_4meter_mirrored NULL, -- schigt4_sp (gespiegelt)
	trees_greater_4meter_basal_area_factor enum_trees_less_4meter_count_factor NULL, -- schigt4_zf
	trees_less_4meter_coverage smallint NULL, -- schile4_bedg
	trees_less_4meter_layer enum_trees_less_4meter_layer NULL -- schile4_schi

	-- ez5 smallint NULL, -- ez5
	-- ez6 smallint NULL, -- ez6
	-- ez7 smallint NULL, -- ez7
	-- ez8 smallint NULL, -- ez8
	-- ez9 smallint NULL -- ez9
);
COMMENT ON TABLE plot IS 'Tabelle für die Erfassung von Ecken';
COMMENT ON COLUMN plot.forest_community IS 'Natürliche Waldgesellschaft.';
COMMENT ON COLUMN plot.forest_community_field IS 'Natürliche Waldgesellschaft im Bestand definiert.';
ALTER TABLE plot ADD CONSTRAINT FK_Plot_Cluster_Unique UNIQUE (cluster_id, plot_name);
ALTER TABLE plot ADD CONSTRAINT FK_Plot_Cluster FOREIGN KEY (cluster_id)
	REFERENCES cluster (cluster_name) MATCH SIMPLE
	ON DELETE CASCADE;
--ALTER TABLE plot ADD CONSTRAINT FK_Plot_SamplingStratum FOREIGN KEY (sampling_stratum) -- TODO
--	REFERENCES lookup_sampling_stratum (abbreviation) MATCH SIMPLE
--	ON UPDATE NO ACTION
--	ON DELETE NO ACTION;

ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupGrowthDistrict FOREIGN KEY (growth_district)
        REFERENCES lookup_growth_district (abbreviation) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupForestStatus FOREIGN KEY (forest_status)
		REFERENCES lookup_forest_status (abbreviation) MATCH SIMPLE
		ON UPDATE NO ACTION
		ON DELETE NO ACTION;
--ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupForestrOffice FOREIGN KEY (forestry_office) --TODO
--		REFERENCES lookup_forestry_office (abbreviation) MATCH SIMPLE
--		ON UPDATE NO ACTION
--		ON DELETE NO ACTION;

ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupElevationLevel FOREIGN KEY (elevation_level) 
	REFERENCES lookup_elevation_level (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupPropertyType FOREIGN KEY (property_type)
	REFERENCES lookup_property_type (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupPropertySizeClass FOREIGN KEY (property_size_class)
	REFERENCES lookup_property_size_class (abbreviation) MATCH SIMPLE
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
	REFERENCES lookup_land_use (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
--ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupHarvestRestrictionSource FOREIGN KEY (harvest_restriction_source)
--	REFERENCES lookup_use_restriction_source (abbreviation) MATCH SIMPLE
--	ON UPDATE NO ACTION
--	ON DELETE NO ACTION;

ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupMarkerStatus FOREIGN KEY (marker_status)
	REFERENCES lookup_marker_status (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupMarkerProfile FOREIGN KEY (marker_profile)
	REFERENCES lookup_marker_profile (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupTerrainForm FOREIGN KEY (terrain_form)
	REFERENCES lookup_terrain_form (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupManagementType FOREIGN KEY (management_type)
	REFERENCES lookup_management_type (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupHarvestingMethod FOREIGN KEY (harvesting_method)
	REFERENCES lookup_harvesting_method (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
--ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupBiotope FOREIGN KEY (biotope)
--	REFERENCES lookup_biotope (abbreviation) MATCH SIMPLE
--	ON UPDATE NO ACTION
--	ON DELETE NO ACTION;

ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupStandStructure FOREIGN KEY (stand_structure)
	REFERENCES lookup_stand_structure (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupStandDevPhase FOREIGN KEY (stand_dev_phase)
	REFERENCES lookup_stand_dev_phase (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupStandLayer FOREIGN KEY (stand_layer_reg)
	REFERENCES lookup_stand_layer (abbreviation) MATCH SIMPLE
	ON UPDATE NO ACTION
	ON DELETE NO ACTION;
ALTER TABLE plot ADD CONSTRAINT FK_Plot_LookupTreesLess4meterMirrored FOREIGN KEY (trees_greater_4meter_mirrored)
	REFERENCES lookup_trees_less_4meter_mirrored (abbreviation) MATCH SIMPLE
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
