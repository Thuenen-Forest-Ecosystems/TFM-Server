-- ============================================================================
-- MIGRATION: Control troop read-only (Kontrolltrupp nur lesend)
-- ============================================================================
-- Control troops (troop.is_control_troop) are the read-only viewing vehicle
-- for administrators: a troop assigned via records.responsible_control_troop
-- gets those records synced to its members through the "troop_records"
-- PowerSync bucket (20260605150000), and the SELECT policies on records /
-- record_changes / records_messages grant read access.
--
-- Control troops must never WRITE records. 20260605150000 gave them an
-- UPDATE-policy branch (gated on completed_at_troop) for a control-survey
-- workflow that has been dropped. This migration:
--
--   1. recreates the records UPDATE policy WITHOUT the control-troop branch
--      (the SELECT branches stay untouched — they are the read access),
--   2. adds responsible_control_troop to the audit trail (missed by
--      20260605150000 although record_changes already has the column),
--   3. defensively drops completed_at_control_troop, which an earlier draft
--      of this migration ("control_troop_completion") may have created,
--   4. removes the abandoned organization_admin_sync_selections mechanism;
--      its PowerSync buckets were broken and are removed from
--      config/sync_rules.yaml in the same change set. The read-only control
--      troop replaces it as the way administrators see records in the app.
--
-- records_messages needs no change: its INSERT/UPDATE/DELETE policies never
-- matched control troops; only SELECT does (20260605150000).
--
-- The TFM app additionally renders the control-troop context read-only:
-- PowerSync treats the 42501 RLS rejection as fatal and silently drops the
-- local transaction, so server-blocked edits would be lost, not surfaced.
--
-- Verification: supabase/tests/run_writability_matrix.sh — the control
-- persona must not show a single W/W! cell.
-- ============================================================================

SET search_path TO public;

-- ============================================================================
-- 1. Recreate records UPDATE policy without the control-troop branch
-- ============================================================================
-- Identical to 20260605150000 section 4 minus the responsible_control_troop
-- branch in USING and WITH CHECK. Control troops keep SELECT access only.

DROP POLICY IF EXISTS "Enable UPDATE access for authenticated users with same organization_id of responsible_state, responsible_provider or responsible_troop" ON public.records;
CREATE POLICY "Enable UPDATE access for authenticated users with same organization_id of responsible_state, responsible_provider or responsible_troop" ON public.records AS PERMISSIVE FOR
UPDATE TO authenticated USING (
    -- Root organization or admin users
    EXISTS (
        SELECT 1 FROM public.organizations org
        JOIN public.users_permissions up ON org.id = up.organization_id
        WHERE up.user_id = auth.uid() AND org.type = 'root'
    )
    OR EXISTS (
        SELECT 1 FROM public.users_profile prof
        WHERE prof.id = auth.uid() AND prof.is_admin = true
    )
    OR responsible_state IN (SELECT organization_id FROM public.users_permissions WHERE user_id = auth.uid())
    OR responsible_provider IN (SELECT organization_id FROM public.users_permissions WHERE user_id = auth.uid())
    OR responsible_troop IN (
        SELECT t.id FROM public.troop t
        JOIN public.users_permissions up ON t.organization_id = up.organization_id
        WHERE up.user_id = auth.uid()
    )
) WITH CHECK (
    -- Same constraints for updates
    EXISTS (
        SELECT 1 FROM public.organizations org
        JOIN public.users_permissions up ON org.id = up.organization_id
        WHERE up.user_id = auth.uid() AND org.type = 'root'
    )
    OR EXISTS (
        SELECT 1 FROM public.users_profile prof
        WHERE prof.id = auth.uid() AND prof.is_admin = true
    )
    OR responsible_state IN (SELECT organization_id FROM public.users_permissions WHERE user_id = auth.uid())
    OR responsible_provider IN (SELECT organization_id FROM public.users_permissions WHERE user_id = auth.uid())
    OR responsible_troop IN (
        SELECT t.id FROM public.troop t
        JOIN public.users_permissions up ON t.organization_id = up.organization_id
        WHERE up.user_id = auth.uid()
    )
);

-- ============================================================================
-- 2. Extend audit function handle_record_changes()
-- ============================================================================
-- Adds responsible_control_troop (missed by 20260605150000 although the
-- column was added to record_changes). Assignments of the control troop are
-- made by state/admin users and must mint an audit version like the other
-- responsible_* columns.

CREATE OR REPLACE FUNCTION public.handle_record_changes() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$ BEGIN -- Insert a record into the record_changes table
INSERT INTO public.record_changes (
        id,
        created_at,
        updated_by,
        properties,
        previous_properties,
        previous_properties_updated_at,
        is_valid,
        plot_id,
        schema_id,
        schema_name,
        responsible_administration,
        responsible_state,
        responsible_provider,
        responsible_troop,
        responsible_control_troop,
        validated_at,
        message,
        cluster_id,
        cluster_name,
        plot_name,
        completed_at_troop,
        completed_at_state,
        completed_at_administration,
        updated_at,
        record_id
    )
