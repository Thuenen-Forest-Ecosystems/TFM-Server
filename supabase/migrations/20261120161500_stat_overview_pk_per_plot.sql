-- ============================================================================
-- MIGRATION: RPC-Funktion stat_overview_pk_per_plot
-- ============================================================================
-- Angelegt am 2026-11-20 durch Thomas Riedel.
-- Prozedur liefert Überblick zur Anzahl der PKs pro Plot
-- Genutzt in TFM-Documentation:
--   components/statistics/PlotStatistics/
-- ============================================================================

SET search_path TO public, extensions;

--drop FUNCTION public.stat_overview_pk_per_plot(text);

CREATE OR REPLACE FUNCTION public.stat_overview_pk_per_plot(
    user_id text
)
RETURNS TABLE (
    landesinventurleitung text,
    cluster_name integer,
    plot_name smallint,
    troop_name text,
    kt boolean,
    abgabedatum_at timestamp with time zone,
    PK_0 integer,
    PK_1 integer,
    PK_4 integer,
    PK_5 integer,
    PK_5_genutzt integer,
    PK_6 integer,
    PK_8 integer,
    PK_9 integer,
    PK_10 integer,
    PK_11 integer,
    PK_12 integer,
    PK_1111 integer,
    PK_1987 integer,
    PK_2002 integer,
    PK_2008 integer,
    PK_2012 integer,
    PK_2017 integer,
    PK_2022 integer
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
--select public.stat_overview_pk_per_plot('3889fc5b-503f-495b-8f06-60c3e06cd8ae'); = LIL ST
--select public.stat_overview_pk_per_plot('460faca2-d7ae-499c-a972-09701d42de76'); = KT-Thünen Bayern
--select * from public.stat_overview_pk_per_plot('d4f08574-24f4-4c29-801a-f1d9bf9d38e0'); = LIL NW
--select * from public.stat_overview_pk_per_plot('460faca2-d7ae-499c-a972-09701d42de76'); = KT-Thünen Bayern
--select * from public.stat_overview_pk_per_plot('b676a934-243d-4589-8cd1-be89a4fae758'); = Thünen Los 3 Bayern Nord

--

/*Spalten der Ergebnistabelle*/
--Landesinventurleitung (lil)
--Trupp (troop_name)
--PK_0,
--PK_1,
--PK_4,
--PK_5,
--PK_5_genutzt,
--PK_6,
--PK_8,
--PK_9,
--PK_10,
--PK_11,
--PK_12,
--PK_1111,
--PK_1987,
--PK_2002,
--PK_2008,
--PK_2012,
--PK_2017,
--PK_2022

/*Angelegt am 2026-11-17 durch Thomas Riedel*/
/*Change-Log*/
-- 

/*Inhalt*/
--4. Baumstatistiken
--4.3 Auftretende PKs pro Plot
select lil, cluster_name, plot_name, troop_name, kt, completed_at_survey_troop as abgabedatum,
       sum(case when tree_status = 0 then 1 else 0 end) as PK_0,
       sum(case when tree_status = 1 then 1 else 0 end) as PK_1,
       sum(case when tree_status = 4 then 1 else 0 end) as PK_4,
       sum(case when tree_status = 5 and deadwood_used is FALSE then 1 else 0 end) as PK_5,
       sum(case when tree_status = 5 and deadwood_used is TRUE then 1 else 0 end) as PK_5_genutzt,
       sum(case when tree_status = 6 then 1 else 0 end) as PK_6,
       sum(case when tree_status = 8 then 1 else 0 end) as PK_8,
       sum(case when tree_status = 9 then 1 else 0 end) as PK_9,
       sum(case when tree_status = 10 then 1 else 0 end) as PK_10,
       sum(case when tree_status = 11 then 1 else 0 end) as PK_11,
       sum(case when tree_status = 12 then 1 else 0 end) as PK_12,
       sum(case when tree_status = 1111 then 1 else 0 end) as PK_1111,
       sum(case when tree_status = 1987 then 1 else 0 end) as PK_1987,
       sum(case when tree_status = 2002 then 1 else 0 end) as PK_2002,
       sum(case when tree_status = 2008 then 1 else 0 end) as PK_2008,
       sum(case when tree_status = 2012 then 1 else 0 end) as PK_2012,
       sum(case when tree_status = 2017 then 1 else 0 end) as PK_2017,
       sum(case when tree_status = 2022 then 1 else 0 end) as PK_2022
  from (select o.name::text as lil,
               r.cluster_name,
               r.plot_name,
               cast(t.name as text) as troop_name,
               t.is_control_troop as kt, 
               r.completed_at_survey_troop,
               r.properties -> 'tree' as tree,
               (t27.elem ->> 'tree_status')::integer as tree_status,
               (t27.elem ->> 'deadwood_used')::boolean as deadwood_used
          from public.view_records_details r
          join public.organizations o
            on r.responsible_state = o.id
          join public.troop t
            on r.last_survey_troop = t.id
          cross join lateral jsonb_array_elements(
            case 
              when jsonb_typeof(r.properties -> 'tree') = 'array' then r.properties -> 'tree'
              when jsonb_typeof(r.properties -> 'tree') = 'object' then jsonb_build_array(r.properties -> 'tree')
              else '[]'::jsonb
            end
          ) as t27(elem)
         where r.cluster_name < 1000000000 and (r.cluster_name not between 9999900 and 10000000) 
           and r.last_survey_troop is not null and r.completed_at_survey_troop is not null
             and (   r.responsible_administration::text = user_id 
                  or r.responsible_state::text = user_id 
                  or r.responsible_provider::text = user_id 
                  or r.last_survey_troop::text = user_id
                  or r.last_control_troop::text = user_id
                 )
      ) as a
 group by lil, cluster_name, plot_name, troop_name, kt, completed_at_survey_troop
 order by lil, cluster_name, plot_name;
$BODY$;

COMMENT ON FUNCTION public.stat_overview_pk_per_plot(text) IS
    'Statistik zum Auftreten (Anzahl) der PKs pro Plot (Thomas Riedel, 2026-111-18). TFM-Documentation: components/statistics/...';

GRANT EXECUTE ON FUNCTION public.stat_overview_pk_per_plot(text) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

