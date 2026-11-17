-- ============================================================================
-- MIGRATION: RPC-Funktion stat_not_accessible_ASP
-- ============================================================================
-- Angelegt am 2026-11-16 durch Thomas Riedel.
-- Prozedur liefert Überblick zu den nicht begehbaren Traktecken
-- aufgrund von Afrikanischer Schweinepest (ASP)
-- Genutzt in TFM-Documentation:
--   components/statistics/PlotStatistics/
-- ============================================================================

SET search_path TO public, extensions;

CREATE OR REPLACE FUNCTION public.stat_not_accessible_ASP(
    user_id text
)
RETURNS TABLE (
    landesinventurleitung text,
    cluster_name integer,
    plot_name smallint,
    troop_name text,
    kontrolltrupp boolean,
    abgabedatum timestamp with time zone,
    Wald2027 text, 
    Wald2027_text text,
    Wald_Vorgängerinventur text, 
    Wald_Vorgängerinventur_text text,
    Begehbarkeit2027 text,
    Begehbarkeit2027_text text
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
--select public.stat_not_accessible_ASP('3889fc5b-503f-495b-8f06-60c3e06cd8ae'); = LIL ST
--select public.stat_not_accessible_ASP('460faca2-d7ae-499c-a972-09701d42de76'); = KT-Thünen Bayern
--select public.stat_not_accessible_ASP('80980439-31fe-47b2-bbf3-312c2c06b90c'); = Thünen

--

/*Spalten der Ergebnistabelle*/
--Landesinventurleitung (lil)
--Traktnummer (cluster_name)
--Eckennummer (plot_name)
--Trupp (troop_name)
--Kontrolltrupp? (kt)
--Abgabedatum (completed_at_troop)
--Wald2027 (wald2027), 
--Wald2027_text (wald2027_text),
--Wald_Vorgängerinventur (wald_vorgaenger), 
--Wald_Vorgängerinventur_text (wald_vorgaenger_text),
--Begehbarkeit2027 (begehbar2027),
--Begehbarkeit2027_text (begehbarkeit_text)

/*Angelegt am 2026-11-16 durch Thomas Riedel*/
/*Change-Log*/
-- 

/*Inhalt*/
--2.5 Statistik zu nicht begehbaren Traktecken wegen ASP
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
       properties ->>'forest_status' as wald2027, a.name_de as wald2027_text,
       previous_properties ->>'forest_status' as wald_vorgaenger, b.name_de as wald_vorgaenger_text,
       properties ->>'accessibility' as begehbar2027,
       c.name_de as begehbarkeit_text
  from public.view_records_details as r
  join public.troop as t
    on r.last_survey_troop = t.id
  join public.organizations as o
    on r.responsible_state = o.id
  join lookup.lookup_forest_status as a
    on r.properties ->>'forest_status' = a.code::text
  join lookup.lookup_forest_status as b
    on r.previous_properties ->>'forest_status' = b.code::text
  join lookup.lookup_accessibility as c
    on r.previous_properties ->>'accessibility' = c.code::text
  where cluster_name < 1000000000 and (cluster_name not between 9999900 and 10000000) 
    and last_survey_troop is not null and completed_at_survey_troop is not null 
    and (   r.responsible_administration::text = user_id 
         or r.responsible_state::text = user_id 
         or r.responsible_provider::text = user_id 
         or r.last_survey_troop::text = user_id
         or r.last_control_troop::text = user_id
        )
    and properties ->>'accessibility' = 10::text 
  order by o.name, r.cluster_name, r.plot_name

$BODY$;

COMMENT ON FUNCTION public.stat_not_accessible_ASP(text) IS
    'Statistik zu nicht begehbaren Traktecken wegen ASP (Thomas Riedel, 2026-11-16). TFM-Documentation: components/statistics/PlotStatistics/...';

GRANT EXECUTE ON FUNCTION public.stat_not_accessible_ASP(text) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

