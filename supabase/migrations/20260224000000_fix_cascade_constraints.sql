-- Fix missing ON DELETE CASCADE constraints
-- subplots_relative_position_coordinates -> subplots_relative_position
ALTER TABLE inventory_archive.subplots_relative_position_coordinates DROP CONSTRAINT subplots_relative_position_co_subplots_relative_position_i_fkey;
ALTER TABLE inventory_archive.subplots_relative_position_coordinates
ADD CONSTRAINT subplots_relative_position_co_subplots_relative_position_i_fkey FOREIGN KEY (subplots_relative_position_id) REFERENCES inventory_archive.subplots_relative_position (id) ON DELETE CASCADE;
-- tree_coordinates -> tree
ALTER TABLE inventory_archive.tree_coordinates DROP CONSTRAINT tree_coordinates_tree_id_fkey;
ALTER TABLE inventory_archive.tree_coordinates
ADD CONSTRAINT tree_coordinates_tree_id_fkey FOREIGN KEY (tree_id) REFERENCES inventory_archive.tree (id) ON DELETE CASCADE;
-- edges_coordinates -> edges
ALTER TABLE inventory_archive.edges_coordinates DROP CONSTRAINT edges_coordinates_edge_id_fkey;
ALTER TABLE inventory_archive.edges_coordinates
ADD CONSTRAINT edges_coordinates_edge_id_fkey FOREIGN KEY (edge_id) REFERENCES inventory_archive.edges (id) ON DELETE CASCADE;
-- plot -> cluster (fix missing ON DELETE CASCADE from inline REFERENCES)
ALTER TABLE inventory_archive.plot DROP CONSTRAINT IF EXISTS plot_cluster_id_fkey;
ALTER TABLE inventory_archive.plot
ADD CONSTRAINT plot_cluster_id_fkey FOREIGN KEY (cluster_id) REFERENCES inventory_archive.cluster (id) ON DELETE CASCADE;
-- records -> plot (fix missing ON DELETE CASCADE)
ALTER TABLE public.records DROP CONSTRAINT IF EXISTS records_plot_id_fkey;
ALTER TABLE public.records
ADD CONSTRAINT records_plot_id_fkey FOREIGN KEY (plot_id) REFERENCES inventory_archive.plot (id) ON DELETE CASCADE;
-- records -> cluster (fix missing ON DELETE CASCADE on direct cluster reference)
ALTER TABLE public.records DROP CONSTRAINT IF EXISTS records_cluster_id_fkey;
ALTER TABLE public.records
ADD CONSTRAINT records_cluster_id_fkey FOREIGN KEY (cluster_id) REFERENCES inventory_archive.cluster (id) ON DELETE CASCADE;
-- record_changes -> plot (inherits records FKs via LIKE INCLUDING ALL, also needs CASCADE)
ALTER TABLE public.record_changes DROP CONSTRAINT IF EXISTS record_changes_plot_id_fkey;
ALTER TABLE public.record_changes
ADD CONSTRAINT record_changes_plot_id_fkey FOREIGN KEY (plot_id) REFERENCES inventory_archive.plot (id) ON DELETE CASCADE;
-- record_changes -> cluster (fix missing ON DELETE CASCADE)
ALTER TABLE public.record_changes DROP CONSTRAINT IF EXISTS record_changes_cluster_id_fkey;
ALTER TABLE public.record_changes
ADD CONSTRAINT record_changes_cluster_id_fkey FOREIGN KEY (cluster_id) REFERENCES inventory_archive.cluster (id) ON DELETE CASCADE;