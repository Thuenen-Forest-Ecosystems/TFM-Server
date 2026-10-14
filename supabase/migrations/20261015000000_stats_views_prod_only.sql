-- ============================================================================
-- MIGRATION: Statistik-Views, die bisher nur in der Produktions-DB existierten
-- ============================================================================
-- Fuenf v_stats_*-Views waren direkt auf Prod angelegt worden und fehlten in
-- der Versionskontrolle (die uebrigen zwoelf stehen in 20260702000000). Folge:
-- lokale und neue Datenbanken hatten sie nicht, und 20261014000000 scheiterte
-- beim ersten Push am DROP COLUMN plot_coordinates.plot_id, weil zwei davon
-- an der Spalte hingen.
--
-- Die Definitionen sind 1:1 aus Prod uebernommen (pg_get_viewdef, Stand
-- 2026-10-14, nach 20261014000000). Auf Prod ist diese Migration damit ein
-- No-op; lokal und auf neuen Datenbanken legt sie die Views an.
--
-- WITH (security_invoker = true) steht ausdruecklich im CREATE: ein
-- CREATE OR REPLACE VIEW ohne WITH-Klausel setzt die Option zurueck
-- (siehe 20261014000000). Rechte wie auf Prod.
--
-- Nutzung laut pg_stat_statements (seit 2026-04-02) bei Erstellung dieser
-- Migration -- alle fuenf werden abgefragt, keine wird hier geloescht.
-- ============================================================================

SET search_path TO public, extensions;

