-- create table test(
--     id uuid not null default gen_random_uuid() primary key,
--     name text not null,
--     created_at timestamptz not null default now(),
--     updated_at timestamptz not null default now()
-- )
select count(*) from (
select prop.tree_id,
	prop.cluster_name, 
	prop.plot_name, 
	prop.tree_number,
	prop.tree_status,
	prop.dbh,
	prop.deprecated,
	pl.acquisition_date
from (
	select
		(jsonb_array_elements(properties -> 'tree') ->> 'id')::uuid as tree_id,
		cluster_name, 
		plot_name,	
		jsonb_array_elements(properties -> 'tree') -> 'tree_number' as tree_number,
		jsonb_array_elements(properties -> 'tree') -> 'tree_status' as tree_status,
		jsonb_array_elements(properties -> 'tree') -> 'dbh' as dbh,
		jsonb_array_elements(properties -> 'tree') -> '_deprecated' as deprecated
	from public.records
) as prop
left outer join (
	select
		(jsonb_array_elements(previous_properties -> 'tree') ->> 'id')::uuid as tree_id		
	from public.records
) as prev
on prop.tree_id = prev.tree_id
join inventory_archive.tree t
on t.id = prop.tree_id
join inventory_archive.plot pl
on t.plot_id = pl.id
where prev.tree_id is null and deprecated is null
order by cluster_name, plot_name, tree_number
) as kram 