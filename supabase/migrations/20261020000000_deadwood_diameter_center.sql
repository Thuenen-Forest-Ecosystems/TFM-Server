-- Mittendurchmesser Totholz: in der BWI 2002 wurde beim Totholz (b2_tot_ge20cm) weder der Durchmesser
-- am dicken Ende (diameter_butt) noch am dünnen Ende (diameter_top) erfasst, sondern nur der mittlere
-- Durchmesser. Eigene Spalte, damit der Wert nicht als diameter_butt missverstanden wird;
-- Einheit wie diameter_butt [cm].
-- Gefüllt durch nfi2022/migration-script (migrate_from_mssql.js, INTERVAL=2002).

ALTER TABLE inventory_archive.deadwood
    ADD COLUMN IF NOT EXISTS diameter_center smallint NULL;

COMMENT ON COLUMN inventory_archive.deadwood.diameter_center IS 'mittlerer Durchmesser [cm] (BWI 2002: nur Mittendurchmesser erfasst)';

-- Neue Spalte für PostgREST sichtbar machen (Migrationsskript schreibt über die REST-API)
NOTIFY pgrst, 'reload schema';
