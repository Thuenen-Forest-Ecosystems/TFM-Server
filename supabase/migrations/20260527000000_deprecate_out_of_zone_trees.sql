-- ============================================================================
-- FUNCTION: set_trees_to_deprecated  (core — single UPDATE owner)
-- ============================================================================
-- Marks every tree whose archive UUID is in p_tree_ids as _deprecated = true
-- inside public.records.properties->'tree'.
-- Rebuilds the full array in one pass so multiple hits per record are handled.
--
-- Parameters:
--   p_tree_ids  array of inventory_archive.tree UUIDs (as text)
--
-- Returns: number of records updated
-- ============================================================================
CREATE OR REPLACE FUNCTION public.set_trees_to_deprecated(
  p_tree_ids  text[],
  p_dry_run   boolean DEFAULT false
) RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_catalog
AS $$
DECLARE
  v_updated integer := 0;
BEGIN
  IF p_dry_run THEN
    -- Count records that would be affected without touching any data
    SELECT COUNT(DISTINCT r.id)
    INTO v_updated
    FROM public.records r
    CROSS JOIN LATERAL jsonb_array_elements(r.properties -> 'tree') AS elem
    WHERE (elem ->> 'id') = ANY(p_tree_ids)
      AND COALESCE((elem ->> '_deprecated')::boolean, false) = false;
  ELSE
    UPDATE public.records r
    SET
      properties       = (
        SELECT jsonb_set(
                 r.properties,
                 '{tree}',
                 jsonb_agg(
                   CASE
                     WHEN (elem ->> 'id') = ANY(p_tree_ids)
                       AND COALESCE((elem ->> '_deprecated')::boolean, false) = false
                     THEN jsonb_set(elem, '{_deprecated}', 'true', true)
                     ELSE elem
                   END
                   ORDER BY ordinality
                 )
               )
        FROM jsonb_array_elements(r.properties -> 'tree')
               WITH ORDINALITY AS t(elem, ordinality)
      ),
      local_updated_at = now()
    WHERE EXISTS (
      SELECT 1
      FROM jsonb_array_elements(r.properties -> 'tree') AS elem
      WHERE (elem ->> 'id') = ANY(p_tree_ids)
        AND COALESCE((elem ->> '_deprecated')::boolean, false) = false
    );

    GET DIAGNOSTICS v_updated = ROW_COUNT;
  END IF;

  RETURN v_updated;
END;
$$;