-- ----------------------------------------------------------------------------
-- v_stats_workflow_plot_map2
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_stats_workflow_plot_map2
WITH (security_invoker = true) AS
SELECT e.cluster_name,
    e.plot_name,
    e.forest_status27,
    e.responsible_administration,
    aufnahme.name AS troop_at,
    aufnahme.completed_at_troop_latest AS completed_at_latest,
    kontrolle.name AS troop_kt,
    kontrolle.completed_at_troop_latest AS completed_kt_latest,
    land.lil,
    land.responsible_state,
    land.completed_at_state_latest,
    bil.completed_at_administration_latest,
    troop_info.responsible_provider,
    troop_info.responsible_troop,
        CASE
            WHEN (bil.completed_at_administration_latest IS NOT NULL) THEN 9
            WHEN (land.completed_at_state_latest IS NOT NULL) THEN 7
            WHEN ((aufnahme.completed_at_troop_latest IS NULL) AND (kontrolle.completed_at_troop_latest IS NULL)) THEN 2
            WHEN ((aufnahme.completed_at_troop_latest IS NOT NULL) AND (kontrolle.completed_at_troop_latest IS NULL)) THEN 3
            WHEN ((aufnahme.completed_at_troop_latest IS NULL) AND (kontrolle.completed_at_troop_latest IS NOT NULL)) THEN 4
            WHEN ((aufnahme.completed_at_troop_latest IS NOT NULL) AND (kontrolle.completed_at_troop_latest IS NOT NULL) AND (aufnahme.completed_at_troop_latest < kontrolle.completed_at_troop_latest)) THEN 5
            WHEN ((aufnahme.completed_at_troop_latest IS NOT NULL) AND (kontrolle.completed_at_troop_latest IS NOT NULL) AND (aufnahme.completed_at_troop_latest > kontrolle.completed_at_troop_latest)) THEN 6
            ELSE '-1'::integer
        END AS wf,
        CASE
            WHEN (bil.completed_at_administration_latest IS NOT NULL) THEN 'TE akzeptiert von BIL'::text
            WHEN (land.completed_at_state_latest IS NOT NULL) THEN 'TE akzeptiert von LIL'::text
            WHEN ((aufnahme.completed_at_troop_latest IS NULL) AND (kontrolle.completed_at_troop_latest IS NULL)) THEN 'Aufnahme nicht begonnen'::text
            WHEN ((aufnahme.completed_at_troop_latest IS NOT NULL) AND (kontrolle.completed_at_troop_latest IS NULL)) THEN 'TE abgegeben von AT, nicht kontrolliert durch KT'::text
            WHEN ((aufnahme.completed_at_troop_latest IS NULL) AND (kontrolle.completed_at_troop_latest IS NOT NULL)) THEN 'TE durch KT aufgenommen und abgegeben'::text
            WHEN ((aufnahme.completed_at_troop_latest IS NOT NULL) AND (kontrolle.completed_at_troop_latest IS NOT NULL) AND (aufnahme.completed_at_troop_latest < kontrolle.completed_at_troop_latest)) THEN 'TE abgegeben von AT und kontrolliert durch KT'::text
            WHEN ((aufnahme.completed_at_troop_latest IS NOT NULL) AND (kontrolle.completed_at_troop_latest IS NOT NULL) AND (aufnahme.completed_at_troop_latest > kontrolle.completed_at_troop_latest)) THEN 'TE nach Kontrolle von KT nochmals abgegeben von AT'::text
            ELSE 'Fehler'::text
        END AS wf_text,
    st_x(st_transform(c.center_location, 4326)) AS x,
    st_y(st_transform(c.center_location, 4326)) AS y
   FROM (((((((( SELECT ee.cluster_name,
            ee.plot_name,
            ee.responsible_administration,
            max(ee.forest_status27) AS forest_status27
           FROM ( SELECT records.id,
                    records.responsible_administration,
                    records.responsible_state,
                    records.cluster_name,
                    records.plot_name,
                    records.responsible_troop,
                    records.completed_at_troop,
                    records.completed_at_state,
                    records.completed_at_administration,
                    ((records.properties ->> 'forest_status'::text))::integer AS forest_status27
                   FROM records
                  WHERE ((records.cluster_name < 1000000000) AND ((records.cluster_name < 9999900) OR (records.cluster_name > 10000000)))
                UNION
                 SELECT record_changes.id,
                    record_changes.responsible_administration,
                    record_changes.responsible_state,
                    record_changes.cluster_name,
                    record_changes.plot_name,
                    record_changes.responsible_troop,
                    record_changes.completed_at_troop,
                    record_changes.completed_at_state,
                    record_changes.completed_at_administration,
                    NULL::integer AS forest_status27
                   FROM record_changes
                  WHERE ((record_changes.cluster_name < 1000000000) AND ((record_changes.cluster_name < 9999900) OR (record_changes.cluster_name > 10000000)))) ee
          GROUP BY ee.cluster_name, ee.plot_name, ee.responsible_administration) e
     LEFT JOIN ( SELECT zwischen_at.cluster_name,
            zwischen_at.plot_name,
            zwischen_at.name,
            zwischen_at.completed_at_troop_latest,
            zwischen_at.r
           FROM ( SELECT r1.cluster_name,
                    r1.plot_name,
                    t1.name,
                    r1.completed_at_troop AS completed_at_troop_latest,
                    row_number() OVER (PARTITION BY r1.cluster_name, r1.plot_name ORDER BY r1.completed_at_troop DESC) AS r
                   FROM (( SELECT records.id,
                            records.responsible_administration,
                            records.responsible_state,
                            records.cluster_name,
                            records.plot_name,
                            records.responsible_troop,
                            records.completed_at_troop,
                            records.completed_at_state,
                            records.completed_at_administration,
                            ((records.properties ->> 'forest_status'::text))::integer AS forest_status27
                           FROM records
                          WHERE ((records.cluster_name < 1000000000) AND ((records.cluster_name < 9999900) OR (records.cluster_name > 10000000)))
                        UNION
                         SELECT record_changes.id,
                            record_changes.responsible_administration,
                            record_changes.responsible_state,
                            record_changes.cluster_name,
                            record_changes.plot_name,
                            record_changes.responsible_troop,
                            record_changes.completed_at_troop,
                            record_changes.completed_at_state,
                            record_changes.completed_at_administration,
                            NULL::integer AS forest_status27
                           FROM record_changes
                          WHERE ((record_changes.cluster_name < 1000000000) AND ((record_changes.cluster_name < 9999900) OR (record_changes.cluster_name > 10000000)))) r1
                     JOIN troop t1 ON ((r1.responsible_troop = t1.id)))
                  WHERE ((t1.is_control_troop IS FALSE) AND (r1.completed_at_troop IS NOT NULL))) zwischen_at
          WHERE (zwischen_at.r = 1)) aufnahme ON (((e.cluster_name = aufnahme.cluster_name) AND (e.plot_name = aufnahme.plot_name))))
     LEFT JOIN ( SELECT zwischen_kt.cluster_name,
            zwischen_kt.plot_name,
            zwischen_kt.name,
            zwischen_kt.completed_at_troop_latest,
            zwischen_kt.r
           FROM ( SELECT r2.cluster_name,
                    r2.plot_name,
                    t2.name,
                    r2.completed_at_troop AS completed_at_troop_latest,
                    row_number() OVER (PARTITION BY r2.cluster_name, r2.plot_name ORDER BY r2.completed_at_troop DESC) AS r
                   FROM (( SELECT records.id,
                            records.responsible_administration,
                            records.responsible_state,
                            records.cluster_name,
                            records.plot_name,
                            records.responsible_troop,
                            records.completed_at_troop,
                            records.completed_at_state,
                            records.completed_at_administration,
                            ((records.properties ->> 'forest_status'::text))::integer AS forest_status27
                           FROM records
                          WHERE ((records.cluster_name < 1000000000) AND ((records.cluster_name < 9999900) OR (records.cluster_name > 10000000)))
                        UNION
                         SELECT record_changes.id,
                            record_changes.responsible_administration,
                            record_changes.responsible_state,
                            record_changes.cluster_name,
                            record_changes.plot_name,
                            record_changes.responsible_troop,
                            record_changes.completed_at_troop,
                            record_changes.completed_at_state,
                            record_changes.completed_at_administration,
                            NULL::integer AS forest_status27
                           FROM record_changes
                          WHERE ((record_changes.cluster_name < 1000000000) AND ((record_changes.cluster_name < 9999900) OR (record_changes.cluster_name > 10000000)))) r2
                     JOIN troop t2 ON ((r2.responsible_troop = t2.id)))
                  WHERE ((t2.is_control_troop IS TRUE) AND (r2.completed_at_troop IS NOT NULL))) zwischen_kt
          WHERE (zwischen_kt.r = 1)) kontrolle ON (((e.cluster_name = kontrolle.cluster_name) AND (e.plot_name = kontrolle.plot_name))))
     LEFT JOIN ( SELECT land_inner.cluster_name,
            land_inner.plot_name,
            land_inner.lil,
            land_inner.responsible_state,
            land_inner.completed_at_state_latest
           FROM ( SELECT r3.cluster_name,
                    r3.plot_name,
                    o3.name AS lil,
                    o3.id AS responsible_state,
                    r3.completed_at_state AS completed_at_state_latest,
                    row_number() OVER (PARTITION BY r3.cluster_name, r3.plot_name ORDER BY r3.completed_at_state DESC NULLS LAST, r3.id DESC) AS r
                   FROM (( SELECT records.id,
                            records.responsible_state,
                            records.cluster_name,
                            records.plot_name,
                            records.completed_at_state
                           FROM records
                          WHERE ((records.cluster_name < 1000000000) AND ((records.cluster_name < 9999900) OR (records.cluster_name > 10000000)))
                        UNION
                         SELECT record_changes.id,
                            record_changes.responsible_state,
                            record_changes.cluster_name,
                            record_changes.plot_name,
                            record_changes.completed_at_state
                           FROM record_changes
                          WHERE ((record_changes.cluster_name < 1000000000) AND ((record_changes.cluster_name < 9999900) OR (record_changes.cluster_name > 10000000)))) r3
                     LEFT JOIN organizations o3 ON ((r3.responsible_state = o3.id)))) land_inner
          WHERE (land_inner.r = 1)) land ON (((e.cluster_name = land.cluster_name) AND (e.plot_name = land.plot_name))))
     LEFT JOIN ( SELECT r4.cluster_name,
            r4.plot_name,
            max(r4.completed_at_administration) AS completed_at_administration_latest
           FROM ( SELECT records.cluster_name,
                    records.plot_name,
                    records.completed_at_administration
                   FROM records
                  WHERE ((records.cluster_name < 1000000000) AND ((records.cluster_name < 9999900) OR (records.cluster_name > 10000000)))
                UNION
                 SELECT record_changes.cluster_name,
                    record_changes.plot_name,
                    record_changes.completed_at_administration
                   FROM record_changes
                  WHERE ((record_changes.cluster_name < 1000000000) AND ((record_changes.cluster_name < 9999900) OR (record_changes.cluster_name > 10000000)))) r4
          GROUP BY r4.cluster_name, r4.plot_name) bil ON (((e.cluster_name = bil.cluster_name) AND (e.plot_name = bil.plot_name))))
     LEFT JOIN ( SELECT troop_inner.cluster_name,
            troop_inner.plot_name,
            troop_inner.responsible_provider,
            troop_inner.responsible_troop
           FROM ( SELECT r_t.cluster_name,
                    r_t.plot_name,
                    r_t.responsible_provider,
                    r_t.responsible_troop,
                    row_number() OVER (PARTITION BY r_t.cluster_name, r_t.plot_name ORDER BY r_t.completed_at_troop DESC NULLS LAST, r_t.id DESC) AS r
                   FROM ( SELECT records.id,
                            records.responsible_provider,
                            records.responsible_troop,
                            records.cluster_name,
                            records.plot_name,
                            records.completed_at_troop
                           FROM records
                          WHERE ((records.cluster_name < 1000000000) AND ((records.cluster_name < 9999900) OR (records.cluster_name > 10000000)))
                        UNION
                         SELECT record_changes.id,
                            record_changes.responsible_provider,
                            record_changes.responsible_troop,
                            record_changes.cluster_name,
                            record_changes.plot_name,
                            record_changes.completed_at_troop
                           FROM record_changes
                          WHERE ((record_changes.cluster_name < 1000000000) AND ((record_changes.cluster_name < 9999900) OR (record_changes.cluster_name > 10000000)))) r_t) troop_inner
          WHERE (troop_inner.r = 1)) troop_info ON (((e.cluster_name = troop_info.cluster_name) AND (e.plot_name = troop_info.plot_name))))
     JOIN ( SELECT p_ordered.id,
            p_ordered.cluster_name,
            p_ordered.plot_name
           FROM ( SELECT plot.id,
                    plot.cluster_name,
                    plot.plot_name,
                    row_number() OVER (PARTITION BY plot.cluster_name, plot.plot_name ORDER BY
                        CASE plot.interval_name
                            WHEN 'bwi2022'::text THEN 1
                            WHEN 'ci2017'::text THEN 2
                            WHEN 'bwi2012'::text THEN 3
                            ELSE 4
                        END) AS rn
                   FROM inventory_archive.plot) p_ordered
          WHERE (p_ordered.rn = 1)) p ON (((e.cluster_name = p.cluster_name) AND (e.plot_name = p.plot_name))))
     JOIN inventory_archive.plot_coordinates c ON (((c.cluster_name = p.cluster_name) AND (c.plot_name = p.plot_name))));

