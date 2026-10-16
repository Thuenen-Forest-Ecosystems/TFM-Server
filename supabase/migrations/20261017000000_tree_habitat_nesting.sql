-- Siehe: https://git-dmz.thuenen.de/datenerfassungci2027/ci2027_datenerfassung/nfi2022/-/work_items/41
-- Weitere Baummerkmale aus älteren Inventuren werden aber nicht in allen Inventuren erhoben,
-- daher nullable ohne Default: NULL = nicht erhoben, false = erhoben und nicht vorhanden.
--   habitat_features: BWI 2012/2017/2022 HabitatBaumMerkmale, BWI 2002/2008 FaulKon
--   nesting_tree:     BWI 2002/2008 Horst
-- Gefüllt durch nfi2022/migration-script (migrate_from_mssql.js).


ALTER TABLE inventory_archive.tree
    ADD COLUMN IF NOT EXISTS habitat_features boolean NULL,
    ADD COLUMN IF NOT EXISTS nesting_tree boolean NULL;

COMMENT ON COLUMN inventory_archive.tree.habitat_features IS 'Biotop - Habitatbaummerkmale vorhanden (BWI 2002/2008: FaulKon, ab 2012: HabitatBaumMerkmale); NULL = nicht erhoben';
COMMENT ON COLUMN inventory_archive.tree.nesting_tree IS 'Biotop - Horstbaum (BWI 2002/2008: Horst); NULL = nicht erhoben';

-- Neue Spalten für PostgREST sichtbar machen (Migrationsskript schreibt über die REST-API)
NOTIFY pgrst, 'reload schema';
