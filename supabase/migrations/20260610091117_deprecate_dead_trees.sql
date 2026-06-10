-- ============================================================================
-- FUNCTION: deprecate_harvested_trees  (bulk discovery wrapper)
-- ============================================================================
-- Finds all trees with tree_status = 4, 5 (dead trees) and from the inventories 
-- 2012 and 2017 then delegates to set_trees_to_deprecated.
--
-- A tree is a candidate when:
--   1. It has a tree_status of 4, 5
--	 2.	It is from the inventories of 2012 an 2017
--   3. Its current record entry has dbh = JSON null (not yet measured)
--   4. cluster_name < 9999900 (exclude test clusters)
--
-- Parameters:
--   p_dry_run for test run
--
-- Returns: number of records updated
-- ============================================================================
CREATE OR REPLACE FUNCTION public.deprecate_dead_trees(
  p_dry_run       boolean DEFAULT false
) RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_catalog
AS $$
DECLARE
  v_ids text[];
BEGIN
  SELECT array_agg(DISTINCT w.archive_tree_id)
  INTO v_ids
  FROM (
    SELECT t.id::text AS archive_tree_id, p.cluster_name, p.plot_name, t.tree_number
    FROM inventory_archive.plot p
    JOIN inventory_archive.tree t ON p.id = t.plot_id
    WHERE t.tree_status in (4, 5) and p.interval_name in ('bwi2012', 'ci2017')
  ) w
  -- Pre-filter: only trees that actually appear with null dbh in records
  INNER JOIN (
    SELECT elem ->> 'id' AS tree_id
    FROM public.records r
    CROSS JOIN LATERAL jsonb_array_elements(r.properties -> 'tree') AS elem
    WHERE r.cluster_name < 9999900
      AND (elem -> 'dbh') = 'null'::jsonb
  ) rec ON w.archive_tree_id = rec.tree_id;

  IF v_ids IS NULL THEN
    RETURN 0;
  END IF;

  RETURN public.set_trees_to_deprecated(v_ids, p_dry_run);
END;
$$;

REVOKE ALL ON FUNCTION public.deprecate_dead_trees(boolean) FROM PUBLIC;

-- ============================================================================
-- FUNCTION: deprecate_dead_trees_preview  (dry-run row output)
-- ============================================================================
-- Same selection logic as deprecate_harvested_trees but returns one row per
-- affected tree instead of a count. Use before the real run to inspect results.
--
-- Usage:
--   SELECT * FROM deprecate_dead_trees();
-- ============================================================================
CREATE OR REPLACE FUNCTION public.deprecate_dead_trees_preview(  
) RETURNS TABLE (
  cluster_name      integer,
  plot_name         smallint,
  tree_number       integer,
  tree_species      text,
  archive_tree_id   text,
  record_id         uuid
)
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, pg_catalog
AS $$
  SELECT
    w.cluster_name,
    w.plot_name::smallint,
    w.tree_number,
    w.tree_species,
    w.archive_tree_id,
    r.id AS record_id
  FROM (
    SELECT t.id::text AS archive_tree_id, p.cluster_name, p.plot_name, t.tree_number, t.tree_species::text
    FROM inventory_archive.plot p
    JOIN inventory_archive.tree t ON p.id = t.plot_id
    WHERE t.tree_status in (4, 5) and p.interval_name in ('bwi2012', 'ci2017')
  ) w
  -- Pre-filter: only trees that actually appear with null dbh in records
  INNER JOIN (
    SELECT elem ->> 'id' AS tree_id, r.id AS record_id
    FROM public.records r
    CROSS JOIN LATERAL jsonb_array_elements(r.properties -> 'tree') AS elem
    WHERE r.cluster_name < 9999900
      AND (elem -> 'dbh') = 'null'::jsonb
  ) rec ON w.archive_tree_id = rec.tree_id
  INNER JOIN public.records r ON r.id = rec.record_id
  ORDER BY w.cluster_name, w.plot_name, w.tree_number;
$$;

REVOKE ALL ON FUNCTION public.deprecate_dead_trees_preview() FROM PUBLIC;
