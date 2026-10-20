-- Siehe: https://git-dmz.thuenen.de/datenerfassungci2027/ci2027_datenerfassung/nfi2022/-/work_items/41
-- Merkmale, die nicht in jeder Inventur erhoben wurden (z. B. cave_tree gibt es 1987 nicht), waren
-- NOT NULL DEFAULT false. Nicht erhobene Werte wurden dadurch zu false ("kein Höhlenbaum") statt
-- "nicht erhoben". Daher nullable: NULL = nicht erhoben, false = erhoben und nicht vorhanden
-- (wie habitat_features/nesting_tree in 20261017000000).
--
-- Der Default false bleibt, wo jeder Schreibweg den Wert explizit setzt:
--   - Migrationsskript (supabase-js upsert, defaultToNull): fehlende Keys werden NULL, der Default greift nie
--   - insert_json_rows() (Archiv-Sync, 20261018000000) ersetzt JSON-null durch den Spalten-Default;
--     in records.properties sind alle Baum- und Plotmerkmale gesetzt, außer fence_regeneration
--     (bei ~98 % der Ecken null oder fehlend). Nur dort wird der Default entfernt, sonst würde
--     "nicht angegeben" im Archiv zu "kein Zaun".
--
-- deadwood.diameter_butt: BWI 2002 hat nur den Mittendurchmesser (diameter_center, 20261020000000).
-- Der CHECK 10-300 bleibt bestehen, NULL erfüllt ihn.

ALTER TABLE inventory_archive.tree
    ALTER COLUMN within_stand DROP NOT NULL,
    ALTER COLUMN tree_marked DROP NOT NULL,
    ALTER COLUMN damage_dead DROP NOT NULL,
    ALTER COLUMN cave_tree DROP NOT NULL,
    ALTER COLUMN tree_top_drought DROP NOT NULL,
    ALTER COLUMN crown_dead_wood DROP NOT NULL,
    ALTER COLUMN biotope_marked DROP NOT NULL,
    ALTER COLUMN bark_pocket DROP NOT NULL,
    ALTER COLUMN damage_fungus DROP NOT NULL,
    ALTER COLUMN damage_resin DROP NOT NULL,
    ALTER COLUMN damage_beetle DROP NOT NULL,
    ALTER COLUMN damage_other DROP NOT NULL;

ALTER TABLE inventory_archive.plot
    ALTER COLUMN coast DROP NOT NULL,
    ALTER COLUMN sandy DROP NOT NULL,
    ALTER COLUMN long_time_forest DROP NOT NULL,
    ALTER COLUMN protected_landscape DROP NOT NULL,
    ALTER COLUMN fence_regeneration DROP NOT NULL,
    ALTER COLUMN fence_regeneration DROP DEFAULT,
    ALTER COLUMN harvest_restriction_fragmented DROP NOT NULL,
    ALTER COLUMN harvest_restriction_insufficient_access DROP NOT NULL,
    ALTER COLUMN harvest_restriction_low_yield DROP NOT NULL,
    ALTER COLUMN harvest_restriction_nature_reserve DROP NOT NULL,
    ALTER COLUMN harvest_restriction_other_internalcause DROP NOT NULL,
    ALTER COLUMN harvest_restriction_private_conservation DROP NOT NULL,
    ALTER COLUMN harvest_restriction_protection_forest DROP NOT NULL,
    ALTER COLUMN harvest_restriction_recreational_forest DROP NOT NULL,
    ALTER COLUMN harvest_restriction_scattered DROP NOT NULL,
    ALTER COLUMN harvest_restriction_wetness DROP NOT NULL;

ALTER TABLE inventory_archive.deadwood
    ALTER COLUMN diameter_butt DROP NOT NULL;

NOTIFY pgrst, 'reload schema';
