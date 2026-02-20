ALTER TABLE inventory_archive.plot
  DROP CONSTRAINT plot_cluster_id_fkey,
  ADD CONSTRAINT plot_cluster_id_fkey
    FOREIGN KEY (cluster_id) REFERENCES inventory_archive.cluster(id) ON DELETE CASCADE;

DELETE FROM inventory_archive.cluster WHERE cluster_name=9990001;