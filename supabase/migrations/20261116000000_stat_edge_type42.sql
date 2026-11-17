-- ============================================================================
-- MIGRATION: RPC-Funktion stat_edge_type42
-- ============================================================================
-- Angelegt am 2026-11-16 durch Thomas Riedel.
-- Prozedur liefert Überblick zu den Bestandesgrenzen mit Grenzart (edge_type) = 42
-- und zum Vorgelagerten Bestand (edge_stand_difference)
-- Genutzt in TFM-Documentation:
--   components/statistics/PlotStatistics/
-- ============================================================================

SET search_path TO public, extensions;

CREATE OR REPLACE FUNCTION public.stat_edge_type42(
    user_id text
)
RETURNS TABLE (
    landesinventurleitung text,
    cluster_name integer,
    plot_name smallint,
    troop_name text,
    kontrolltrupp boolean,
    abgabedatum timestamp with time zone,
    Grenznummer text,
    Grenzart text,
    Vorgelagerter_Bestand text,
    Vorgelagerter_Bestand_text text
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
--select public.stat_edge_type42('3889fc5b-503f-495b-8f06-60c3e06cd8ae'); = LIL ST
--select public.stat_edge_type42('460faca2-d7ae-499c-a972-09701d42de76'); = KT-Thünen Bayern
--select * from public.stat_edge_type42('cee0b61d-4e42-4ef0-b910-bc2388632a49'); = Thünen Los 4 Bayern Ost

/*Spalten der Ergebnistabelle*/
--Landesinventurleitung (lil)
--Traktnummer (cluster_name)
--Eckennummer (plot_name)
--Trupp (troop_name)
--Kontrolltrupp? (kt)
--Abgabedatum (completed_at_troop)
--Grenznummer (grenznummer),
--Grenzart (grenzart),
--Vorgelagerter_Bestand (vorgelagerter_bestand),
--Vorgelagerter_Bestand_text (vorgelagerter_bestand_text)

/*Angelegt am 2026-11-16 durch Thomas Riedel*/
/*Change-Log*/
-- 

/*Inhalt*/
--2.4 Statistik zu übernommenen Bestandesgrenzen mit Grenzart = 42
select a.*, e.name_de as vorgelagerter_bestand_text 
  from ( select --r.id,
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
                jsonb_array_elements(properties -> 'edges') -> 'edge_number' as grenznummer, 
                jsonb_array_elements(properties -> 'edges') -> 'edge_type' as grenzart, 
                jsonb_array_elements(properties -> 'edges') -> 'edge_stand_difference' as vorgelagerter_bestand
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
        ) as a
  join lookup.lookup_edge_stand_difference as e
    on a.vorgelagerter_bestand::text = e.code::text
  where a.grenzart = '42'
  order by lil, cluster_name, plot_name

$BODY$;

COMMENT ON FUNCTION public.stat_edge_type42(text) IS
    'Statistik zu übernommenen Bestandesgrenzen mit Grenzart = 42 (Thomas Riedel, 2026-11-16). TFM-Documentation: components/statistics/PlotStatistics/...';

GRANT EXECUTE ON FUNCTION public.stat_edge_type42(text) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';


