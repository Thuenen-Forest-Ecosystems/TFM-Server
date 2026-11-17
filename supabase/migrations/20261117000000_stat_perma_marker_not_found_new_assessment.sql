-- ============================================================================
-- MIGRATION: RPC-Funktion stat_perma_marker_not_found_new_assessment
-- ============================================================================
-- Angelegt am 2026-11-17 durch Thomas Riedel.
-- Prozedur liefert Überblick zu den Traktecken auf denen der Perma-Marker nicht
-- gefunden, die Traktecke auch nicht identifiziert wurde und somit neu erfasst
-- wurde.
-- Genutzt in TFM-Documentation:
--   components/statistics/PlotStatistics/
-- ============================================================================

SET search_path TO public, extensions;

CREATE OR REPLACE FUNCTION public.stat_perma_marker_not_found_new_assessment(
    user_id text
)
RETURNS TABLE (
    landesinventurleitung text,
    cluster_name integer,
    plot_name smallint,
    troop_name text,
    kontrolltrupp boolean,
    abgabedatum timestamp with time zone,
    Marker_Status text,
    Beschreibung text
)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $BODY$
/*Relevante Tabellen*/
--select * from public.organizations 
--select * from public.troop 
--select * from public.view_records_details

/*Inputparameter*/
--user_id wird der Funktion übergeben und gibt entweder den Trupp oder die Organisation an.
--Bezieht sich auf public.view_records_details: responsible_administration, responsible_state, responsible_provider oder last_survey_troop und completed_at_survey_troop.

/*Beispiele*/
--select public.stat_perma_marker_not_found_new_assessment('3889fc5b-503f-495b-8f06-60c3e06cd8ae'); = LIL ST
--select public.stat_perma_marker_not_found_new_assessment('460faca2-d7ae-499c-a972-09701d42de76'); = KT-Thünen Bayern
--select * from public.stat_perma_marker_not_found_new_assessment('d4f08574-24f4-4c29-801a-f1d9bf9d38e0'); = LIL NW
--select * from public.stat_perma_marker_not_found_new_assessment('460faca2-d7ae-499c-a972-09701d42de76'); = KT-Thünen Bayern
--select * from public.stat_perma_marker_not_found_new_assessment('b676a934-243d-4589-8cd1-be89a4fae758'); = Thünen Los 3 Bayern Nord

--

/*Spalten der Ergebnistabelle*/
--Landesinventurleitung (lil)
--Traktnummer (cluster_name)
--Eckennummer (plot_name)
--Trupp (troop_name)
--Kontrolltrupp? (kt)
--Abgabedatum (completed_at_troop)
--Marker_Status (marker_status)
--Beschreibung (beschreibung)

/*Angelegt am 2026-11-17 durch Thomas Riedel*/
/*Change-Log*/
-- 

/*Inhalt*/
--2.1 Statistik zu neu gesetzten Markierungen
--select * from lookup.lookup_marker_status
--2.1.2 Alle Ecken bei denen die Markierung erstmals neu gesetzt wurde
select --r.id,
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
       completed_at_survey_troop,
       properties ->>'marker_status' as marker_status,
       'alte Markierung nicht gefunden; Neuaufnahme' as beschreibung
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
    and properties ->>'marker_status'='4'
  order by o.name, r.cluster_name, r.plot_name

$BODY$;

COMMENT ON FUNCTION public.stat_perma_marker_not_found_new_assessment(text) IS
    'Statistik zu Ecken bei denen ein Perma-Marker nicht gefunden, die Ecke nicht identifiziert und daher neu aufgenommen wurde (Thomas Riedel, 2026-11-17). TFM-Documentation: components/statistics/PlotStatistics/...';

GRANT EXECUTE ON FUNCTION public.stat_perma_marker_not_found_new_assessment(text) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

