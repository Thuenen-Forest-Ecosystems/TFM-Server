select count(*) 
from inventory_archive.plot p
join inventory_archive.structure_lt4m s
on p.id = s.plot_id
where interval_name = 'bwi2012'