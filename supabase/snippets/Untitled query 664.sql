--Befehle zum Anpassen den intervals in den Lookup-Tabellen
--lookup_accessibility
--i.O.
--lookup_bark_condition
update lookup.lookup_bark_condition
set interval = ARRAY ['bwi2022','ci2027']
where code in (1, 2, 3, 4);
--lookup_basal_area_factor
update lookup.lookup_basal_area_factor
set interval = ARRAY ['bwi2002','bwi2012','bwi2022','ci2027']
where code in (1, 2);
--lookup_biogeographische_region
update lookup.lookup_biogeographische_region
set interval = ARRAY ['bwi2012','ci2017', 'bwi2022','ci2027'];
--lookup-biosphaere
--i.O.
--lookup_biotope
--i.O.
--lookup_browsing
--passt!
--lookup_cluster_situation
update lookup.lookup_cluster_situation
set interval = ARRAY ['bwi2002','bwi2012','ci2017','bwi2022','ci2027']
where code in (1, 2, 3, 4, 5, 6, 7, 8, 10);
--lookup_cluster_status
update lookup.lookup_cluster_status
set interval = ARRAY ['bwi2002','bwi2012','ci2017','bwi2022','ci2027']
where code in (1, 2, 3, 4, 5, 6);
--lookup_damage_peel
update lookup.lookup_damage_peel
set interval = ARRAY ['bwi2012','bwi2022','ci2027']
where code in (0, 1, 2);
--lookup_dead_wood_type
--i.O.
--lookup_decomposition
update lookup.lookup_decomposition
set interval = ARRAY ['bwi202','bwi2012','ci2017','bwi2022','ci2027']
where code in (1, 2, 3, 4);
--lookup_district
--i.O.
--lookup_edge_stand_difference
update lookup.lookup_edge_stand_difference
set interval = ARRAY ['ci2027']
where code in (1, 2, 3, 4, 9);
--lookup_edge_status
--wird nicht gebraucht, alt, gilt bis BWI 2022
--lookup_edge_type
--i.O.
--lookup_edge_type_deprecated
update lookup.lookup_edge_type_deprecated
set interval = ARRAY ['bwi2002','bwi2012','bwi2022']
where code in (1, 2, 3, 4);
--lookup_elevation_level
update lookup.lookup_elevation_level
set interval = ARRAY ['bwi2002','bwi2012','ci2017','bwi2022','ci2027']
where code in (1, 2, 3, 4, 5);
--lookup_exploration_instruction
update lookup.lookup_exploration_instruction
set interval = ARRAY ['bwi2012','bwi2022']
where code in (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 99);
--lookup_ffh
--diskutieren?
-- ist aktuell, Stand von 2022
--lookup_ffh_forest_type
--i.O.
--lookup_forest_community
--i.O.
--lookup_forest_office
--i.O.
--lookup_forest_status
update lookup.lookup_forest_status
set interval = ARRAY ['bwi2002','bwi2012','bwi2022','ci2027']
where code in (6, 7);
update lookup.lookup_forest_status
set interval = ARRAY ['ci2017']
where code in (23, 24, 25);
update lookup.lookup_forest_status
set interval = ARRAY ['bwi2022','ci2027']
where code in (73, 74, 75);
--lookup_foresty_office
--Dopplung zu lookup_forest_office?
--wird gelöscht!
--lookup_gnss_quality
--i.O.
--lookup_grid_density
update lookup.lookup_grid_density
set interval = ARRAY ['bwi1987','bwi2002','bwi2012', 'ci2017', 'bwi2022','ci2027']
where code in (0, 1, 2, 4, 8, 16, 32, 64, 256);
--lookup_growth_district
update lookup.lookup_growth_district
set interval = ARRAY ['bwi2002','bwi2012', 'ci2017', 'bwi2022','ci2027']
where mod(code, 100) <> 99;
--lookup_growth_region
update lookup.lookup_growth_region
set interval = ARRAY ['bwi2002','bwi2012','ci2017','bwi2022','ci2027']
where code <> 99;
--lookup_harvest_condition
update lookup.lookup_harvest_condition
set interval = ARRAY ['bwi2012','bwi2022','ci2027']
where code in (0, 1, 2, 3, 4);
--lookup_harvest_method
--i.O.
--lookup_harvest_reason
--i.O.
--lookup_interval
--i.O.
--lookup_land_use
--i.O.
--lookup_layer
update lookup.lookup_layer
set interval = ARRAY ['bwi2002','bwi2012','bwi2022','ci2027']
where code in (1, 2, 3, 9);
--lookup_management_type
update lookup.lookup_management_type
set interval = ARRAY ['bwi1987','bwi2002','bwi2012','bwi2022','ci2027']
where code in (1, 2, 3, 4);
--lookup_marker_profile
update lookup.lookup_marker_profile
set interval = ARRAY ['bwi2012','ci2017','bwi2022','ci2027'];
--lookup_marker_status
update lookup.lookup_marker_status
set interval = ARRAY ['bwi2002','bwi2012','ci2017','bwi2022','ci2027']
where code in (0, 1, 2, 3, 4);
--lookup_municipality
--muss Gerrit bei der Übernahme anpassen! Sein Skript greift bisher nicht.
--lookup_national_park
--i.O
--lookup_natur_park
--i.O.
--lookup_natur_schutzgebiet
update lookup.lookup_natur_schutzgebiet
set interval = ARRAY ['bwi2012','bwi2022','ci2027']
where code in (0, 1);
--lookup_property_size_class
--i.O.
--lookup_property_type
--i.O.
--lookup_pruning
update lookup.lookup_pruning
set interval = ARRAY ['bwi2002','bwi2012','bwi2022']
where code in (0, 1, 2);
update lookup.lookup_pruning
set interval = ARRAY ['bwi2012','bwi2022']
where code in (3, 4, 5, 6);
--lookup_sampling_stratum
-- müssen wir jetzt erstmal so lassen
-- braucht größere Umbauarbeiten, die auch plot.sampling_stratum betreffen
-- sampling_stratum für jede Inventur korrekt eintragen, so dass Veränderungen in der Verdichtung
-- auch in den Daten abgebildet werden (bspw. Thüringen hatte in 2002 8km2- und 16km2-Netz, ab 2012 nur noch 8km2,
-- in plot.sampling_stratum sollte dann ab 2012 nur noch 1608 auftauchen)
-- die bayrischen CI-Plots 2027 sollten
update lookup.lookup_sampling_stratum
set interval = ARRAY ['bwi2002','bwi2012','ci2017','bwi2022','ci2027']
where code > 1100;
update lookup.lookup_sampling_stratum
set interval = ARRAY ['bwi1987', 'bwi2002','ci2017','bwi2012','bwi2022','ci2027']
where code < 1100;
--lookup_stand_development_phase
update lookup.lookup_stand_development_phase
set interval = ARRAY ['bwi2012','bwi2022']
where code in (1, 2, 3, 4, 5);
--lookup_stand_layer
update lookup.lookup_stand_layer
set interval = ARRAY ['bwi1987','bwi2002','bwi2012','ci2017','bwi2022','ci2027']
where code in (0, 1, 2, 3, 4, 9);
--lookup_stand_structure
--Einträge kommen nicht aus  [bwi].[xyk].[x_BestockAb]! Überarbeiten!
update lookup.lookup_stand_structure
set name_de = 'zweischichtig',
    name_en = 'two-layered'
