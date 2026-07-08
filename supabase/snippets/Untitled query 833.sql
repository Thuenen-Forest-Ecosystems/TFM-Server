SELECT DISTINCT
    c.cluster_name,
    p.plot_name
FROM inventory_archive.cluster c
JOIN inventory_archive.plot p ON p.cluster_id = c.id
JOIN inventory_archive.tree t ON t.plot_id = p.id
WHERE c.is_training = TRUE
  AND t.dbh IS NOT NULL;

SELECT count(*) FROM inventory_archive.cluster WHERE cluster.is_training = TRUE;