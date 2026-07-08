UPDATE lookup.lookup_growth_district
SET growth_region = code / 100;
-- https://github.com/Thuenen-Forest-Ecosystems/TFM-Server/issues/5
COMMENT ON TABLE inventory_archive.cluster IS 'Trakt/Cluster-Merkmale';
COMMENT ON TABLE inventory_archive.plot IS 'Traktecken/Plot-Merkmale zu jedem Aufnahmezeitpunkt';
COMMENT ON TABLE inventory_archive.plot_coordinates IS 'Traktecken/Plot-Koordinaten';
COMMENT ON TABLE inventory_archive.plot_support_points IS 'Information über die Lage der Traktecken/Plot-Markierung, falls der Permamarker versetzt in den Boden gebracht wurde (pro Inventurzeitpunkt = interval_name)';
COMMENT ON TABLE inventory_archive.regeneration IS 'Traktecken/Plot-Merkmale zur Verjüngung pro Inventurzeitpunkt';
COMMENT ON TABLE inventory_archive.deadwood IS 'Traktecken/Plot-Merkmale zum Totholz pro Inventurzeitpunkt';
COMMENT ON TABLE inventory_archive.edges IS 'Traktecken/Plot-Merkmale zu Wald- und Bestandesrändern pro Inventurzeitpunkt';
COMMENT ON TABLE inventory_archive.tree IS 'Merkmale der Bäume, erfasst durch die Winkelzählprobe mit Zählfaktor 4 pro Inventurzeitpunkt';
COMMENT ON TABLE inventory_archive.structure_lt4m IS 'Merkmale der Bestockungsaufnahme im 10m-Kreis für Bäume kleiner 4m pro Inventurzeitpunkt';
COMMENT ON TABLE inventory_archive.structure_gt4m IS 'Merkmale der Bestockungsaufnahme der Winkelzählprobe mit Zählfaktor 1 oder 2 für Bäume größer 4m pro Inventurzeitpunkt';