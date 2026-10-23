-- Code der Inventurstudie 2008 korrigieren: 20241202134805_lookup.sql hat sie als 'ci2000' angelegt
-- (Name war schon 'CI 2008'). Bisher verweist nichts auf 'ci2000' (plot, interval_release).
-- Gefüllt durch nfi2022/migration-script (migrate_from_mssql.js, INTERVAL=2008 → ci2008).

UPDATE lookup.lookup_interval
SET code = 'ci2008'
WHERE code = 'ci2000'
    AND NOT EXISTS (SELECT 1 FROM lookup.lookup_interval WHERE code = 'ci2008');
