-- ============================================================================
-- FIX: Stop inventory_archive re-imports from silently deleting user records
-- ============================================================================
-- 20260224000000_fix_cascade_constraints.sql set the records (and
-- record_changes) foreign keys to inventory_archive.plot / cluster to
-- ON DELETE CASCADE. As a result, deleting/replacing a cluster or plot during
-- a data re-import silently cascade-deletes every dependent public.records row
-- (and its record_changes audit trail) with no error — this destroyed ~80k
-- records during a Schulungstrakte re-import.
--
-- Switch these FKs to ON DELETE RESTRICT so that any attempt to delete a plot
-- or cluster that is still referenced by a record fails loudly instead of
-- eating collected field data. Re-imports must upsert in place (keeping the
-- same id) rather than delete-then-insert.
--
-- Affected constraints (original definitions):
--   records_plot_id_fkey, records_cluster_id_fkey,
--   record_changes_plot_id_fkey, record_changes_cluster_id_fkey
--     → 20260224000000_fix_cascade_constraints.sql
-- ============================================================================

-- records -> plot
ALTER TABLE public.records DROP CONSTRAINT IF EXISTS records_plot_id_fkey;
ALTER TABLE public.records
ADD CONSTRAINT records_plot_id_fkey FOREIGN KEY (plot_id) REFERENCES inventory_archive.plot (id) ON DELETE RESTRICT;

-- records -> cluster
ALTER TABLE public.records DROP CONSTRAINT IF EXISTS records_cluster_id_fkey;
ALTER TABLE public.records
ADD CONSTRAINT records_cluster_id_fkey FOREIGN KEY (cluster_id) REFERENCES inventory_archive.cluster (id) ON DELETE RESTRICT;

-- record_changes -> plot
ALTER TABLE public.record_changes DROP CONSTRAINT IF EXISTS record_changes_plot_id_fkey;
ALTER TABLE public.record_changes
ADD CONSTRAINT record_changes_plot_id_fkey FOREIGN KEY (plot_id) REFERENCES inventory_archive.plot (id) ON DELETE RESTRICT;

-- record_changes -> cluster
ALTER TABLE public.record_changes DROP CONSTRAINT IF EXISTS record_changes_cluster_id_fkey;
ALTER TABLE public.record_changes
ADD CONSTRAINT record_changes_cluster_id_fkey FOREIGN KEY (cluster_id) REFERENCES inventory_archive.cluster (id) ON DELETE RESTRICT;


ALTER VIEW public.plot_nested_json     SET (security_invoker = true);
ALTER VIEW public.view_records_details SET (security_invoker = true);