COMMENT ON VIEW public.v_stats_workflow_plot_map2 IS
    'Workflow-Karte (TFM-Documentation: components/statistics/ClusterStatistics/WorkflowMap.vue). Eigene Nummerierung wf 2-9, siehe 20260825000000.';

GRANT ALL ON public.v_stats_workflow_plot_map2 TO anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- v_stats_workflow_plot_map
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_stats_workflow_plot_map
WITH (security_invoker = true) AS
SELECT e.cluster_name,
    e.plot_name,
    e.forest_status27,
    e.responsible_administration,
    aufnahme.troop_name AS troop_at,
    aufnahme.completed_at_troop AS completed_at_latest,
    kontrolle.troop_name AS troop_kt,
    kontrolle.completed_at_troop AS completed_kt_latest,
    land.responsible_state,
    land.completed_at_state_latest,
    land.completed_at_administration_latest,
        CASE
            WHEN (land.completed_at_administration_latest IS NOT NULL) THEN 9
            WHEN (land.completed_at_state_latest IS NOT NULL) THEN 7
            WHEN ((aufnahme.completed_at_troop IS NULL) AND (kontrolle.completed_at_troop IS NULL)) THEN 2
            WHEN ((aufnahme.completed_at_troop IS NOT NULL) AND (kontrolle.completed_at_troop IS NULL)) THEN 3
            WHEN ((aufnahme.completed_at_troop IS NULL) AND (kontrolle.completed_at_troop IS NOT NULL)) THEN 4
            WHEN ((aufnahme.completed_at_troop IS NOT NULL) AND (kontrolle.completed_at_troop IS NOT NULL) AND (aufnahme.completed_at_troop < kontrolle.completed_at_troop)) THEN 5
            WHEN ((aufnahme.completed_at_troop IS NOT NULL) AND (kontrolle.completed_at_troop IS NOT NULL) AND (aufnahme.completed_at_troop > kontrolle.completed_at_troop)) THEN 6
            ELSE '-1'::integer
        END AS wf,
        CASE
            WHEN (land.completed_at_administration_latest IS NOT NULL) THEN 'TE akzeptiert von BIL'::text
            WHEN (land.completed_at_state_latest IS NOT NULL) THEN 'TE akzeptiert von LIL'::text
            WHEN ((aufnahme.completed_at_troop IS NULL) AND (kontrolle.completed_at_troop IS NULL)) THEN 'Aufnahme nicht begonnen'::text
            WHEN ((aufnahme.completed_at_troop IS NOT NULL) AND (kontrolle.completed_at_troop IS NULL)) THEN 'TE abgegeben von AT, nicht kontrolliert durch KT'::text
            WHEN ((aufnahme.completed_at_troop IS NULL) AND (kontrolle.completed_at_troop IS NOT NULL)) THEN 'TE durch KT aufgenommen und abgegeben'::text
            WHEN ((aufnahme.completed_at_troop IS NOT NULL) AND (kontrolle.completed_at_troop IS NOT NULL) AND (aufnahme.completed_at_troop < kontrolle.completed_at_troop)) THEN 'TE abgegeben von AT und kontrolliert durch KT'::text
            WHEN ((aufnahme.completed_at_troop IS NOT NULL) AND (kontrolle.completed_at_troop IS NOT NULL) AND (aufnahme.completed_at_troop > kontrolle.completed_at_troop)) THEN 'TE nach Kontrolle von KT nochmals abgegeben von AT'::text
            ELSE 'Fehler'::text
        END AS wf_text,
    round((st_x(st_transform(c.center_location, 4326)))::numeric, 6) AS x,
    round((st_y(st_transform(c.center_location, 4326)))::numeric, 6) AS y
   FROM (((((( SELECT sub.cluster_name,
            sub.plot_name,
            sub.responsible_administration,
            max(sub.forest_status27) AS forest_status27
           FROM ( SELECT records.cluster_name,
                    records.plot_name,
                    records.responsible_administration,
                    ((records.properties ->> 'forest_status'::text))::integer AS forest_status27
                   FROM records
                  WHERE ((records.cluster_name < 1000000000) AND ((records.cluster_name < 9999900) OR (records.cluster_name > 10000000)) AND (records.completed_at_troop IS NOT NULL))
                UNION ALL
                 SELECT record_changes.cluster_name,
                    record_changes.plot_name,
                    record_changes.responsible_administration,
                    NULL::integer AS forest_status27
                   FROM record_changes
                  WHERE ((record_changes.cluster_name < 1000000000) AND ((record_changes.cluster_name < 9999900) OR (record_changes.cluster_name > 10000000)) AND (record_changes.completed_at_troop IS NOT NULL))) sub
          GROUP BY sub.cluster_name, sub.plot_name, sub.responsible_administration) e
     LEFT JOIN ( SELECT d.cluster_name,
            d.plot_name,
            t.name AS troop_name,
            d.completed_at_troop,
            t.is_control_troop,
            row_number() OVER (PARTITION BY d.cluster_name, d.plot_name, t.is_control_troop ORDER BY d.completed_at_troop DESC) AS rank_num
           FROM (( SELECT records.cluster_name,
                    records.plot_name,
                    records.responsible_troop,
                    records.completed_at_troop
                   FROM records
                  WHERE (records.completed_at_troop IS NOT NULL)
                UNION ALL
                 SELECT record_changes.cluster_name,
                    record_changes.plot_name,
                    record_changes.responsible_troop,
                    record_changes.completed_at_troop
                   FROM record_changes
                  WHERE (record_changes.completed_at_troop IS NOT NULL)) d
             JOIN troop t ON ((d.responsible_troop = t.id)))) aufnahme ON (((e.cluster_name = aufnahme.cluster_name) AND (e.plot_name = aufnahme.plot_name) AND (aufnahme.is_control_troop IS FALSE) AND (aufnahme.rank_num = 1))))
     LEFT JOIN ( SELECT d.cluster_name,
            d.plot_name,
            t.name AS troop_name,
            d.completed_at_troop,
            t.is_control_troop,
            row_number() OVER (PARTITION BY d.cluster_name, d.plot_name, t.is_control_troop ORDER BY d.completed_at_troop DESC) AS rank_num
           FROM (( SELECT records.cluster_name,
                    records.plot_name,
                    records.responsible_troop,
                    records.completed_at_troop
                   FROM records
                  WHERE (records.completed_at_troop IS NOT NULL)
                UNION ALL
                 SELECT record_changes.cluster_name,
                    record_changes.plot_name,
                    record_changes.responsible_troop,
                    record_changes.completed_at_troop
                   FROM record_changes
                  WHERE (record_changes.completed_at_troop IS NOT NULL)) d
             JOIN troop t ON ((d.responsible_troop = t.id)))) kontrolle ON (((e.cluster_name = kontrolle.cluster_name) AND (e.plot_name = kontrolle.plot_name) AND (kontrolle.is_control_troop IS TRUE) AND (kontrolle.rank_num = 1))))
     LEFT JOIN ( SELECT d.cluster_name,
            d.plot_name,
            max(o3.name) AS responsible_state,
            max(d.completed_at_state) AS completed_at_state_latest,
            max(d.completed_at_administration) AS completed_at_administration_latest
           FROM (( SELECT records.cluster_name,
                    records.plot_name,
                    records.responsible_state,
                    records.completed_at_state,
                    records.completed_at_administration
                   FROM records
                  WHERE ((records.completed_at_state >= '2025-01-01 00:00:00+00'::timestamp with time zone) OR (records.completed_at_administration >= '2025-01-01 00:00:00+00'::timestamp with time zone))
                UNION ALL
                 SELECT record_changes.cluster_name,
                    record_changes.plot_name,
                    record_changes.responsible_state,
                    record_changes.completed_at_state,
                    record_changes.completed_at_administration
                   FROM record_changes
                  WHERE ((record_changes.completed_at_state >= '2025-01-01 00:00:00+00'::timestamp with time zone) OR (record_changes.completed_at_administration >= '2025-01-01 00:00:00+00'::timestamp with time zone))) d
             LEFT JOIN organizations o3 ON ((d.responsible_state = o3.id)))
          GROUP BY d.cluster_name, d.plot_name) land ON (((e.cluster_name = land.cluster_name) AND (e.plot_name = land.plot_name))))
     JOIN inventory_archive.plot p ON (((e.cluster_name = p.cluster_name) AND (e.plot_name = p.plot_name))))
     JOIN inventory_archive.plot_coordinates c ON (((c.cluster_name = p.cluster_name) AND (c.plot_name = p.plot_name))));

