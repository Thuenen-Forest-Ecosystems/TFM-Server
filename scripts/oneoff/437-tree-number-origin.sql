-- Herkunft doppelt vergebener Baumnummern (TFM-client-app #437).
-- Zeigt je Ecke den Verlauf von properties->'tree' über record_changes
-- (speichert den alten Stand, siehe handle_record_changes) plus den aktuellen
-- Stand in records, dazu die Nummernlage im Archiv. Reines SELECT.
--
-- Spalten:
--   stand                 Zeitpunkt des Standes (record_changes.created_at bzw.
--                         'aktuell' = records)
--   nr_vorbelegt          Nummern mit inventory_archive-UUID (vom Server)
--   nr_ohne_uuid          Nummern ohne UUID (in der App angelegt oder ohne id übernommen)
--   prev_nr               Nummern in previous_properties->'tree'
--   archiv_max            höchste Nummer der Ecke über alle früheren Inventuren
--   bwi2022_nr            Nummern der Ecke in bwi2022 (Quelle der Vorbelegung)
--   bearbeiter, trupp     updated_by / responsible_troop des Standes

WITH params AS (
    SELECT * FROM (VALUES (16873, 2), (18282, 2), (18283, 3), (18360, 3), (18506, 2))
        AS v(cluster_name, plot_name)
),
staende AS (
    SELECT rc.cluster_name, rc.plot_name, rc.created_at AS stand_zeit,
           to_char(rc.created_at, 'YYYY-MM-DD HH24:MI') AS stand,
           rc.properties, rc.previous_properties, rc.updated_by, rc.responsible_troop,
           rc.schema_name
    FROM public.record_changes rc
    JOIN params p USING (cluster_name, plot_name)
    UNION ALL
    SELECT r.cluster_name, r.plot_name, 'infinity'::timestamptz, 'aktuell',
           r.properties, r.previous_properties, r.updated_by, r.responsible_troop,
           r.schema_name
    FROM public.records r
    JOIN params p USING (cluster_name, plot_name)
),
archiv AS (
    SELECT pl.cluster_name, pl.plot_name,
           max(tr.tree_number) FILTER (WHERE pl.interval_name <> 'ci2027') AS archiv_max,
           string_agg(tr.tree_number::text, ',' ORDER BY tr.tree_number)
               FILTER (WHERE pl.interval_name = 'bwi2022') AS bwi2022_nr,
           string_agg(DISTINCT pl.interval_name || ':' || tr.tree_number, ' ')
               FILTER (WHERE pl.interval_name <> 'ci2027') AS alle_nr
    FROM inventory_archive.plot pl
    JOIN params p ON p.cluster_name = pl.cluster_name AND p.plot_name = pl.plot_name
    JOIN inventory_archive.tree tr ON tr.plot_id = pl.id
    GROUP BY 1, 2
),
je_stand AS (
    SELECT s.cluster_name, s.plot_name, s.stand_zeit, s.stand, s.schema_name,
           s.updated_by, s.responsible_troop,
           (SELECT string_agg(e->>'tree_number', ',' ORDER BY (e->>'tree_number')::int)
              FROM jsonb_array_elements(CASE WHEN jsonb_typeof(s.properties->'tree') = 'array'
                                             THEN s.properties->'tree' END) e
             WHERE coalesce(e->>'id', '') ~* '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$') AS nr_vorbelegt,
           (SELECT string_agg(e->>'tree_number', ',' ORDER BY (e->>'tree_number')::int)
              FROM jsonb_array_elements(CASE WHEN jsonb_typeof(s.properties->'tree') = 'array'
                                             THEN s.properties->'tree' END) e
             WHERE coalesce(e->>'id', '') !~* '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$') AS nr_ohne_uuid,
           (SELECT string_agg(e->>'tree_number', ',' ORDER BY (e->>'tree_number')::int)
              FROM jsonb_array_elements(CASE WHEN jsonb_typeof(s.previous_properties->'tree') = 'array'
                                             THEN s.previous_properties->'tree' END) e) AS prev_nr
    FROM staende s
)
SELECT j.cluster_name, j.plot_name, j.stand, j.schema_name,
       j.nr_vorbelegt, j.nr_ohne_uuid, j.prev_nr,
       a.archiv_max, a.bwi2022_nr,
       u.email AS bearbeiter, tp.name AS trupp,
       -- hat sich der Baumbestand gegenüber dem vorigen Stand geändert?
       (j.nr_vorbelegt, j.nr_ohne_uuid, j.prev_nr) IS DISTINCT FROM
         lag((j.nr_vorbelegt, j.nr_ohne_uuid, j.prev_nr))
           OVER (PARTITION BY j.cluster_name, j.plot_name ORDER BY j.stand_zeit) AS geaendert
FROM je_stand j
LEFT JOIN archiv a USING (cluster_name, plot_name)
LEFT JOIN auth.users u ON u.id = j.updated_by
LEFT JOIN public.troop tp ON tp.id = j.responsible_troop
ORDER BY j.cluster_name, j.plot_name, j.stand_zeit;