VALUES (
        gen_random_uuid(),
        NOW(),
        OLD.updated_by,
        OLD.properties,
        OLD.previous_properties,
        OLD.previous_properties_updated_at,
        OLD.is_valid,
        OLD.plot_id,
        OLD.schema_id,
        OLD.schema_name,
        OLD.responsible_administration,
        OLD.responsible_state,
        OLD.responsible_provider,
        OLD.responsible_troop,
        OLD.responsible_control_troop,
        OLD.validated_at,
        OLD.message,
        OLD.cluster_id,
        OLD.cluster_name,
        OLD.plot_name,
        OLD.completed_at_troop,
        OLD.completed_at_state,
        OLD.completed_at_administration,
        OLD.updated_at,
        OLD.id
    );
RETURN NEW;
END;
$$;

-- ============================================================================
-- 3. Recreate on_record_updated with responsible_control_troop in WHEN
-- ============================================================================
-- Pattern from 20260428000000_backup_on_updated_by_change.sql: plain AFTER
-- UPDATE trigger with WHEN condition (evaluated after BEFORE triggers).
-- Must run BEFORE step 4: if the abandoned draft was ever applied, the old
-- WHEN clause references completed_at_control_troop and would block the
-- column drop.

DROP TRIGGER IF EXISTS on_record_updated ON public.records;

CREATE TRIGGER on_record_updated
AFTER UPDATE ON public.records
FOR EACH ROW
WHEN (
    OLD.is_valid IS DISTINCT FROM NEW.is_valid
    OR OLD.completed_at_troop IS DISTINCT FROM NEW.completed_at_troop
    OR OLD.completed_at_state IS DISTINCT FROM NEW.completed_at_state
    OR OLD.completed_at_administration IS DISTINCT FROM NEW.completed_at_administration
    OR OLD.responsible_provider IS DISTINCT FROM NEW.responsible_provider
    OR OLD.responsible_troop IS DISTINCT FROM NEW.responsible_troop
    OR OLD.responsible_control_troop IS DISTINCT FROM NEW.responsible_control_troop
    OR OLD.record_changes_id IS DISTINCT FROM NEW.record_changes_id
    OR OLD.updated_by IS DISTINCT FROM NEW.updated_by
)
EXECUTE FUNCTION public.handle_record_changes();

-- ============================================================================
-- 4. Drop the abandoned completed_at_control_troop columns (draft cleanup)
-- ============================================================================
-- A read-only control troop has no completion to record. No-op unless the
-- earlier "control_troop_completion" draft was applied. view_records_details
-- expands "SELECT r.*" at CREATE time, so it must be dropped first and
-- recreated afterwards either way.

DROP VIEW IF EXISTS public.view_records_details;

ALTER TABLE public.records DROP COLUMN IF EXISTS completed_at_control_troop;
ALTER TABLE public.record_changes DROP COLUMN IF EXISTS completed_at_control_troop;

CREATE OR REPLACE VIEW public.view_records_details AS
SELECT r.*,
    p_coordinates.center_location,
    p_bwi.federal_state,
    p_bwi.growth_district,
    p_bwi.forest_status AS forest_status_bwi2022,
    p_bwi.accessibility,
    p_bwi.forest_office,
    p_bwi.ffh_forest_type_field,
    p_bwi.property_type,
    p_ci2017.forest_status AS forest_status_ci2017,
    p_ci2012.forest_status AS forest_status_ci2012,
    c.cluster_status,
    c.cluster_situation,
    c.state_responsible,
    c.states_affected,
    c.is_training AS cluster_is_training,
    c.grid_density
FROM public.records r
    LEFT JOIN inventory_archive.plot p_bwi ON r.plot_name = p_bwi.plot_name
    AND r.cluster_name = p_bwi.cluster_name
    AND p_bwi.interval_name = 'bwi2022'
    LEFT JOIN inventory_archive.plot_coordinates p_coordinates ON p_bwi.id = p_coordinates.plot_id
    LEFT JOIN inventory_archive.plot p_ci2017 ON p_bwi.plot_name = p_ci2017.plot_name
    AND p_bwi.cluster_name = p_ci2017.cluster_name
    AND p_ci2017.interval_name = 'ci2017'
    LEFT JOIN inventory_archive.plot p_ci2012 ON p_bwi.plot_name = p_ci2012.plot_name
    AND p_bwi.cluster_name = p_ci2012.cluster_name
    AND p_ci2012.interval_name = 'bwi2012'
    LEFT JOIN inventory_archive.cluster c ON r.cluster_name = c.cluster_name;

REVOKE ALL ON public.view_records_details FROM PUBLIC;
REVOKE ALL ON public.view_records_details FROM anon;
GRANT SELECT ON public.view_records_details TO authenticated;

-- ============================================================================
-- 5. Remove abandoned admin sync-selection mechanism
-- ============================================================================
-- Never referenced by any UI code; its PowerSync buckets
-- (organization_admin_sync_management, synced_records) were broken (parameter
-- query on a nonexistent users_permissions.role column / unfiltered
-- parameter query) and are removed from config/sync_rules.yaml alongside
-- this migration. The read-only control troop replaces it.

DROP TABLE IF EXISTS public.organization_admin_sync_selections CASCADE;