COMMENT ON VIEW public.v_stats_workflow_plot_map IS
    'Vorgaenger von v_stats_workflow_plot_map2. Kein Aufrufer im Workspace, laut pg_stat_statements aber per PostgREST (authenticated) genutzt -- nicht loeschen, bevor der Aufrufer bekannt ist.';

GRANT ALL ON public.v_stats_workflow_plot_map TO anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- v_stats_workflow_cluster
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_stats_workflow_cluster
WITH (security_invoker = true) AS
SELECT bbb.lil,
    bbb.cluster_name,
    max(bbb.aufnahmetrupp) AS aufnahmetrupp,
    max(bbb.kontrolltrupp) AS kontrolltrupp,
    sum(bbb.anzahl_ecken) AS anzahl_ecken,
    sum(bbb.bereits_erfasste_waldecken) AS bereits_erfasste_waldecken,
    sum(bbb.vorhandene_waldecken) AS vorhandene_waldecken,
        CASE
            WHEN (sum(bbb.vorhandene_waldecken) > (0)::numeric) THEN 'Waldtrakt'::text
            ELSE 'Nichtwaldtrakt'::text
        END AS cluster_status,
        CASE
            WHEN (max(bbb.r) > 1) THEN 99
            ELSE min(bbb.wf)
        END AS wf,
        CASE
            WHEN (max(bbb.r) > 1) THEN 'unterschiedliche WF im Trakt'::text
            WHEN (min(bbb.wf) = 9) THEN 'TE akzeptiert von BIL'::text
            WHEN (min(bbb.wf) = 7) THEN 'TE akzeptiert von LIL'::text
            WHEN (min(bbb.wf) = 2) THEN 'Aufnahme nicht begonnen'::text
            WHEN (min(bbb.wf) = 3) THEN 'TE abgegeben von AT, nicht kontrolliert durch KT'::text
            WHEN (min(bbb.wf) = 4) THEN 'TE durch KT aufgenommen und abgegeben'::text
            WHEN (min(bbb.wf) = 5) THEN 'TE abgegeben von AT und kontrolliert durch KT'::text
            WHEN (min(bbb.wf) = 6) THEN 'TE nach Kontrolle von KT nochmals abgegeben von AT'::text
            ELSE 'Fehler'::text
        END AS wf_text,
    max(bbb.r) AS rowcount,
    ccc.inspire_grid_cell
   FROM (( SELECT aaa.responsible_state AS lil,
            aaa.cluster_name,
            aaa.troop_at AS aufnahmetrupp,
            aaa.troop_kt AS kontrolltrupp,
            count(*) AS anzahl_ecken,
            sum(
                CASE
                    WHEN ((aaa.completed_at_latest IS NOT NULL) AND (aaa.forest_status27 = ANY (ARRAY[3, 4, 5]))) THEN 1
                    ELSE 0
                END) AS bereits_erfasste_waldecken,
            sum(
                CASE
                    WHEN (aaa.forest_status27 = ANY (ARRAY[3, 4, 5])) THEN 1
                    ELSE 0
                END) AS vorhandene_waldecken,
            min(aaa.wf) AS wf,
                CASE
                    WHEN (sum(
                    CASE
                        WHEN (aaa.forest_status27 = ANY (ARRAY[3, 4, 5])) THEN 1
                        ELSE 0
                    END) > 0) THEN 'Waldtrakt'::text
                    ELSE 'Nichtwaldtrakt'::text
                END AS cluster_status,
            row_number() OVER (PARTITION BY aaa.responsible_state, aaa.cluster_name ORDER BY aaa.troop_at, aaa.troop_kt) AS r
           FROM ( SELECT e.cluster_name,
                    e.plot_name,
                    e.forest_status27,
                    e.responsible_administration,
                    aufnahme.name AS troop_at,
                    aufnahme.completed_at_troop_latest AS completed_at_latest,
                    kontrolle.name AS troop_kt,
                    kontrolle.completed_at_troop_latest AS completed_kt_latest,
                    land.responsible_state,
                    land.completed_at_state_latest,
                    bil.completed_at_administration_latest,
                        CASE
                            WHEN (bil.completed_at_administration_latest IS NOT NULL) THEN 9
                            WHEN (land.completed_at_state_latest IS NOT NULL) THEN 7
                            WHEN ((aufnahme.completed_at_troop_latest IS NULL) AND (kontrolle.completed_at_troop_latest IS NULL)) THEN 2
                            WHEN ((aufnahme.completed_at_troop_latest IS NOT NULL) AND (kontrolle.completed_at_troop_latest IS NULL)) THEN 3
                            WHEN ((aufnahme.completed_at_troop_latest IS NULL) AND (kontrolle.completed_at_troop_latest IS NOT NULL)) THEN 4
                            WHEN ((aufnahme.completed_at_troop_latest IS NOT NULL) AND (kontrolle.completed_at_troop_latest IS NOT NULL) AND (aufnahme.completed_at_troop_latest < kontrolle.completed_at_troop_latest)) THEN 5
                            WHEN ((aufnahme.completed_at_troop_latest IS NOT NULL) AND (kontrolle.completed_at_troop_latest IS NOT NULL) AND (aufnahme.completed_at_troop_latest > kontrolle.completed_at_troop_latest)) THEN 6
                            ELSE '-1'::integer
                        END AS wf
                   FROM ((((( SELECT ee.cluster_name,
                            ee.plot_name,
                            ee.responsible_administration,
                            max(ee.forest_status27) AS forest_status27
                           FROM ( SELECT records.id,
                                    records.responsible_administration,
                                    records.responsible_state,
                                    records.cluster_name,
                                    records.plot_name,
                                    records.responsible_troop,
                                    records.completed_at_troop,
                                    records.completed_at_state,
                                    records.completed_at_administration,
                                    ((records.properties ->> 'forest_status'::text))::integer AS forest_status27
                                   FROM records
                                  WHERE ((records.cluster_name < 1000000000) AND ((records.cluster_name < 9999900) OR (records.cluster_name > 10000000)))
                                UNION
                                 SELECT record_changes.id,
                                    record_changes.responsible_administration,
                                    record_changes.responsible_state,
                                    record_changes.cluster_name,
                                    record_changes.plot_name,
                                    record_changes.responsible_troop,
                                    record_changes.completed_at_troop,
                                    record_changes.completed_at_state,
                                    record_changes.completed_at_administration,
                                    NULL::integer AS forest_status27
                                   FROM record_changes
                                  WHERE ((record_changes.cluster_name < 1000000000) AND ((record_changes.cluster_name < 9999900) OR (record_changes.cluster_name > 10000000)))) ee
                          GROUP BY ee.cluster_name, ee.plot_name, ee.responsible_administration) e
                     LEFT JOIN ( SELECT zwischen_at.cluster_name,
                            zwischen_at.plot_name,
                            zwischen_at.name,
                            zwischen_at.completed_at_troop_latest,
                            zwischen_at.r
                           FROM ( SELECT r1.cluster_name,
                                    r1.plot_name,
                                    t1.name,
                                    r1.completed_at_troop AS completed_at_troop_latest,
                                    row_number() OVER (PARTITION BY r1.cluster_name, r1.plot_name ORDER BY r1.completed_at_troop DESC) AS r
                                   FROM (( SELECT records.id,
    records.responsible_administration,
    records.responsible_state,
    records.cluster_name,
    records.plot_name,
    records.responsible_troop,
    records.completed_at_troop,
    records.completed_at_state,
    records.completed_at_administration,
    ((records.properties ->> 'forest_status'::text))::integer AS forest_status27
   FROM records
  WHERE ((records.cluster_name < 1000000000) AND ((records.cluster_name < 9999900) OR (records.cluster_name > 10000000)))
UNION
 SELECT record_changes.id,
    record_changes.responsible_administration,
    record_changes.responsible_state,
    record_changes.cluster_name,
    record_changes.plot_name,
    record_changes.responsible_troop,
    record_changes.completed_at_troop,
    record_changes.completed_at_state,
    record_changes.completed_at_administration,
    NULL::integer AS forest_status27
   FROM record_changes
  WHERE ((record_changes.cluster_name < 1000000000) AND ((record_changes.cluster_name < 9999900) OR (record_changes.cluster_name > 10000000)))) r1
                                     JOIN troop t1 ON ((r1.responsible_troop = t1.id)))
                                  WHERE ((t1.is_control_troop IS FALSE) AND (r1.completed_at_troop IS NOT NULL))) zwischen_at
                          WHERE (zwischen_at.r = 1)) aufnahme ON (((e.cluster_name = aufnahme.cluster_name) AND (e.plot_name = aufnahme.plot_name))))
                     LEFT JOIN ( SELECT zwischen_kt.cluster_name,
                            zwischen_kt.plot_name,
                            zwischen_kt.name,
                            zwischen_kt.completed_at_troop_latest,
                            zwischen_kt.r
                           FROM ( SELECT r2.cluster_name,
                                    r2.plot_name,
                                    t2.name,
                                    r2.completed_at_troop AS completed_at_troop_latest,
                                    row_number() OVER (PARTITION BY r2.cluster_name, r2.plot_name ORDER BY r2.completed_at_troop DESC) AS r
                                   FROM (( SELECT records.id,
    records.responsible_administration,
    records.responsible_state,
    records.cluster_name,
    records.plot_name,
    records.responsible_troop,
    records.completed_at_troop,
    records.completed_at_state,
    records.completed_at_administration,
    ((records.properties ->> 'forest_status'::text))::integer AS forest_status27
   FROM records
  WHERE ((records.cluster_name < 1000000000) AND ((records.cluster_name < 9999900) OR (records.cluster_name > 10000000)))
UNION
 SELECT record_changes.id,
    record_changes.responsible_administration,
    record_changes.responsible_state,
    record_changes.cluster_name,
    record_changes.plot_name,
    record_changes.responsible_troop,
    record_changes.completed_at_troop,
    record_changes.completed_at_state,
    record_changes.completed_at_administration,
    NULL::integer AS forest_status27
   FROM record_changes
  WHERE ((record_changes.cluster_name < 1000000000) AND ((record_changes.cluster_name < 9999900) OR (record_changes.cluster_name > 10000000)))) r2
                                     JOIN troop t2 ON ((r2.responsible_troop = t2.id)))
                                  WHERE ((t2.is_control_troop IS TRUE) AND (r2.completed_at_troop IS NOT NULL))) zwischen_kt
                          WHERE (zwischen_kt.r = 1)) kontrolle ON (((e.cluster_name = kontrolle.cluster_name) AND (e.plot_name = kontrolle.plot_name))))
                     LEFT JOIN ( SELECT r3.cluster_name,
                            r3.plot_name,
                            max(o3.name) AS responsible_state,
                            max(r3.completed_at_state) AS completed_at_state_latest
                           FROM (( SELECT records.id,
                                    records.responsible_administration,
                                    records.responsible_state,
                                    records.cluster_name,
                                    records.plot_name,
                                    records.responsible_troop,
                                    records.completed_at_troop,
                                    records.completed_at_state,
                                    records.completed_at_administration,
                                    ((records.properties ->> 'forest_status'::text))::integer AS forest_status27
                                   FROM records
                                  WHERE ((records.cluster_name < 1000000000) AND ((records.cluster_name < 9999900) OR (records.cluster_name > 10000000)))
                                UNION
                                 SELECT record_changes.id,
                                    record_changes.responsible_administration,
                                    record_changes.responsible_state,
                                    record_changes.cluster_name,
                                    record_changes.plot_name,
                                    record_changes.responsible_troop,
                                    record_changes.completed_at_troop,
                                    record_changes.completed_at_state,
                                    record_changes.completed_at_administration,
                                    NULL::integer AS forest_status27
                                   FROM record_changes
                                  WHERE ((record_changes.cluster_name < 1000000000) AND ((record_changes.cluster_name < 9999900) OR (record_changes.cluster_name > 10000000)))) r3
                             LEFT JOIN organizations o3 ON ((r3.responsible_state = o3.id)))
                          GROUP BY r3.cluster_name, r3.plot_name) land ON (((e.cluster_name = land.cluster_name) AND (e.plot_name = land.plot_name))))
                     LEFT JOIN ( SELECT r3.cluster_name,
                            r3.plot_name,
                            max(r3.completed_at_administration) AS completed_at_administration_latest
                           FROM (( SELECT records.id,
                                    records.responsible_administration,
                                    records.responsible_state,
                                    records.cluster_name,
                                    records.plot_name,
                                    records.responsible_troop,
                                    records.completed_at_troop,
                                    records.completed_at_state,
                                    records.completed_at_administration,
                                    ((records.properties ->> 'forest_status'::text))::integer AS forest_status27
                                   FROM records
                                  WHERE ((records.cluster_name < 1000000000) AND ((records.cluster_name < 9999900) OR (records.cluster_name > 10000000)))
                                UNION
                                 SELECT record_changes.id,
                                    record_changes.responsible_administration,
                                    record_changes.responsible_state,
                                    record_changes.cluster_name,
                                    record_changes.plot_name,
                                    record_changes.responsible_troop,
                                    record_changes.completed_at_troop,
                                    record_changes.completed_at_state,
                                    record_changes.completed_at_administration,
                                    NULL::integer AS forest_status27
                                   FROM record_changes
                                  WHERE ((record_changes.cluster_name < 1000000000) AND ((record_changes.cluster_name < 9999900) OR (record_changes.cluster_name > 10000000)))) r3
                             LEFT JOIN organizations o3 ON ((r3.responsible_state = o3.id)))
                          GROUP BY r3.cluster_name, r3.plot_name) bil ON (((e.cluster_name = bil.cluster_name) AND (e.plot_name = bil.plot_name))))) aaa
          GROUP BY aaa.responsible_state, aaa.cluster_name, aaa.troop_at, aaa.troop_kt) bbb
     JOIN inventory_archive.cluster ccc ON ((bbb.cluster_name = ccc.cluster_name)))
  GROUP BY bbb.lil, bbb.cluster_name, ccc.inspire_grid_cell;

