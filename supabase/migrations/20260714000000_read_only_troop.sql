-- ============================================================================
-- MIGRATION: Read-only troop (Admin-Gruppe "nur Leserechte")
-- ============================================================================
-- Separates two concepts that 20260605150000/20260709120000 conflated:
--
--   * Kontrolltrupp (troop.is_control_troop): a real surveying troop that
--     performs control surveys. Assigned via responsible_troop and WRITES
--     like any other troop. Unchanged by this migration.
--   * Read-only group (NEW troop.is_read_only): a viewing vehicle for
--     administrators. Assigned via the column previously called
--     responsible_control_troop, which is renamed to
--     responsible_read_only_troop here. Grants SELECT/sync only — the
--     records UPDATE policy has no branch for it (removed in 20260709120000).
--
-- The RENAME COLUMN carries over data, indexes, RLS SELECT policies and
-- trigger WHEN clauses automatically (PostgreSQL stores them as parsed
-- expressions referencing the attribute, not the name). Only objects that
-- embed the column name as TEXT must be recreated:
--   * populate_records_messages_access_control()  (denormalization)
--   * update_records_messages_on_records_change() (denormalization)
--   * handle_record_changes()                     (audit trail)
--   * view_records_details                        (output column names are
--     frozen at CREATE time, so the dashboard would still see the old name)
--
-- Rollout note: config/sync_rules.yaml switches to the new column name in the
-- same change set (PowerSync service restart required), and TFM-app renames
-- the column in its local PowerSync schema. Deploy together.
-- ============================================================================

SET search_path TO public;

-- ============================================================================
-- 1. New flag: troop.is_read_only
-- ============================================================================

ALTER TABLE public.troop
    ADD COLUMN IF NOT EXISTS is_read_only boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.troop.is_read_only IS
    'Read-only group (Admin "nur Leserechte"): members only view records assigned via records.responsible_read_only_troop. Independent of is_control_troop, which marks Kontrolltrupps (regular surveying troops for control surveys).';

-- ============================================================================
-- 2. Rename responsible_control_troop -> responsible_read_only_troop
-- ============================================================================
-- Guarded so a re-run (or a database that never had the old column) is a
-- no-op instead of an error.

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'records'
          AND column_name = 'responsible_control_troop'
    ) THEN
        ALTER TABLE public.records
            RENAME COLUMN responsible_control_troop TO responsible_read_only_troop;
    END IF;
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'record_changes'
          AND column_name = 'responsible_control_troop'
    ) THEN
        ALTER TABLE public.record_changes
            RENAME COLUMN responsible_control_troop TO responsible_read_only_troop;
    END IF;
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'records_messages'
          AND column_name = 'responsible_control_troop'
    ) THEN
        ALTER TABLE public.records_messages
            RENAME COLUMN responsible_control_troop TO responsible_read_only_troop;
    END IF;
END
$$;

COMMENT ON COLUMN public.records.responsible_read_only_troop IS
    'Read-only group (troop.is_read_only) that may VIEW this record in the app (PowerSync troop_records bucket + SELECT policies). No write access: the records UPDATE policy has no branch for this column.';

-- Index names do not follow the column rename; rename them for hygiene.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_records_responsible_control_troop') THEN
        ALTER INDEX public.idx_records_responsible_control_troop RENAME TO idx_records_responsible_read_only_troop;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_record_changes_responsible_control_troop') THEN
        ALTER INDEX public.idx_record_changes_responsible_control_troop RENAME TO idx_record_changes_responsible_read_only_troop;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_records_messages_responsible_control_troop') THEN
        ALTER INDEX public.idx_records_messages_responsible_control_troop RENAME TO idx_records_messages_responsible_read_only_troop;
    END IF;
END
$$;

-- ============================================================================
-- 3. Recreate records_messages denormalization functions (text bodies)
-- ============================================================================
-- Same logic as 20260605150000, with the renamed column.

CREATE OR REPLACE FUNCTION public.populate_records_messages_access_control() RETURNS TRIGGER AS $$
BEGIN
    SELECT
        r.responsible_administration,
        r.responsible_state,
        r.responsible_provider,
        r.responsible_troop,
        r.responsible_read_only_troop
    INTO
        NEW.responsible_administration,
        NEW.responsible_state,
        NEW.responsible_provider,
        NEW.responsible_troop,
        NEW.responsible_read_only_troop
    FROM public.records r
    WHERE r.id = NEW.records_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.update_records_messages_on_records_change() RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.records_messages
    SET
        responsible_administration = NEW.responsible_administration,
        responsible_state = NEW.responsible_state,
        responsible_provider = NEW.responsible_provider,
        responsible_troop = NEW.responsible_troop,
        responsible_read_only_troop = NEW.responsible_read_only_troop
    WHERE records_id = NEW.id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_records_messages_on_records_change_trigger ON public.records;
CREATE TRIGGER update_records_messages_on_records_change_trigger
AFTER UPDATE ON public.records FOR EACH ROW
WHEN (
    OLD.responsible_administration IS DISTINCT FROM NEW.responsible_administration
    OR OLD.responsible_state IS DISTINCT FROM NEW.responsible_state
    OR OLD.responsible_provider IS DISTINCT FROM NEW.responsible_provider
    OR OLD.responsible_troop IS DISTINCT FROM NEW.responsible_troop
    OR OLD.responsible_read_only_troop IS DISTINCT FROM NEW.responsible_read_only_troop
) EXECUTE FUNCTION public.update_records_messages_on_records_change();

-- ============================================================================
-- 4. Recreate audit function handle_record_changes() (text body)
-- ============================================================================

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
        responsible_read_only_troop,
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
        OLD.responsible_read_only_troop,
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

-- The on_record_updated trigger WHEN clause (20260709120000) follows the
-- rename automatically; recreated here anyway so the deployed definition can
-- be reproduced from this file alone.
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
    OR OLD.responsible_read_only_troop IS DISTINCT FROM NEW.responsible_read_only_troop
    OR OLD.record_changes_id IS DISTINCT FROM NEW.record_changes_id
    OR OLD.updated_by IS DISTINCT FROM NEW.updated_by
)
EXECUTE FUNCTION public.handle_record_changes();

-- ============================================================================
-- 5. Recreate view_records_details
-- ============================================================================
-- View output column names are frozen at CREATE time; without recreation the
-- view would still expose "responsible_control_troop".

DROP VIEW IF EXISTS public.view_records_details;
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
