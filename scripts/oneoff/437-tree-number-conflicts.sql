-- Doppelt vergebene Baumnummern (TFM-client-app #437) – Bericht, schreibt nichts.
--
--   psql "$DB_URL" -X -f scripts/oneoff/437-tree-number-conflicts.sql
--   psql "$DB_URL" -X --csv -f scripts/oneoff/437-tree-number-conflicts.sql > 437.csv
--
-- Kandidat ist jeder Baum in properties ohne inventory_archive-UUID in id,
-- dessen tree_number in einer früheren Inventur der Ecke schon vergeben ist. Fehlende UUID
-- heißt nicht immer "in der App neu angelegt": es gibt übernommene Bäume ohne
-- UUID. Entscheidend ist daher die Lage (Azimut/Entfernung):
--
--   0_kein_konflikt       gleiche Position und Art wie der Vorgänger ->
--                         derselbe Baum, nichts zu tun
--   1_umnummerieren       Lage weicht ab, Vorgänger schon ausgefallen
--                         (tree_status >= 1987) oder, ohne Lage, Art/BHD
--                         passen nicht -> anderer Baum,
--                         neue_nummer = Maximum aus properties und allen
--                         früheren Inventuren + 1, in Array-Reihenfolge
--   2_gleicher_baum_pruefen  Lage innerhalb der Toleranz, aber nicht identisch
--                         oder andere Art -> vermutlich derselbe Baum,
--                         fachlich bestätigen
--   3_einzelfall          Lage unbekannt und nichts spricht dagegen, oder die
--                         Nummer ist im Vorgänger mehrfach vergeben
--
-- Zusätzlich, ohne Konflikt im Sinne von #437:
--
--   B_statusaenderung     vorbelegter Baum (mit UUID) lebt (status_lebend),
--                         Vorgänger mit gleicher Nummer ist schon ausgefallen
--                         (tree_status >= 1987)
--
-- Die Schwellen in params sind Vorschläge und mit Thünen abzustimmen.
-- Einheiten laut Schema: azimuth Gon, distance cm, dbh mm.
-- Reines SELECT, ohne BEGIN/ROLLBACK, damit pgAdmin & Co. das Ergebnis zeigen.

WITH params AS (
    SELECT
        150::numeric AS lage_toleranz_cm,      -- Abstand der beiden Stammfußpunkte
        1::numeric   AS lage_identisch_cm,     -- bis hier: übernommene Position
        20::numeric  AS bhd_schwund_mm,        -- BHD darf so viel kleiner sein (Messfehler)
        250::numeric AS bhd_zuwachs_max_mm,    -- mehr Zuwachs gilt als anderer Baum
        ARRAY[0, 1]  AS status_lebend,         -- neuer / wiederholt aufgenommener Probebaum
        '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$'::text AS uuid_re
),
current_trees AS MATERIALIZED (
    SELECT r.id AS record_id, r.cluster_name, r.plot_name,
           t.ord,
           (t.e->>'tree_number')::int  AS tree_number,
           t.e->>'id'                  AS tree_id,
           (t.e->>'tree_status')::int  AS status,
           (t.e->>'tree_species')::int AS art,
           (t.e->>'dbh')::numeric      AS bhd,
           (t.e->>'azimuth')::numeric  AS azimut,
           (t.e->>'distance')::numeric AS entfernung
    FROM public.records r
    CROSS JOIN LATERAL jsonb_array_elements(r.properties->'tree') WITH ORDINALITY AS t(e, ord)
    WHERE jsonb_typeof(r.properties->'tree') = 'array'
),
-- Vorgänger = alle früheren Inventuren im Archiv, nicht nur previous_properties
-- (bwi2022): Bäume, die vor 2022 ausgefallen sind, stehen nur in älteren
-- Intervallen, ihre Nummern sind aber vergeben (18360/3, 18282/2, 18283/3).
-- Je Nummer zählt das jüngste Vorkommen.
previous_trees AS MATERIALIZED (
    SELECT DISTINCT ON (r.id, t.tree_number)
           r.id AS record_id,
           t.tree_number,
           pl.interval_name AS intervall_vorg,
           t.tree_status    AS status,
           t.tree_species   AS art,
           t.dbh::numeric      AS bhd,
           t.azimuth::numeric  AS azimut,
           t.distance::numeric AS entfernung
    FROM public.records r
    JOIN inventory_archive.plot pl
      ON pl.cluster_name = r.cluster_name AND pl.plot_name = r.plot_name
    JOIN lookup.lookup_interval li ON li.code = pl.interval_name
    JOIN inventory_archive.tree t ON t.plot_id = pl.id
    WHERE pl.interval_name <> 'ci2027'          -- laufende Inventur
    ORDER BY r.id, t.tree_number, li.sort DESC
),
-- höchste je vergebene Nummer pro Datensatz
max_nummer AS (
    SELECT record_id, max(tree_number) AS max_nr
    FROM (SELECT record_id, tree_number FROM current_trees
          UNION ALL
          SELECT record_id, tree_number FROM previous_trees) n
    GROUP BY record_id
),
paare AS (
    SELECT ct.*,
           ct.tree_id IS NOT NULL AND ct.tree_id ~* (SELECT uuid_re FROM params) AS ist_archiv,
           ps.intervall_vorg,
           ps.status     AS status_vorg,
           ps.art        AS art_vorg,
           ps.bhd        AS bhd_vorg,
           ps.azimut     AS azimut_vorg,
           ps.entfernung AS entfernung_vorg,
           -- Polarkoordinaten (Gon) -> Abstand der Fußpunkte in cm
           sqrt(power(ct.entfernung * sin(ct.azimut * pi() / 200)
                    - ps.entfernung * sin(ps.azimut * pi() / 200), 2)
              + power(ct.entfernung * cos(ct.azimut * pi() / 200)
                    - ps.entfernung * cos(ps.azimut * pi() / 200), 2)) AS lage_abstand_cm
    FROM current_trees ct
    JOIN previous_trees ps USING (record_id, tree_number)
),
bewertet AS (
    SELECT p.*,
           array_remove(ARRAY[
               CASE WHEN p.status_vorg >= 1987 THEN 'vorgaenger_ausgefallen' END,
               CASE WHEN p.art IS DISTINCT FROM p.art_vorg
                         AND p.art IS NOT NULL AND p.art_vorg IS NOT NULL THEN 'art_abweichend' END,
               CASE WHEN p.lage_abstand_cm > prm.lage_toleranz_cm THEN 'lage_abweichend' END,
               CASE WHEN p.bhd < p.bhd_vorg - prm.bhd_schwund_mm THEN 'bhd_kleiner' END,
               CASE WHEN p.bhd > p.bhd_vorg + prm.bhd_zuwachs_max_mm THEN 'bhd_zuwachs_zu_gross' END
           ], NULL) AS gruende_anderer_baum,
           array_remove(ARRAY[
               CASE WHEN p.status IS NULL THEN 'status_fehlt' END,
               CASE WHEN p.art IS NULL OR p.art_vorg IS NULL THEN 'art_fehlt' END,
               CASE WHEN p.lage_abstand_cm IS NULL THEN 'lage_fehlt' END,
               CASE WHEN p.bhd IS NULL OR p.bhd_vorg IS NULL THEN 'bhd_fehlt' END
           ], NULL) AS fehlende_angaben
    FROM paare p, params prm
),
klassifiziert AS (
    SELECT b.*,
           CASE
               WHEN b.ist_archiv THEN
                   CASE WHEN b.status = ANY (prm.status_lebend) AND b.status_vorg >= 1987
                        THEN 'B_statusaenderung' END
               -- Nummer im Vorgänger mehrfach vergeben: nicht automatisch entscheiden
               WHEN b.treffer_vorg > 1 THEN '3_einzelfall'
               -- Die Lage entscheidet, wenn sie bekannt ist: ein Baum wandert nicht.
               -- Abweichende Art/BHD/Status bei gleicher Lage sind Korrekturen am
               -- selben Baum, kein Nummernkonflikt.
               WHEN b.lage_abstand_cm > prm.lage_toleranz_cm THEN '1_umnummerieren'
               -- schon in einer früheren Inventur ausgefallen: kann nicht neu
               -- aufgenommen werden, auch wenn er nah am Vorgänger steht
               WHEN b.status_vorg >= 1987 THEN '1_umnummerieren'
               WHEN b.lage_abstand_cm <= prm.lage_identisch_cm
                    AND b.art IS NOT DISTINCT FROM b.art_vorg THEN '0_kein_konflikt'
               WHEN b.lage_abstand_cm IS NOT NULL THEN '2_gleicher_baum_pruefen'
               -- Lage unbekannt: andere Merkmale, sonst Einzelfall
               WHEN cardinality(b.gruende_anderer_baum) > 0 THEN '1_umnummerieren'
               ELSE '3_einzelfall'
           END AS klasse
    FROM (SELECT bewertet.*,
                 count(*) OVER (PARTITION BY record_id, ord) AS treffer_vorg
          FROM bewertet) b,
         params prm
),
-- eine Zeile je aktuellem Baum (bei mehreren Vorgängern gleicher Nummer die erste)
je_baum AS (
    SELECT DISTINCT ON (record_id, ord) *
    FROM klassifiziert
    WHERE klasse IS NOT NULL
    ORDER BY record_id, ord, lage_abstand_cm NULLS LAST
)
SELECT k.klasse,
       count(*) OVER (PARTITION BY k.klasse) AS anzahl_klasse,
       k.cluster_name, k.plot_name, k.record_id,
       k.ord AS array_position,
       k.tree_number,
       CASE WHEN k.klasse = '1_umnummerieren'
            THEN m.max_nr + row_number() OVER (
                     PARTITION BY k.record_id, k.klasse = '1_umnummerieren'
                     ORDER BY k.ord)
       END AS neue_nummer,
       CASE WHEN k.treffer_vorg > 1 THEN 'mehrere_vorgaenger_mit_nummer' END AS hinweis,
       array_to_string(k.gruende_anderer_baum, ', ') AS gruende,
       array_to_string(k.fehlende_angaben, ', ')     AS fehlend,
       k.intervall_vorg,
       k.status AS status_neu, k.status_vorg,
       k.art    AS art_neu,    k.art_vorg,
       k.bhd    AS bhd_neu,    k.bhd_vorg,
       round(k.lage_abstand_cm) AS lage_abstand_cm,
       k.tree_id
FROM je_baum k
JOIN max_nummer m USING (record_id)
ORDER BY k.klasse, k.cluster_name, k.plot_name, k.tree_number, k.ord;
