-- ============================================================================
-- GUARD: Prevent admins from modifying records.properties
-- ============================================================================
-- "properties" holds the field data collected by the responsible troops.
-- Elevated users must not silently overwrite that collected data, so admins
-- are blocked from changing it. Regular (non-admin) authenticated users are
-- still governed by the existing RLS UPDATE policy and may change properties.
--
-- "admin (org or root)" mirrors the two elevated branches of the records
-- UPDATE policy (20260605150000_add_responsible_control_troop.sql):
--   * users_profile.is_admin = true            (global admin), OR
--   * membership in a root organisation        (organizations.type = 'root')
--
-- service_role and other elevated roles bypass this guard (auth.role() check),
-- as do updates that do not actually change properties.
--
-- NOTE: previous_properties is intentionally NOT handled here. It is already
-- immutable for every authenticated user via guard_records_immutable_columns
-- (20260225000001_records_guards.sql); only service_role / postgres may write
-- it (e.g. fill_previous_properties).
-- ============================================================================
SET search_path TO public;

CREATE OR REPLACE FUNCTION public.guard_records_properties_admin() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE is_blocked_admin boolean;
BEGIN
    -- Allow service_role and other elevated roles to update any column
    IF auth.role() IS DISTINCT FROM 'authenticated' THEN
        RETURN NEW;
    END IF;

    -- Nothing to enforce when properties is unchanged (jsonb equality)
    IF NEW.properties IS NOT DISTINCT FROM OLD.properties THEN
        RETURN NEW;
    END IF;

    -- Is the current user a global admin OR a member of a root organisation?
    SELECT EXISTS (
            SELECT 1
            FROM public.users_profile prof
            WHERE prof.id = auth.uid()
                AND prof.is_admin = true
        )
        OR EXISTS (
            SELECT 1
            FROM public.users_permissions up
                JOIN public.organizations o ON o.id = up.organization_id
            WHERE up.user_id = auth.uid()
                AND o.type = 'root'
        ) INTO is_blocked_admin;

    IF is_blocked_admin THEN
        RAISE EXCEPTION 'Admins (global admin or root organisation) are not permitted to modify records.properties' USING ERRCODE = '42501';
    END IF;

    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.guard_records_properties_admin() IS 'Blocks authenticated admins (users_profile.is_admin or root organisation members) from changing records.properties. service_role bypasses this guard; non-admin users remain governed by RLS.';

-- Apply trigger
DROP TRIGGER IF EXISTS guard_records_properties_admin ON public.records;
CREATE TRIGGER guard_records_properties_admin BEFORE
UPDATE ON public.records FOR EACH ROW EXECUTE FUNCTION public.guard_records_properties_admin();