where code = 2;
update lookup.lookup_stand_structure
set interval = ARRAY ['bwi2002','bwi2012','bwi2022','ci2027']
where code in (1, 2, 6);
--lookup_state
update lookup.lookup_state
set interval = ARRAY ['bwi1987','bwi2002','bwi2012','ci2017','bwi2022','ci2027']
where code in (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10);
update lookup.lookup_state
set interval = ARRAY ['bwi2002','bwi2012','ci2017','bwi2022','ci2027']
where code in (11, 12, 13, 14, 15, 16);
--lookup_stem_breakage
update lookup.lookup_stem_breakage
set interval = ARRAY ['bwi1987','bwi2002','bwi2012','ci2017','bwi2022','ci2027']
where code in (0, 1, 2);
--lookup_stem_form
update lookup.lookup_stem_form
set interval = ARRAY ['bwi1987','bwi2002','bwi2012','ci2017','bwi2022','ci2027']
where code in (0, 1, 2, 3);
--lookup_support_point_type
--i.O.
--lookup_template
--i.O.
--lookup_terrain
update lookup.lookup_terrain
set interval = ARRAY ['bwi2002','bwi2012','bwi2022']
where code in (1, 2, 3, 4, 5, 6, 7, 8, 9, 10);
update lookup.lookup_terrain
set interval = ARRAY ['bwi2012','bwi2022']
where code in (0, 11, 12, 13, 14);
--lookup_terrain_form
update lookup.lookup_terrain_form
set interval = ARRAY ['bwi2002','bwi2012','bwi2022','ci2027']
where code in (1, 2, 3, 4, 21, 22, 31, 32, 33);
--lookup_tree_size_class
update lookup.lookup_tree_size_class
set interval = ARRAY ['bwi2002','bwi2012','ci2017','bwi2022','ci2027']
where code in (0, 1, 2, 5, 6, 9);
--lookup_tree_species
update lookup.lookup_tree_species
set interval = ARRAY ['bwi1987','bwi2002']
where code in (950, 951);
--lookup_tree_species_group
--i.O.
--lookup_tree_status
update lookup.lookup_tree_status
set interval = ARRAY ['bwi2002','bwi2012','ci2017','bwi2022','ci2027']
where code in (0, 1, 4, 5, 6, 8, 9, 10, 11, 12, 1111);
--lookup_trees_less_4meter_layer
--ist doppelt zu lookup_layer! Ist in Issue verpackt.#168
--lookup_trees_less_4meter_mirrored
--Inhalt okay, falsch benannt!!!
--lookup_trees_less_4meter_origin
update lookup.lookup_trees_less_4meter_origin
set interval = ARRAY ['bwi2002','bwi2012','bwi2022','ci2027']
where code in (1, 2, 3, 4, 5);
--lookup_vogel_schutzgebiet
--i.O. Notwendigkeit von 'interval' diskutieren
update lookup.lookup_tree_size_class
set interval = ARRAY ['bwi2002','bwi2012','ci2017','bwi2022','ci2027']
where code in (0, 1, 2, 5, 6);
update lookup.lookup_tree_size_class
set interval = ARRAY ['bwi2002']
where code in (9);