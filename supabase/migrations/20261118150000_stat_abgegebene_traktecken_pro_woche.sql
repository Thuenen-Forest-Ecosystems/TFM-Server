-- ============================================================================
-- MIGRATION: RPC-Funktion stat_abgegebene_traktecken_pro_woche
-- ============================================================================
-- Angelegt am 2026-11-18 durch Thomas Riedel.
-- Prozedur liefert Überblick zu abgegebenen Traktecken pro Woche pro Aufnahme-
-- trupp
--
-- Genutzt in TFM-Documentation:
--   components/statistics/TroopStatistics/...
-- ============================================================================

SET search_path TO public, extensions;

CREATE OR REPLACE FUNCTION public.stat_abgegebene_traktecken_pro_woche(
    user_id text
)
RETURNS TABLE (
    landesinventurleitung text,
    troop_name text,
    kontrolltrupp boolean,
    woche text,
    abgegebene_ecken bigint,
    davon_wald_ecken bigint,
    davon_begehbare_wald_ecken bigint,
    davon_holzboden_ecken bigint,
    davon_begehbare_holzboden_ecken bigint
)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $BODY$
/*Relevante Tabellen*/
--select * from public.organizations 
--select * from public.troop 

/*Inputparameter*/
--user_id wird der Funktion übergeben und gibt entweder den Trupp oder die Organisation an.
--Bezieht sich auf public.records / record_changes: responsible_administration, responsible_state, responsible_provider oder responsible_troop.

/*Beispiele*/
--select public.stat_abgegebene_traktecken_pro_woche('3889fc5b-503f-495b-8f06-60c3e06cd8ae'); = LIL ST
--select public.stat_abgegebene_traktecken_pro_woche('460faca2-d7ae-499c-a972-09701d42de76'); = KT-Thünen Bayern
--select * from public.stat_abgegebene_traktecken_pro_woche('cee0b61d-4e42-4ef0-b910-bc2388632a49'); = Thünen Los 4 Bayern Ost

--

/*Spalten der Ergebnistabelle*/
--Landesinventurleitung (lil)
--Trupp (troop_name)
--Kontrolltrupp? (kt)
--Woche text
--abgegebene_ecken bigint,
--davon_wald_ecken bigint,
--davon_begehbare_wald_ecken bigint,
--davon_holzboden_ecken bigint,
--davon_begehbare_holzboden_ecken bigint

/*Angelegt am 2026-11-18 durch Thomas Riedel*/
/*Change-Log*/
-- 

/*Inhalt*/
--1.2a Leistung pro Inventurtrupp: abgegebene Traktecken (Wald + Nichtwald)
--1.2.2 pro Woche
--CREATE OR REPLACE VIEW v_stats_performance_by_troop_by_month with(security_invoker=true) AS
SELECT lil, troop_name, kt, to_char(completed_at_survey_troop, 'IYYY-IW') as woche, 
       count(*) as abgegebene_ecken,
       sum(case when foreststatus27 in (3,4,5) then 1 else 0 end) as davon_wald_ecken,
       sum(case when foreststatus27 in (3,4,5) and begehbar27 = 1 then 1 else 0 end) as davon_begehbare_wald_ecken,
       sum(case when foreststatus27 in (3,5) then 1 else 0 end) as davon_holzboden_ecken,
       sum(case when foreststatus27 in (3,5) and begehbar27 = 1 then 1 else 0 end) as davon_begehbare_holzboden_ecken
  from ( select o.name as lil, r.cluster_name, r.plot_name, t.name as troop_name, t.is_control_troop as kt, r.completed_at_survey_troop,
                CAST(r.properties ->> 'forest_status' AS integer) as foreststatus27, 
                CAST(r.properties ->> 'accessibility' AS integer) as begehbar27
	       from public.view_records_details as r
           join public.troop as t
	         on r.last_survey_troop = t.id
           join public.organizations as o
             on r.responsible_state = o.id
	       where cluster_name < 1000000000 and (cluster_name not between 9999900 and 10000000) 
             and last_survey_troop is not null and completed_at_survey_troop is not null  
             and (   r.responsible_administration::text = user_id 
                  or r.responsible_state::text = user_id 
                  or r.responsible_provider::text = user_id 
                  or r.last_survey_troop::text = user_id
                  or r.last_control_troop::text = user_id
                 )
        ) as t
  group by lil, troop_name, kt, to_char(completed_at_survey_troop, 'IYYY-IW')
  order by lil, troop_name, to_char(completed_at_survey_troop, 'IYYY-IW')

$BODY$;

COMMENT ON FUNCTION public.stat_abgegebene_traktecken_pro_woche(text) IS
    'Statistik abgegebener Trakte pro Woche und Inventurtrupp (Thomas Riedel, 2026-10-15). TFM-Documentation: components/statistics/TroopStatistics/PlotsDeliveredByTroopAndDate.vue';

GRANT EXECUTE ON FUNCTION public.stat_abgegebene_traktecken_pro_woche(text) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

