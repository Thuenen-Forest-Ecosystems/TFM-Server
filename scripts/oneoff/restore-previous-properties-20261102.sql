-- ============================================================================
-- previous_properties auf den Stand vor dem Lauf vom 2026-11-02 zuruecksetzen
-- ============================================================================
-- Der Neuaufbau am 2026-11-02 (20261102100000, Body "nur Plot-Baeume") hat bei
-- 13.613 von 20.371 records die Baeume aelterer Inventuren (ci2017, bwi2012, ...)
-- aus previous_properties->'tree' entfernt. Die Sicherung
-- public.backup_previous_properties_20261102 haelt den Stand davor (Lauf vom
-- 2026-06-23 mit 20260616-Logik).
--
-- Zurueckgesetzt werden NUR previous_properties und
-- previous_properties_updated_at. cluster und previous_position_data bleiben
-- auf dem Stand vom 2026-11-02 (dort keine Baeume betroffen).
--
-- Nebenwirkung: die BHD-Ergaenzung vom 2026-11-02 (Status 4/5/9/12 ohne dbh)
-- geht fuer diese records wieder verloren.
--
-- Keine anderen Spalten: app.skip_updated_at verhindert updated_at (kein
-- PowerSync-Sync); updated_by bleibt, weil auth.uid() als postgres NULL ist;
-- kein record_changes-Eintrag (on_record_updated feuert nicht).
--
-- Vorher sichert das Skript den aktuellen Stand nach
-- public.backup_previous_properties_20261104.
--
-- Aufruf (Prod, VPN):
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f scripts/oneoff/restore-previous-properties-20261102.sql
-- ============================================================================

\set ON_ERROR_STOP 1
\timing on

BEGIN;
SET LOCAL app.skip_updated_at = 'on';

-- Sicherung des aktuellen Stands (bricht ab, falls die Tabelle schon existiert)
CREATE TABLE public.backup_previous_properties_20261104 AS
SELECT r.id, r.previous_properties, r.cluster, r.previous_position_data,
       r.previous_properties_updated_at
FROM public.records r
JOIN public.backup_previous_properties_20261102 b ON b.id = r.id;

REVOKE ALL ON public.backup_previous_properties_20261104 FROM anon, authenticated;

UPDATE public.records r
SET previous_properties = b.previous_properties,
    previous_properties_updated_at = b.previous_properties_updated_at
FROM public.backup_previous_properties_20261102 b
WHERE r.id = b.id
  AND r.previous_properties IS DISTINCT FROM b.previous_properties;

-- Kontrolle: alle records aus der Sicherung tragen wieder deren Stand
SELECT count(*) AS restored,
       count(*) FILTER (WHERE r.previous_properties IS DISTINCT FROM b.previous_properties) AS still_different,
       count(*) FILTER (WHERE r.updated_at > now() - interval '10 minutes') AS updated_at_touched
FROM public.records r
JOIN public.backup_previous_properties_20261102 b ON b.id = r.id;

-- Stichprobe 18597/3: Baeume nach Herkunft (intkey endet auf _<interval>)
SELECT split_part(e->>'intkey', '_', 2) AS interval_name, count(*) AS trees
FROM public.records r,
     jsonb_array_elements(r.previous_properties->'tree') e
WHERE r.cluster_name = 18597 AND r.plot_name = 3
GROUP BY 1 ORDER BY 1;

COMMIT;
