-- Migration: Add responsible_control_troop column to records, record_changes, records_messages 
-- and update related policies + triggers

SET search_path TO public;

-- 1. Add columns to records, record_changes, records_messages
ALTER TABLE public.records ADD COLUMN IF NOT EXISTS responsible_control_troop uuid REFERENCES public.troop(id) ON DELETE SET NULL;
ALTER TABLE public.record_changes ADD COLUMN IF NOT EXISTS responsible_control_troop uuid REFERENCES public.troop(id) ON DELETE SET NULL;
ALTER TABLE public.records_messages ADD COLUMN IF NOT EXISTS responsible_control_troop uuid REFERENCES public.troop(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_records_responsible_control_troop ON public.records(responsible_control_troop);
CREATE INDEX IF NOT EXISTS idx_record_changes_responsible_control_troop ON public.record_changes(responsible_control_troop);
CREATE INDEX IF NOT EXISTS idx_records_messages_responsible_control_troop ON public.records_messages(responsible_control_troop);

-- 2. Update Triggers for records_messages denormalization
CREATE OR REPLACE FUNCTION public.populate_records_messages_access_control() RETURNS TRIGGER AS $$ 
BEGIN 
    SELECT 
        r.responsible_administration,
        r.responsible_state,
        r.responsible_provider,
        r.responsible_troop,
        r.responsible_control_troop 
    INTO 
        NEW.responsible_administration,
        NEW.responsible_state,
        NEW.responsible_provider,
        NEW.responsible_troop,
        NEW.responsible_control_troop
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
        responsible_control_troop = NEW.responsible_control_troop
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
    OR OLD.responsible_control_troop IS DISTINCT FROM NEW.responsible_control_troop
) EXECUTE FUNCTION public.update_records_messages_on_records_change();

-- Initialize column on existing messages
UPDATE public.records_messages m
SET responsible_control_troop = r.responsible_control_troop
FROM public.records r
WHERE m.records_id = r.id;

-- 3. Update SELECT Policy for records
DROP POLICY IF EXISTS "Enable SELECT access for authenticated users with same organization_id of responsible_state, responsible_provider or responsible_troop" ON public.records;
CREATE POLICY "Enable SELECT access for authenticated users with same organization_id of responsible_state, responsible_provider or responsible_troop" ON public.records AS PERMISSIVE FOR
SELECT TO authenticated USING (
    -- Root organization users can see all records
    EXISTS (
        SELECT 1 FROM public.organizations org
        JOIN public.users_permissions up ON org.id = up.organization_id
        WHERE up.user_id = auth.uid() AND org.type = 'root'
    )
    OR responsible_state IN (SELECT organization_id FROM public.users_permissions WHERE user_id = auth.uid())
    OR responsible_provider IN (SELECT organization_id FROM public.users_permissions WHERE user_id = auth.uid())
    OR responsible_troop IN (
        SELECT t.id FROM public.troop t
        JOIN public.users_permissions up ON t.organization_id = up.organization_id
        WHERE up.user_id = auth.uid()
    )
    OR responsible_control_troop IN (
        SELECT t.id FROM public.troop t
        JOIN public.users_permissions up ON t.organization_id = up.organization_id
        WHERE up.user_id = auth.uid()
    )
);

-- 4. Update UPDATE Policy for records
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
    OR (
        responsible_control_troop IN (
            SELECT t.id FROM public.troop t
            JOIN public.users_permissions up ON t.organization_id = up.organization_id
            WHERE up.user_id = auth.uid()
        )
        AND (completed_at_troop IS NOT NULL OR responsible_troop IS NULL)
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
    OR (
        responsible_control_troop IN (
            SELECT t.id FROM public.troop t
            JOIN public.users_permissions up ON t.organization_id = up.organization_id
            WHERE up.user_id = auth.uid()
        )
        AND (completed_at_troop IS NOT NULL OR responsible_troop IS NULL)
    )
);

-- 5. Update SELECT Policy for record_changes
DROP POLICY IF EXISTS "record_changes: Enable SELECT access for authenticated users with same organization_id of responsible_state, responsible_provider or responsible_troop" ON public.record_changes;
CREATE POLICY "record_changes: Enable SELECT access for authenticated users with same organization_id of responsible_state, responsible_provider or responsible_troop" ON public.record_changes AS PERMISSIVE FOR
SELECT TO authenticated USING (
    -- Root organization users can see all changes
    EXISTS (
        SELECT 1 FROM public.organizations org
        JOIN public.users_permissions up ON org.id = up.organization_id
        WHERE up.user_id = auth.uid() AND org.type = 'root'
    )
    OR responsible_state IN (SELECT organization_id FROM public.users_permissions WHERE user_id = auth.uid())
    OR responsible_provider IN (SELECT organization_id FROM public.users_permissions WHERE user_id = auth.uid())
    OR responsible_troop IN (
        SELECT t.id FROM public.troop t
        JOIN public.users_permissions up ON t.organization_id = up.organization_id
        WHERE up.user_id = auth.uid()
    )
    OR responsible_control_troop IN (
        SELECT t.id FROM public.troop t
        JOIN public.users_permissions up ON t.organization_id = up.organization_id
        WHERE up.user_id = auth.uid()
    )
);

-- 6. Update SELECT Policy for records_messages
DROP POLICY IF EXISTS "Enable SELECT access for records_messages" ON public.records_messages;
CREATE POLICY "Enable SELECT access for records_messages" ON public.records_messages AS PERMISSIVE FOR
SELECT TO authenticated USING (
    EXISTS (
        SELECT 1 FROM public.organizations org
        JOIN public.users_permissions up ON org.id = up.organization_id
        WHERE up.user_id = auth.uid() AND org.type = 'root'
    )
    OR responsible_state IN (SELECT organization_id FROM public.users_permissions WHERE user_id = auth.uid())
    OR responsible_provider IN (SELECT organization_id FROM public.users_permissions WHERE user_id = auth.uid())
    OR responsible_troop IN (
        SELECT t.id FROM public.troop t
        JOIN public.users_permissions up ON t.organization_id = up.organization_id
        WHERE up.user_id = auth.uid()
    )
    OR responsible_control_troop IN (
        SELECT t.id FROM public.troop t
        JOIN public.users_permissions up ON t.organization_id = up.organization_id
        WHERE up.user_id = auth.uid()
    )
);

-- ============================================================================
-- Recreate view_records_details to include the new column
-- ============================================================================
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