REVOKE ALL ON FUNCTION public.set_trees_to_deprecated(text[], boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_trees_to_deprecated(text[], boolean) TO authenticated;


-- ============================================================================
-- FUNCTION: set_tree_to_deprecated  (ad-hoc single-tree wrapper)
-- ============================================================================
-- Looks up all archive UUIDs for the given (cluster, plot, tree_number)
-- across all inventory intervals, then delegates to set_trees_to_deprecated.
-- Use this for targeted one-off fixes on a specific tree.
--
-- Returns: number of records updated
-- ============================================================================
CREATE OR REPLACE FUNCTION public.set_tree_to_deprecated(
  p_cluster_name integer,
  p_plot_name    integer,
  p_tree_number  integer,
  p_dry_run      boolean DEFAULT false
) RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_catalog
AS $$
DECLARE
  v_ids text[];
BEGIN
  SELECT array_agg(t.id::text)
  INTO v_ids
  FROM inventory_archive.plot p
  JOIN inventory_archive.tree t ON p.id = t.plot_id
  WHERE p.cluster_name = p_cluster_name
    AND p.plot_name    = p_plot_name
    AND t.tree_number  = p_tree_number;

  IF v_ids IS NULL THEN
    RETURN 0;
  END IF;

  RETURN public.set_trees_to_deprecated(v_ids, p_dry_run);
END;
$$;

REVOKE ALL ON FUNCTION public.set_tree_to_deprecated(int, int, int, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_tree_to_deprecated(int, int, int, boolean) TO authenticated;


-- ============================================================================
-- FUNCTION: deprecate_out_of_zone_trees  (bulk discovery wrapper)
-- ============================================================================
-- Finds all trees that were recorded outside their angle-count inclusion zone
-- in bwi2012 and never re-appeared in ci2017 or bwi2022, then delegates to
-- set_trees_to_deprecated.
--
-- A tree is a candidate when:
--   1. It exists in bwi2012 with distance > dbh * 25 / 10 (outside inclusion zone)
--   2. It has NO matching entry in ci2017 (by cluster_name + plot_name + tree_number)
--   3. It has NO matching entry in bwi2022
--   4. Its current record entry has dbh = JSON null (not yet measured)
--   5. cluster_name < 9999900 (exclude test clusters)
--
-- Parameters:
--   p_federal_state  German federal state code (default 12 = Brandenburg)
--
-- Returns: number of records updated
-- ============================================================================
CREATE OR REPLACE FUNCTION public.deprecate_out_of_zone_trees(
  p_federal_state integer DEFAULT 12,
  p_dry_run       boolean DEFAULT false
) RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_catalog
AS $$
DECLARE
  v_ids text[];
BEGIN
  SELECT array_agg(DISTINCT w12.archive_tree_id)
  INTO v_ids
  FROM (
    SELECT t.id::text AS archive_tree_id, p.cluster_name, p.plot_name, t.tree_number
    FROM inventory_archive.plot p
    JOIN inventory_archive.tree t ON p.id = t.plot_id
    WHERE p.interval_name = 'bwi2012'
      AND p.federal_state = p_federal_state
      AND t.distance      > (t.dbh * 25.0 / 10)
  ) w12
  LEFT JOIN (
    SELECT p.cluster_name, p.plot_name, t.tree_number
    FROM inventory_archive.plot p
    JOIN inventory_archive.tree t ON p.id = t.plot_id
    WHERE p.interval_name = 'ci2017' AND p.federal_state = p_federal_state
  ) w17 ON w12.cluster_name = w17.cluster_name
       AND w12.plot_name    = w17.plot_name
       AND w12.tree_number  = w17.tree_number
  LEFT JOIN (
    SELECT p.cluster_name, p.plot_name, t.tree_number
    FROM inventory_archive.plot p
    JOIN inventory_archive.tree t ON p.id = t.plot_id
    WHERE p.interval_name = 'bwi2022' AND p.federal_state = p_federal_state
  ) w22 ON w12.cluster_name = w22.cluster_name
       AND w12.plot_name    = w22.plot_name
       AND w12.tree_number  = w22.tree_number
  -- Pre-filter: only trees that actually appear with null dbh in records
  INNER JOIN (
    SELECT elem ->> 'id' AS tree_id
    FROM public.records r
    CROSS JOIN LATERAL jsonb_array_elements(r.properties -> 'tree') AS elem
    WHERE r.cluster_name < 9999900
      AND (elem -> 'dbh') = 'null'::jsonb
  ) rec ON w12.archive_tree_id = rec.tree_id
  WHERE w17.tree_number IS NULL
    AND w22.tree_number IS NULL;

  IF v_ids IS NULL THEN
    RETURN 0;
  END IF;

  RETURN public.set_trees_to_deprecated(v_ids, p_dry_run);
END;
$$;

REVOKE ALL ON FUNCTION public.deprecate_out_of_zone_trees(int, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.deprecate_out_of_zone_trees(int, boolean) TO authenticated;


-- ============================================================================
-- FUNCTION: deprecate_out_of_zone_trees_preview  (dry-run row output)
-- ============================================================================
-- Same selection logic as deprecate_out_of_zone_trees but returns one row per
-- affected tree instead of a count. Use before the real run to inspect results.
--
-- Usage:
--   SELECT * FROM deprecate_out_of_zone_trees_preview(12);
--   SELECT * FROM deprecate_out_of_zone_trees_preview(12) WHERE cluster_name = 1000000065;
-- ============================================================================
CREATE OR REPLACE FUNCTION public.deprecate_out_of_zone_trees_preview(
  p_federal_state integer DEFAULT 12
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
    w12.cluster_name,
    w12.plot_name::smallint,
    w12.tree_number,
    w12.tree_species,
    w12.archive_tree_id,
    r.id AS record_id
  FROM (
    SELECT t.id::text AS archive_tree_id, p.cluster_name, p.plot_name, t.tree_number, t.tree_species::text
    FROM inventory_archive.plot p
    JOIN inventory_archive.tree t ON p.id = t.plot_id
    WHERE p.interval_name = 'bwi2012'
      AND p.federal_state = p_federal_state
      AND t.distance      > (t.dbh * 25.0 / 10)
  ) w12
  LEFT JOIN (
    SELECT p.cluster_name, p.plot_name, t.tree_number
    FROM inventory_archive.plot p
    JOIN inventory_archive.tree t ON p.id = t.plot_id
    WHERE p.interval_name = 'ci2017' AND p.federal_state = p_federal_state
  ) w17 ON w12.cluster_name = w17.cluster_name
       AND w12.plot_name    = w17.plot_name
       AND w12.tree_number  = w17.tree_number
  LEFT JOIN (
    SELECT p.cluster_name, p.plot_name, t.tree_number
    FROM inventory_archive.plot p
    JOIN inventory_archive.tree t ON p.id = t.plot_id
    WHERE p.interval_name = 'bwi2022' AND p.federal_state = p_federal_state
  ) w22 ON w12.cluster_name = w22.cluster_name
       AND w12.plot_name    = w22.plot_name
       AND w12.tree_number  = w22.tree_number
  INNER JOIN (
    SELECT elem ->> 'id' AS tree_id, r.id AS record_id
    FROM public.records r
    CROSS JOIN LATERAL jsonb_array_elements(r.properties -> 'tree') AS elem
    WHERE r.cluster_name < 9999900
      AND (elem -> 'dbh') = 'null'::jsonb
      AND COALESCE((elem ->> '_deprecated')::boolean, false) = false
  ) rec ON w12.archive_tree_id = rec.tree_id
  INNER JOIN public.records r ON r.id = rec.record_id
  WHERE w17.tree_number IS NULL
    AND w22.tree_number IS NULL
  ORDER BY w12.cluster_name, w12.plot_name, w12.tree_number;
$$;

REVOKE ALL ON FUNCTION public.deprecate_out_of_zone_trees_preview(int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.deprecate_out_of_zone_trees_preview(int) TO authenticated;
