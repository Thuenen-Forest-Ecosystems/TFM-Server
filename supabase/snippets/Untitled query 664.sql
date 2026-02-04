SELECT 
    c.cluster_name,
    p.plot_name,
    c.is_training,
    t.tree_number,
    t.tree_species,
    ts.name_de as tree_species_name,
    t.dbh,
    t.dbh_height,
    t.tree_height,
    t.azimuth,
    t.distance,
    t.tree_status
FROM 
    inventory_archive.cluster c
INNER JOIN 
    inventory_archive.plot p ON p.cluster_id = c.id
INNER JOIN 
    inventory_archive.tree t ON t.plot_id = p.id
LEFT JOIN 
    lookup.lookup_tree_species ts ON ts.code = t.tree_species
WHERE 
    c.is_training = TRUE
ORDER BY 
    c.cluster_name, p.plot_name, t.tree_number;