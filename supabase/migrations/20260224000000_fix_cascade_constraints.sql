-- ============================================================================
-- Fix missing ON DELETE CASCADE constraints on inventory_archive child tables
-- ============================================================================
-- AMENDED 2026-09-03. Two defects were fixed in place; read this before
-- comparing the file against an older database.
--
-- 1. The three DROP CONSTRAINT statements on inventory_archive had no
--    IF EXISTS, so the file could only ever run once. On any database that had
--    not applied it exactly as written it failed on the first statement, which
--    is how it came to be half-applied on some.
--
-- 2. It originally set records/record_changes -> plot/cluster to
--    ON DELETE CASCADE. That is the configuration that cascade-deleted ~80k
--    collected records during a Schulungstrakte re-import, and
--    20260617000000_records_fk_restrict.sql exists solely to change it to
--    ON DELETE RESTRICT.
--
--    Because migrations are applied one transaction per file, any database
--    behind on both would be left armed with CASCADE for as long as it took
--    the next file to run — and indefinitely if that file failed. Those four
--    constraints are therefore created RESTRICT here directly. The end state is
--    unchanged: 20260617000000 sets exactly the same thing and is idempotent,
--    so it remains a no-op on top of this.
--
-- The inventory_archive cascades below are NOT affected by any of that. They
-- are this migration's actual purpose: deleting a plot, tree or edge is meant
-- to take its coordinate rows with it.
-- ============================================================================
-- subplots_relative_position_coordinates -> subplots_relative_position
ALTER TABLE inventory_archive.subplots_relative_position_coordinates DROP CONSTRAINT IF EXISTS subplots_relative_position_co_subplots_relative_position_i_fkey;
ALTER TABLE inventory_archive.subplots_relative_position_coordinates
ADD CONSTRAINT subplots_relative_position_co_subplots_relative_position_i_fkey FOREIGN KEY (subplots_relative_position_id) REFERENCES inventory_archive.subplots_relative_position (id) ON DELETE CASCADE;
-- tree_coordinates -> tree
ALTER TABLE inventory_archive.tree_coordinates DROP CONSTRAINT IF EXISTS tree_coordinates_tree_id_fkey;
ALTER TABLE inventory_archive.tree_coordinates
ADD CONSTRAINT tree_coordinates_tree_id_fkey FOREIGN KEY (tree_id) REFERENCES inventory_archive.tree (id) ON DELETE CASCADE;
-- edges_coordinates -> edges
ALTER TABLE inventory_archive.edges_coordinates DROP CONSTRAINT IF EXISTS edges_coordinates_edge_id_fkey;
ALTER TABLE inventory_archive.edges_coordinates
ADD CONSTRAINT edges_coordinates_edge_id_fkey FOREIGN KEY (edge_id) REFERENCES inventory_archive.edges (id) ON DELETE CASCADE;
-- plot -> cluster (fix missing ON DELETE CASCADE from inline REFERENCES)
ALTER TABLE inventory_archive.plot DROP CONSTRAINT IF EXISTS plot_cluster_id_fkey;
ALTER TABLE inventory_archive.plot
ADD CONSTRAINT plot_cluster_id_fkey FOREIGN KEY (cluster_id) REFERENCES inventory_archive.cluster (id) ON DELETE CASCADE;
-- ── records / record_changes: RESTRICT, never CASCADE — see the header ───────
-- A re-import must upsert in place. Deleting a plot or cluster that a record
-- still points at has to fail loudly instead of eating collected field data.
-- records -> plot
ALTER TABLE public.records DROP CONSTRAINT IF EXISTS records_plot_id_fkey;
ALTER TABLE public.records
ADD CONSTRAINT records_plot_id_fkey FOREIGN KEY (plot_id) REFERENCES inventory_archive.plot (id) ON DELETE RESTRICT;
-- records -> cluster
ALTER TABLE public.records DROP CONSTRAINT IF EXISTS records_cluster_id_fkey;
ALTER TABLE public.records
ADD CONSTRAINT records_cluster_id_fkey FOREIGN KEY (cluster_id) REFERENCES inventory_archive.cluster (id) ON DELETE RESTRICT;
-- record_changes -> plot (inherits records FKs via LIKE INCLUDING ALL)
ALTER TABLE public.record_changes DROP CONSTRAINT IF EXISTS record_changes_plot_id_fkey;
ALTER TABLE public.record_changes
ADD CONSTRAINT record_changes_plot_id_fkey FOREIGN KEY (plot_id) REFERENCES inventory_archive.plot (id) ON DELETE RESTRICT;
-- record_changes -> cluster
ALTER TABLE public.record_changes DROP CONSTRAINT IF EXISTS record_changes_cluster_id_fkey;
ALTER TABLE public.record_changes
ADD CONSTRAINT record_changes_cluster_id_fkey FOREIGN KEY (cluster_id) REFERENCES inventory_archive.cluster (id) ON DELETE RESTRICT;
