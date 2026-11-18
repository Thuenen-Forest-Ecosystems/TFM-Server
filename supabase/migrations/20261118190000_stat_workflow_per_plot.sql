-- ============================================================================
-- MIGRATION: RPC-Funktion stat_workflow_per_plot
-- ============================================================================
-- Angelegt am 2026-11-18 durch Thomas Riedel.
-- Prozedur liefert Überblick zum Workflow-Staus der Traktecken 
-- Genutzt in TFM-Documentation:
--   components/statistics/PlotStatistics/
-- ============================================================================

SET search_path TO public, extensions;

CREATE OR REPLACE FUNCTION public.stat_workflow_per_plot(
    user_id text
)
RETURNS TABLE (
    landesinventurleitung text,
    cluster_name integer,
    plot_name smallint,
    troop_name text,
    kontrolltrupp boolean,
    abgabedatum timestamp with time zone,
    workflow_code integer,
    workflow_code_text text,
    cartesian_x numeric,
    cartesian_y numeric
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
--select public.stat_workflow_per_plot('3889fc5b-503f-495b-8f06-60c3e06cd8ae'); = LIL ST
--select public.stat_workflow_per_plot('460faca2-d7ae-499c-a972-09701d42de76'); = KT-Thünen Bayern
--select * from public.stat_workflow_per_plot('d4f08574-24f4-4c29-801a-f1d9bf9d38e0'); = LIL NW
--select * from public.stat_workflow_per_plot('460faca2-d7ae-499c-a972-09701d42de76'); = KT-Thünen Bayern
--select * from public.stat_workflow_per_plot('b676a934-243d-4589-8cd1-be89a4fae758'); = Thünen Los 3 Bayern Nord

--

/*Spalten der Ergebnistabelle*/
--Landesinventurleitung (lil)
--Traktnummer (cluster_name)
--Eckennummer (plot_name)
--Trupp (troop_name)
--Kontrolltrupp? (kt)
--Abgabedatum (completed_at_troop)
--workflow_code
--workflow_code_text
--cartesian_x
--cartesian_y

/*Angelegt am 2026-11-18 durch Thomas Riedel*/
/*Change-Log*/
-- 

/*Inhalt*/
--2.3 Statistik zu geändertem Waldentscheid gegenüber der Vorgängerinventur
--2.3.1 Statistik zu geändertem Waldentscheid gegenüber der Vorgängerinventur nach Traktecken
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
       workflow_code,
       a.name_de as workflow_code_text,
       c.cartesian_x, c.cartesian_y
  from public.view_records_details as r
  join public.troop as t
    on r.last_survey_troop = t.id
  join public.organizations as o
    on r.responsible_state = o.id
  join lookup.lookup_workflow_status as a
    on r.workflow_code = a.code
  join inventory_archive.plot_coordinates as c
    on r.cluster_name = c.cluster_name and r.plot_name = c.plot_name
  where r.cluster_name < 1000000000 and (r.cluster_name not between 9999900 and 10000000) 
  and last_survey_troop is not null and completed_at_survey_troop is not null 
  and (   r.responsible_administration::text = user_id 
       or r.responsible_state::text = user_id 
       or r.responsible_provider::text = user_id 
       or r.last_survey_troop::text = user_id
       or r.last_control_troop::text = user_id
      )
  order by o.name, r.cluster_name, r.plot_name
$BODY$;

COMMENT ON FUNCTION public.stat_workflow_per_plot(text) IS
    'Statistik zum Workflow-Status nach Traktecken (Thomas Riedel, 2026-11-17). TFM-Documentation: components/statistics/PlotStatistics/...';

GRANT EXECUTE ON FUNCTION public.stat_workflow_per_plot(text) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

