
--Achtung nur in der lokalen Instanz ausführen, da die Funktion public.add_plot_ids_to_records() die Datenbank löscht

select schema_id,count(schema_id) from public.records group by schema_id;

SELECT public.add_plot_ids_to_records('47315630-06dd-470b-b550-21faffb7878e', 1000);


SELECT public.fill_previous_properties(NULL, 500);     -- all records, batch size 500

SELECT public.fill_properties(NULL, 500); 

SELECT public.deprecate_out_of_zone_trees();

SELECT public.deprecate_dead_trees();

SELECT public.deprecate_harvested_trees();

SELECT * FROM public.deprecate_harvested_trees_preview();
SELECT public.deprecate_harvested_trees(TRUE);  -- dry run, returns count only