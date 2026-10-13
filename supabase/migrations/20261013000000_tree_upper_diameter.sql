-- Oberer Durchmesser: in der BWI 1987 wurde bei einem Teil der Bäume zusätzlich der Durchmesser
-- in 7 m Höhe gemessen (b1_wzp.M_d7, 166.948 Bäume). Zwei Spalten, damit die Messhöhe als Wert
-- erhalten bleibt; Einheiten wie dbh [mm] und dbh_height [cm].
-- Gefüllt durch nfi2022/migration-script (migrate_from_mssql.js, INTERVAL=1987).

ALTER TABLE inventory_archive.tree
    ADD COLUMN IF NOT EXISTS upper_diameter smallint NULL,
    ADD COLUMN IF NOT EXISTS height_upper_diameter smallint NULL;

COMMENT ON COLUMN inventory_archive.tree.upper_diameter IS 'oberer Durchmesser [mm] (BWI 1987: M_d7)';
COMMENT ON COLUMN inventory_archive.tree.height_upper_diameter IS 'Messhöhe des oberen Durchmessers [cm] (BWI 1987: immer 700)';

-- Neue Spalten für PostgREST sichtbar machen (Migrationsskript schreibt über die REST-API)
NOTIFY pgrst, 'reload schema';
