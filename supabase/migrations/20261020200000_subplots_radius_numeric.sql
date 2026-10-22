-- Radius der Verjüngungskreise mit Nachkommastellen: in BWI 2002 und CI 2008 gibt es neben dem
-- 1-m-Kreis einen zweiten Kreis am Eckenzentrum mit 1,75 m Radius. smallint kann das nicht speichern.
-- numeric(6,2) hält alle bisherigen Werte (1, 2, 4) unverändert; der Check 1..1000 bleibt.
-- Gefüllt durch nfi2022/migration-script (migrate_from_mssql.js, INTERVAL=2002/2008).
--
-- Vor dem Push auf Prod: abhängige Views über pg_depend prüfen (prod-only Views fehlen lokal).

ALTER TABLE inventory_archive.subplots_relative_position
    ALTER COLUMN radius TYPE numeric(6,2);

COMMENT ON COLUMN inventory_archive.subplots_relative_position.radius IS 'Radius [m] des Probekreises für Bäume der Baumgröße 0 {1, 1,75, 2 oder 4 m}';

NOTIFY pgrst, 'reload schema';
