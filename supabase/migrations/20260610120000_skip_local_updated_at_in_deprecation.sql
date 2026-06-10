-- ==========================================================================
-- MIGRATION: Stop bumping local_updated_at in set_trees_to_deprecated
-- ==========================================================================
-- set_trees_to_deprecated (20260527000000_deprecate_out_of_zone_trees.sql)
-- already skips the updated_at / updated_by audit triggers via the
-- app.skip_updated_at / app.skip_updated_by session flags, so the maintenance
-- deprecation does not look like a user edit.
--
-- It still wrote `local_updated_at = now()`, which flags records as having
-- pending local changes (local_updated_at > updated_at) and triggers a re-sync
-- in the app. For a silent maintenance update that is unwanted, so this column
-- is now left untouched as well.
--
-- Only the UPDATE branch is changed; the dry-run COUNT branch is unchanged.
-- ==========================================================================
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
    -- Skip audit triggers for this maintenance update.
    PERFORM set_config('app.skip_updated_by', 'on', true);
    PERFORM set_config('app.skip_updated_at', 'on', true);
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
      )
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
