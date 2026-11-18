-- ============================================================================
-- MIGRATION: RPC-Funktion stat_list_of_shrinked_trees_per_at
-- ============================================================================
-- Angelegt am 2026-11-17 durch Thomas Riedel.
-- Prozedur liefert Liste mit Bäumen mit geschrumpftem BHD pro Aufnahmetrupp
-- Genutzt in TFM-Documentation:
--   components/statistics/PlotStatistics/
-- ============================================================================

SET search_path TO public, extensions;

--drop FUNCTION public.stat_list_of_shrinked_trees_per_at(text);

CREATE OR REPLACE FUNCTION public.stat_list_of_shrinked_trees_per_at(
    user_id text
)
RETURNS TABLE (
    landesinventurleitung text,
    cluster_name integer,
    plot_name smallint,
    troop_name text,
    kt boolean,
    abgabedatum_at timestamp with time zone,
    baumnummer27 integer,
    bdh27 integer,
    baumnummer22 integer,
    bhd22 integer,
    differenz integer
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
--select public.stat_list_of_shrinked_trees_per_at('3889fc5b-503f-495b-8f06-60c3e06cd8ae'); = LIL ST
--select public.stat_list_of_shrinked_trees_per_at('460faca2-d7ae-499c-a972-09701d42de76'); = KT-Thünen Bayern
--select * from public.stat_list_of_shrinked_trees_per_at('d4f08574-24f4-4c29-801a-f1d9bf9d38e0'); = LIL NW
--select * from public.stat_list_of_shrinked_trees_per_at('460faca2-d7ae-499c-a972-09701d42de76'); = KT-Thünen Bayern
--select * from public.stat_list_of_shrinked_trees_per_at('b676a934-243d-4589-8cd1-be89a4fae758'); = Thünen Los 3 Bayern Nord

--

/*Spalten der Ergebnistabelle*/
--Landesinventurleitung (lil)
--Trupp (troop_name)
--Anzahl_geschrumpfter_Bäume

/*Angelegt am 2026-11-17 durch Thomas Riedel*/
/*Change-Log*/
-- 

/*Inhalt*/
--4. Baumstatistiken
--4.1 Bäume mit geschrumpften BHDs pro AT
select *
  from (select o.name::text as lil,
               r.cluster_name,
               r.plot_name,
               cast(t.name as text) as troop_name,
               t.is_control_troop as kt, 
               r.completed_at_survey_troop,
               --r.properties -> 'tree' as tree,
               (t27.elem ->> 'tree_number')::integer as tree_id27,
               (t27.elem ->> 'dbh')::integer as dbh27,
               (t22.elem ->> 'tree_number')::integer as tree_id22,
               (t22.elem ->> 'dbh')::integer as dbh22,
               (t27.elem ->> 'dbh')::integer - (t22.elem ->> 'dbh')::integer as differenz
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
          join lateral jsonb_array_elements(
            case 
              when jsonb_typeof(r.previous_properties -> 'tree') = 'array' then r.previous_properties -> 'tree'
              when jsonb_typeof(r.previous_properties -> 'tree') = 'object' then jsonb_build_array(r.previous_properties -> 'tree')
              else '[]'::jsonb
            end
          ) as t22(elem)
            on (t27.elem ->> 'id') = (t22.elem ->> 'id')
         where r.cluster_name < 1000000000 and (r.cluster_name not between 9999900 and 10000000) 
           and r.last_survey_troop is not null and r.completed_at_survey_troop is not null
             and (   r.responsible_administration::text = user_id 
                  or r.responsible_state::text = user_id 
                  or r.responsible_provider::text = user_id 
                  or r.last_survey_troop::text = user_id
                  or r.last_control_troop::text = user_id
                 )
      ) as a
 where dbh27 > 0
   and dbh22 > 0
   and dbh27 <= dbh22
 order by lil;
$BODY$;

COMMENT ON FUNCTION public.stat_list_of_shrinked_trees_per_at(text) IS
    'Statistik Liste der Bäume mit geschrumpftem BHD pro Inventurtrupp (Thomas Riedel, 2026-111-18). TFM-Documentation: components/statistics/...';

GRANT EXECUTE ON FUNCTION public.stat_list_of_shrinked_trees_per_at(text) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

