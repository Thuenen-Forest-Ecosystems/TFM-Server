-- ============================================================================
-- MIGRATION: RPC-Funktion stat_abgegebene_traktecken_pro_at_member
-- ============================================================================
-- Angelegt am 2026-10-15 durch Thomas Riedel.
-- Korrigiert am 2026-11-06: responsible_administration & responsible_provider
-- einbeziehen, damit die Abfrage auch fuer die Organisation Thuenen (BIL)
-- und Dienstleister Daten liefert.
--
-- Genutzt in TFM-Documentation:
--   components/statistics/TroopStatistics/PlotsDeliveredByTroopAndDate.vue
-- ============================================================================

SET search_path TO public, extensions;
--drop function public.stat_abgegebene_traktecken_pro_at_member(text);
CREATE OR REPLACE FUNCTION public.stat_abgegebene_traktecken_pro_at_member(
    user_id_uebergabe text
)
RETURNS TABLE (
    landesinventurleitung text,
    cluster_name integer,
    plot_name smallint,
    troop_name text,
    kontrolltrupp boolean,
    abgabedatum timestamp with time zone,
    user_name text,
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
--select * from public.stat_abgegebene_traktecken_pro_at_member('3889fc5b-503f-495b-8f06-60c3e06cd8ae'); = LIL ST
--select * from public.stat_abgegebene_traktecken_pro_at_member('460faca2-d7ae-499c-a972-09701d42de76'); = KT-Thünen Bayern
--select * from public.stat_abgegebene_traktecken_pro_at_member('cee0b61d-4e42-4ef0-b910-bc2388632a49'); = Thünen Los 4 Bayern Ost
--select * from public.stat_abgegebene_traktecken_pro_at_member('d4f08574-24f4-4c29-801a-f1d9bf9d38e0'); = LIL NW
--select * from public.stat_abgegebene_traktecken_pro_at_member('ee2ea837-8eaa-44cb-a1ba-95ef4c915355');
--ee2ea837-8eaa-44cb-a1ba-95ef4c915355

/*Spalten der Ergebnistabelle*/
--Landesinventurleitung (lil)
--Traktnummer (cluster_name)
--Eckennummer (plot_name)
--Trupp (troop_name)
--Kontrolltrupp? (kt)
--Abgabedatum (completed_at_troop)
--Truppmitglied,
--Waldentscheid2027 (wald2027)
--Begehbarkeit2027 (begehbar2027)

/*Angelegt am 2026-10-15 durch Thomas Riedel*/
/*Change-Log*/
-- 2026-11-06: Filter um responsible_administration und responsible_provider erweitert,
--             damit auch die Organisation Thuenen (BIL) und Dienstleister Daten erhalten.

/*Inhalt*/
--1.1 Statistik abgegebener Trakte pro Inventurtrupp (letztes Datum) 
select --responsible_state,               --uuid
       lil,                             --Landesinventurleitung text
       --cluster_id,                      --uuid des Traktes
       cluster_name,                    --Traktnummer integer
       plot_name,                       --Trakteckennummer smallint       
       troop_name,                      --Trupp text
       kt,                              --Kontrolltrupp? boolean
       completed_at_survey_troop as abgabedatum, --Abgabedatum 
       truppmitglied,    --Name Truppmitglied (welches geliefert hat)
       foreststatus27 as wald2027,      --Waldentscheid2027
       begehbar27 as begehbar2027      --Begehbarkeit2027
       --responsible_administration,      --
       --responsible_provider,            --
       --responsible_troop                --uuid des Trupps
  from ( select r1.responsible_state, o1.name as lil, r1.cluster_id, r1.cluster_name, r1.plot_name, r1.responsible_administration, r1.responsible_provider, r1.responsible_troop, t1.name as troop_name, t1.is_control_troop as kt, 
                r1.completed_at_survey_troop, 
                CAST(r1.properties ->> 'forest_status' as integer) as foreststatus27, 
                CAST(r1.properties ->> 'accessibility' as integer) as begehbar27,
                z.updated_by as troop_member_id, 
                z.user_name as truppmitglied
           from public.view_records_details as r1 
           join public.troop as t1 
             on r1.last_survey_troop = t1.id 
           join public.organizations as o1 
             on r1.responsible_state = o1.id 
           join (select r.cluster_name, r.plot_name, r.last_survey_troop, r.completed_at_survey_troop,
                        c.responsible_troop, c.completed_at_troop, c.updated_at, c.updated_by, up.user_name
                   from public.view_records_details as r
                   join public.record_changes as c
                     on r.last_survey_troop = c.responsible_troop and r.completed_at_survey_troop = c.completed_at_troop
                   join public.troop_members tm 
                     on c.updated_by  = tm.user_id
                   join public.users_profile up 
                     on tm.user_id = up.id) as z
             on r1.cluster_name = z.cluster_name
               and r1.plot_name = z.plot_name
               and r1.last_survey_troop = z.last_survey_troop
               and r1.completed_at_survey_troop = z.completed_at_troop
           where r1.cluster_name < 1000000000 and (r1.cluster_name not between 9999900 and 10000000) 
             and r1.last_survey_troop is not null and r1.completed_at_survey_troop is not null 
             and (   r1.responsible_administration::text = user_id_uebergabe 
                  or r1.responsible_state::text = user_id_uebergabe 
                  or r1.responsible_provider::text = user_id_uebergabe 
                  or r1.last_survey_troop::text = user_id_uebergabe
                  or r1.last_control_troop::text = user_id_uebergabe
                 )
       ) as t 
  --group by responsible_state, lil, cluster_id, cluster_name, plot_name, responsible_administration, responsible_provider, responsible_troop, troop_name, kt, foreststatus27, begehbar27 
  order by lil, troop_name, cluster_name, plot_name;
$BODY$;

COMMENT ON FUNCTION public.stat_abgegebene_traktecken_pro_at_member(text) IS
    'Statistik abgegebener Trakte pro Inventurtruppmitglied (Thomas Riedel, 2026-11-27). TFM-Documentation: components/statistics/TroopStatistics/PlotsDeliveredByTroopAndDate.vue';

GRANT EXECUTE ON FUNCTION public.stat_abgegebene_traktecken_pro_at_member(text) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

--select up.user_name, r.*  
--from public.records r
--join public.troop_members tm 
--on r.updated_by  = tm.user_id
--join public.users_profile up 
--on tm.user_id = up.id 
--where cluster_name = 16507



--select r.cluster_name, r.plot_name, r.last_survey_troop, r.completed_at_survey_troop,
--       c.responsible_troop, c.completed_at_troop, c.updated_at, c.updated_by, up.user_name
--  from public.view_records_details as r
--  join public.record_changes as c
--    on r.last_survey_troop = c.responsible_troop and r.completed_at_survey_troop = c.completed_at_troop
--  join public.troop_members tm 
--    on c.updated_by  = tm.user_id
--  join public.users_profile up 
--    on tm.user_id = up.id