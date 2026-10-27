-- Fehlende inventory_archive.edges_coordinates nachberechnen.
-- update_edges_coordinates (AFTER INSERT OR UPDATE ON edges) braucht position.position_mean als
-- Startpunkt; ist die position beim Edge-Insert noch nicht committet, entsteht keine Zeile. Der
-- Upload (nfi2022/migration-script, uploadSupabaseBatch) schrieb edges und position parallel:
-- 2026-10-27 fehlten so 24963 Kanten bwi2022 (lokal + Production) und 1516 ci2008 (Production).
-- Gleiche Berechnung wie der Trigger; bestehende Zeilen bleiben unverändert, mehrfach ausführbar.

INSERT INTO inventory_archive.edges_coordinates (edge_id, geometry_edges)
SELECT e.id, extensions.create_linestring_from_edges(e.edges, po.position_mean)
FROM inventory_archive.edges e
JOIN inventory_archive.position po ON po.plot_id = e.plot_id
WHERE po.position_mean IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM inventory_archive.edges_coordinates ec WHERE ec.edge_id = e.id)
ON CONFLICT (edge_id) DO NOTHING;
