-- Baumnummern-Historie einer Traktecke über alle Inventuren (TFM-client-app #437).
-- Zeigt, ob eine Nummer in einer späteren Inventur an einen anderen Baum
-- vergeben wurde. Reines SELECT, schreibt nichts. Ecke in params eintragen.
--
-- Eine Zeile je Baumnummer und Inventur, verglichen mit dem jüngsten früheren
-- Vorkommen derselben Nummer:
--   abstand_cm   Abstand der Stammfußpunkte (aus Azimut in Gon und
--                Horizontalentfernung in cm)
--   befund       WIEDERVERWENDET  Status 0 (neuer Probebaum) auf einer schon
--                                 vergebenen Nummer, > 1,5 m vom früheren Baum
--                LAGE_ABWEICHEND  kein Status 0, aber > 1,5 m entfernt
--                ok               <= 1,5 m, derselbe Baum
--                (leer)           erstes Vorkommen der Nummer
-- Beispiel mit vielen Befunden: 39008/2 (bwi2022 gegenüber bwi2012).

WITH params AS (
    SELECT 39008 AS cluster_name, 2 AS plot_name, 150::numeric AS lage_toleranz_cm
),
t AS (
    SELECT pl.interval_name, li.sort,
           tr.tree_number,
           tr.tree_status  AS status,
           st.name_de      AS status_text,
           tr.tree_species AS art,
           tr.dbh, tr.azimuth, tr.distance
    FROM params p
    JOIN inventory_archive.plot pl
      ON pl.cluster_name = p.cluster_name AND pl.plot_name = p.plot_name
    JOIN lookup.lookup_interval li ON li.code = pl.interval_name
    JOIN inventory_archive.tree tr ON tr.plot_id = pl.id
    LEFT JOIN lookup.lookup_tree_status st ON st.code = tr.tree_status
),
mit_vorg AS (
    SELECT t.*,
           lag(interval_name) OVER w AS int_vorg,
           lag(art)           OVER w AS art_vorg,
           lag(dbh)           OVER w AS bhd_vorg,
           lag(azimuth)       OVER w AS az_vorg,
           lag(distance)      OVER w AS dist_vorg
    FROM t
    WINDOW w AS (PARTITION BY tree_number ORDER BY sort)
),
bewertet AS (
    SELECT m.*,
           round(sqrt(
               power(distance * sin(azimuth * pi() / 200) - dist_vorg * sin(az_vorg * pi() / 200), 2)
             + power(distance * cos(azimuth * pi() / 200) - dist_vorg * cos(az_vorg * pi() / 200), 2)
           )::numeric) AS abstand_cm
    FROM mit_vorg m
)
SELECT b.tree_number AS nr,
       b.interval_name AS inventur,
       b.status, b.status_text,
       b.art, b.dbh AS bhd_mm, b.azimuth AS azimut_gon, b.distance AS entfernung_cm,
       b.int_vorg AS vorher_in,
       b.art_vorg, b.bhd_vorg,
       b.abstand_cm,
       CASE
           WHEN b.int_vorg IS NULL THEN NULL
           WHEN b.abstand_cm > p.lage_toleranz_cm AND b.status = 0 THEN 'WIEDERVERWENDET'
           WHEN b.abstand_cm > p.lage_toleranz_cm THEN 'LAGE_ABWEICHEND'
           WHEN b.abstand_cm IS NOT NULL THEN 'ok'
       END AS befund
FROM bewertet b, params p
ORDER BY b.tree_number, b.sort;
