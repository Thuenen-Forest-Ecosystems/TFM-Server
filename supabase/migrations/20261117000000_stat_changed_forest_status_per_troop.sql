-- ============================================================================
-- MIGRATION: RPC-Funktion stat_changed_forest_status_per_troop
-- ============================================================================
-- Angelegt am 2026-11-17 durch Thomas Riedel.
-- Prozedur liefert Überblick zur Anzahl Traktecken auf denen sich der
-- Waldentscheid gegenüber der Vorgängerinventur geändert hat pro Aufnahmetrupp
-- Genutzt in TFM-Documentation:
--   components/statistics/PlotStatistics/
-- ============================================================================

SET search_path TO public, extensions;

CREATE OR REPLACE FUNCTION public.stat_changed_forest_status_per_troop(
    user_id text
)
RETURNS TABLE (
    landesinventurleitung text,
    troop_name text,
    kontrolltrupp boolean,
    aenderung_waldentscheid integer,
    aenderung_begehbar integer
)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $BODY$
/*Relevante Tabellen*/
--select * from public.organizations 
--select * from public.troop 
--select * from public.troop_members
--select * from public.users_profile where user_name like '%Frank%'
--select * from public.view_records_details

/*Inputparameter*/
--user_id wird der Funktion übergeben und gibt entweder den Trupp oder die Organisation an.
--Bezieht sich auf public.view_records_details: responsible_administration, responsible_state, responsible_provider oder last_survey_troop und completed_at_survey_troop.

/*Beispiele*/
--select public.stat_changed_forest_status_per_troop('3889fc5b-503f-495b-8f06-60c3e06cd8ae'); = LIL ST
--select public.stat_changed_forest_status_per_troop('460faca2-d7ae-499c-a972-09701d42de76'); = KT-Thünen Bayern
--select * from public.stat_changed_forest_status_per_troop('d4f08574-24f4-4c29-801a-f1d9bf9d38e0'); = LIL NW
--select * from public.stat_changed_forest_status_per_troop('460faca2-d7ae-499c-a972-09701d42de76'); = KT-Thünen Bayern
--select * from public.stat_changed_forest_status_per_troop('80980439-31fe-47b2-bbf3-312c2c06b90c'); = Thünen
--select * from public.stat_changed_forest_status_per_troop('cee0b61d-4e42-4ef0-b910-bc2388632a49'); = Thünen Los 3 Bayern Nord

--

/*Spalten der Ergebnistabelle*/
--Landesinventurleitung (lil)
--Trupp (troop_name)
--Kontrolltrupp? (kt)
--Anzahl_Änderung_Waldentscheid (aenderung_waldentscheid)
--Anzahl_Änderung_Begehbarkeit (aenderung_begehbar)

/*Angelegt am 2026-11-17 durch Thomas Riedel*/
/*Change-Log*/
-- 

/*Inhalt*/
--2.3 Statistik zu geändertem Waldentscheid gegenüber der Vorgängerinventur
--2.3.2 Statistik zu geändertem Waldentscheid gegenüber der Vorgängerinventur nach Anzahl pro Trupp
SELECT lil, troop_name, kt, sum(forest_status_change) as aenderung_waldentscheid, sum(accessibility_change) as aenderung_begehbar
  from (select --r.id,
               --r.responsible_state, 
               o.name as lil, 
               --r.cluster_id, 
               r.cluster_name, 
               r.plot_name, 
               --r.responsible_administration,
               --r.responsible_provider,
               --r.responsible_troop, 
               t.name as troop_name, 
               t.is_control_troop as kt, 
               --completed_at_survey_troop,
               case when properties ->>'forest_status' = previous_properties ->>'forest_status' then 0 else 1 end as forest_status_change,
               case when properties ->>'accessibility' = previous_properties ->>'accessibility' then 0 else 1 end as accessibility_change
          from public.view_records_details as r
          join public.troop as t
            on r.last_survey_troop = t.id
          join public.organizations as o
            on r.responsible_state = o.id
          join lookup.lookup_forest_status as a
            on r.properties ->>'forest_status' = a.code::text
          join lookup.lookup_forest_status as b
            on r.previous_properties ->>'forest_status' = b.code::text
          where cluster_name < 1000000000 and (cluster_name not between 9999900 and 10000000) 
            and last_survey_troop is not null and completed_at_survey_troop is not null 
            and (   r.responsible_administration::text = user_id 
                 or r.responsible_state::text = user_id 
                 or r.responsible_provider::text = user_id 
                 or r.last_survey_troop::text = user_id
                 or r.last_control_troop::text = user_id
                ) 
            and ( properties ->>'forest_status' <> previous_properties ->>'forest_status'
                 or properties ->>'accessibility' <> previous_properties ->>'accessibility')
        ) as z
group by lil, troop_name, kt
order by lil, troop_name, kt

$BODY$;

COMMENT ON FUNCTION public.stat_changed_forest_status_per_troop(text) IS
    'Statistik zu geänderten Waldentscheiden nach Anzahl Traktecken pro Trupp (Thomas Riedel, 2026-11-17). TFM-Documentation: components/statistics/PlotStatistics/...';

GRANT EXECUTE ON FUNCTION public.stat_changed_forest_status_per_troop(text) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