COMMENT ON VIEW public.v_stats_workflow_cluster IS
    'Workflow-Status je Trakt. Kein Aufrufer im Workspace, laut pg_stat_statements per PostgREST (authenticated) und ti_read genutzt.';

GRANT ALL ON public.v_stats_workflow_cluster TO anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- v_stats_performance_by_troop_by_week_forest
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_stats_performance_by_troop_by_week_forest
WITH (security_invoker = true) AS
SELECT r.responsible_state,
    r.responsible_administration,
    r.responsible_provider,
    o.name AS lil,
    r.responsible_troop,
    t.name AS troop_name,
    t.is_control_troop AS kt,
    to_char(COALESCE(r.completed_at_troop, ( SELECT max(c.completed_at_troop) AS max
           FROM record_changes c
          WHERE ((c.cluster_name = r.cluster_name) AND (c.plot_name = r.plot_name) AND (c.responsible_troop = r.responsible_troop) AND (c.completed_at_troop IS NOT NULL) AND (c.cluster_name < 1000000000) AND ((c.cluster_name < 9999900) OR (c.cluster_name > 10000000))))), 'IYYY-IW'::text) AS woche,
    count(*) AS anzahl
   FROM ((records r
     JOIN troop t ON ((r.responsible_troop = t.id)))
     JOIN organizations o ON ((r.responsible_state = o.id)))
  WHERE ((r.completed_at_troop IS NOT NULL) AND (r.cluster_name < 1000000000) AND ((r.cluster_name < 9999900) OR (r.cluster_name > 10000000)) AND (((r.properties ->> 'forest_status'::text))::integer = ANY (ARRAY[3, 4, 5])) AND (((r.properties ->> 'accessibility'::text))::integer = 1))
  GROUP BY r.responsible_state, r.responsible_administration, r.responsible_provider, o.name, r.responsible_troop, t.name, t.is_control_troop, (to_char(COALESCE(r.completed_at_troop, ( SELECT max(c.completed_at_troop) AS max
           FROM record_changes c
          WHERE ((c.cluster_name = r.cluster_name) AND (c.plot_name = r.plot_name) AND (c.responsible_troop = r.responsible_troop) AND (c.completed_at_troop IS NOT NULL) AND (c.cluster_name < 1000000000) AND ((c.cluster_name < 9999900) OR (c.cluster_name > 10000000))))), 'IYYY-IW'::text))
  ORDER BY o.name, t.name, (to_char(COALESCE(r.completed_at_troop, ( SELECT max(c.completed_at_troop) AS max
           FROM record_changes c
          WHERE ((c.cluster_name = r.cluster_name) AND (c.plot_name = r.plot_name) AND (c.responsible_troop = r.responsible_troop) AND (c.completed_at_troop IS NOT NULL) AND (c.cluster_name < 1000000000) AND ((c.cluster_name < 9999900) OR (c.cluster_name > 10000000))))), 'IYYY-IW'::text));

