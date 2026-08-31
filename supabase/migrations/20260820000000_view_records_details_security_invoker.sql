-- ============================================================================
-- FIX: view_records_details lost its security_invoker setting
-- ============================================================================
-- 20260617000000_records_fk_restrict.sql set
--     ALTER VIEW public.view_records_details SET (security_invoker = true);
-- but the view was afterwards DROPped and recreated in
--     20260709120000_control_troop_read_only.sql
--     20260714000000_read_only_troop.sql
-- DROP VIEW discards the reloption, so the view fell back to the Postgres
-- default (security_invoker = false) — i.e. it runs with the permissions and
-- RLS policies of its owner (postgres), not of the querying user. That is what
-- the Supabase linter reports as "defined with the SECURITY DEFINER property".
--
-- With security_invoker = true the RLS policies on public.records apply to the
-- caller again; the joined inventory_archive tables (plot, plot_coordinates,
-- cluster) grant SELECT to `authenticated` and carry permissive
-- default_select_ti_read_and_authenticated policies (20250115140841_rls.sql),
-- so the join side keeps working unchanged.
--
-- NOTE for future migrations: any DROP VIEW / CREATE VIEW of this view must
-- re-apply security_invoker (either via ALTER VIEW or
-- CREATE VIEW ... WITH (security_invoker = true)).

ALTER VIEW public.view_records_details SET (security_invoker = true);

REVOKE ALL ON public.view_records_details FROM PUBLIC;
REVOKE ALL ON public.view_records_details FROM anon;
GRANT SELECT ON public.view_records_details TO authenticated;
