-- ============================================================================
-- MIGRATION: RPC-Funktion stat_kontrollierte_traktecken_pro_at
-- ============================================================================
-- Angelegt am 2026-11-18 durch Thomas Riedel.
-- Prozedur liefert Überblick zu kontrollierten Traktecken pro Aufnahmetrupp
--
-- Genutzt in TFM-Documentation:
--   components/statistics/TroopStatistics/PlotsDeliveredByTroopAndDate.vue
-- ============================================================================

SET search_path TO public, extensions;

CREATE OR REPLACE FUNCTION public.stat_kontrollierte_traktecken_pro_at(
    user_id text
)
RETURNS TABLE (
    landesinventurleitung text,
    cluster_name integer,
    plot_name smallint,
    troop_name text,
    kontrolltrupp boolean,
    abgabedatum_at timestamp with time zone,
    abgabedatum_kt timestamp with time zone,
    waldentscheid2027 integer,
    begehbarkeit2027 integer
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
--select public.stat_kontrollierte_traktecken_pro_at('3889fc5b-503f-495b-8f06-60c3e06cd8ae'); = LIL ST
--select public.stat_kontrollierte_traktecken_pro_at('460faca2-d7ae-499c-a972-09701d42de76'); = KT-Thünen Bayern
--select * from public.stat_kontrollierte_traktecken_pro_at('cee0b61d-4e42-4ef0-b910-bc2388632a49'); = Thünen Los 4 Bayern Ost

--

/*Spalten der Ergebnistabelle*/
--Landesinventurleitung (lil)
--Traktnummer (cluster_name)
--Eckennummer (plot_name)
--Trupp (troop_name)
--Kontrolltrupp? (kt)
--Abgabedatum_AT (abgabedatum_at)
--Abgabedatum_KT (abgabedatum_kt)
--Waldentscheid2027 (wald2027)
--Begehbarkeit2027 (begehbar2027)

/*Angelegt am 2026-11-18 durch Thomas Riedel*/
/*Change-Log*/


/*Inhalt*/
--1.3 Statistik abgegebener Trakte pro Inventurtrupp (letztes Datum) 
select --responsible_state,               --uuid
       lil,                             --Landesinventurleitung text
       --cluster_id,                      --uuid des Traktes
       cluster_name,                    --Traktnummer integer
       plot_name,                       --Trakteckennummer smallint       
       troop_name,                      --Trupp text
       kt,                              --Kontrolltrupp? boolean
       completed_at_survey_troop as abgabedatum_at, --Abgabedatum_AT
       completed_at_control_troop as abgabedatum_kt, --Abgabedatum_KT
       foreststatus27 as wald2027,      --Waldentscheid2027
       begehbar27 as begehbar2027      --Begehbarkeit2027
       --responsible_administration,      --
       --responsible_provider,            --
       --responsible_troop                --uuid des Trupps
  from ( select r1.responsible_state, o1.name as lil, r1.cluster_id, r1.cluster_name, r1.plot_name, r1.responsible_administration, r1.responsible_provider, r1.responsible_troop, t1.name as troop_name, t1.is_control_troop as kt, 
                r1.completed_at_survey_troop, r1.completed_at_control_troop,
                CAST(r1.properties ->> 'forest_status' as integer) as foreststatus27, 
                CAST(r1.properties ->> 'accessibility' as integer) as begehbar27 
           from public.view_records_details as r1 
           join public.troop as t1 
             on r1.last_survey_troop = t1.id 
           join public.organizations as o1 
             on r1.responsible_state = o1.id 
           where cluster_name < 1000000000 and (cluster_name not between 9999900 and 10000000) 
             and last_survey_troop is not null and completed_at_survey_troop is not null and completed_at_control_troop is not null 
             and (   r1.responsible_administration::text = user_id 
                  or r1.responsible_state::text = user_id 
                  or r1.responsible_provider::text = user_id 
                  or r1.last_survey_troop::text = user_id
                  or r1.last_control_troop::text = user_id
                 )
       ) as t 
  --group by responsible_state, lil, cluster_id, cluster_name, plot_name, responsible_administration, responsible_provider, responsible_troop, troop_name, kt, foreststatus27, begehbar27 
  order by lil, troop_name, cluster_name, plot_name;
$BODY$;

COMMENT ON FUNCTION public.stat_kontrollierte_traktecken_pro_at(text) IS
    'Statistik kontrollierter Traktecken pro Inventurtrupp (Thomas Riedel, 2026-10-15). TFM-Documentation: components/statistics/TroopStatistics/PlotsDeliveredByTroopAndDate.vue';

GRANT EXECUTE ON FUNCTION public.stat_kontrollierte_traktecken_pro_at(text) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