COMMENT ON VIEW public.v_stats_performance_by_troop_by_week_forest IS
    'TFM-Documentation: components/statistics/TroopStatistics/PerformanceByTroopByWeekForest.vue';

GRANT ALL ON public.v_stats_performance_by_troop_by_week_forest TO anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- v_stats_performance_by_troop_by_month_forest
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_stats_performance_by_troop_by_month_forest
WITH (security_invoker = true) AS
SELECT r.responsible_state,
    r.responsible_administration,
    r.responsible_provider,
    o.name AS lil,
    r.responsible_troop,
    t.name AS troop_name,
    t.is_control_troop AS kt,
    to_char(COALESCE(r.completed_at_troop, ( SELECT max(c.completed_at_troop) AS max
           FROM record_changes c
          WHERE ((c.cluster_name = r.cluster_name) AND (c.plot_name = r.plot_name) AND (c.responsible_troop = r.responsible_troop) AND (c.completed_at_troop IS NOT NULL) AND (c.cluster_name < 1000000000) AND ((c.cluster_name < 9999900) OR (c.cluster_name > 10000000))))), 'YYYY-MM'::text) AS monat,
    count(*) AS anzahl
   FROM ((records r
     JOIN troop t ON ((r.responsible_troop = t.id)))
     JOIN organizations o ON ((r.responsible_state = o.id)))
  WHERE ((r.completed_at_troop IS NOT NULL) AND (r.cluster_name < 1000000000) AND ((r.cluster_name < 9999900) OR (r.cluster_name > 10000000)) AND (((r.properties ->> 'forest_status'::text))::integer = ANY (ARRAY[3, 4, 5])) AND (((r.properties ->> 'accessibility'::text))::integer = 1))
  GROUP BY r.responsible_state, r.responsible_administration, r.responsible_provider, o.name, r.responsible_troop, t.name, t.is_control_troop, (to_char(COALESCE(r.completed_at_troop, ( SELECT max(c.completed_at_troop) AS max
           FROM record_changes c
          WHERE ((c.cluster_name = r.cluster_name) AND (c.plot_name = r.plot_name) AND (c.responsible_troop = r.responsible_troop) AND (c.completed_at_troop IS NOT NULL) AND (c.cluster_name < 1000000000) AND ((c.cluster_name < 9999900) OR (c.cluster_name > 10000000))))), 'YYYY-MM'::text))
  ORDER BY o.name, t.name, (to_char(COALESCE(r.completed_at_troop, ( SELECT max(c.completed_at_troop) AS max
           FROM record_changes c
          WHERE ((c.cluster_name = r.cluster_name) AND (c.plot_name = r.plot_name) AND (c.responsible_troop = r.responsible_troop) AND (c.completed_at_troop IS NOT NULL) AND (c.cluster_name < 1000000000) AND ((c.cluster_name < 9999900) OR (c.cluster_name > 10000000))))), 'YYYY-MM'::text));

COMMENT ON VIEW public.v_stats_performance_by_troop_by_month_forest IS
    'TFM-Documentation: components/statistics/TroopStatistics/PerformanceByTroopByMonthForest.vue';

GRANT ALL ON public.v_stats_performance_by_troop_by_month_forest TO anon, authenticated, service_role;

RESET search_path;

NOTIFY pgrst, 'reload schema';
