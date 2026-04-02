-- ============================================================================
-- PATCH: Allow root organisation admins to change responsible_state
-- ============================================================================
-- Extends guard_records_immutable_columns so that authenticated users who hold
-- is_organization_admin = true in users_permissions for at least one
-- organisation with type = 'root' may update the responsible_state column.
-- All other immutable-column restrictions remain unchanged.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.guard_records_immutable_columns() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE is_root_admin boolean;
BEGIN -- Allow service_role and other elevated roles to update any column
IF auth.role() IS DISTINCT
FROM 'authenticated' THEN RETURN NEW;
END IF;
-- Check whether the current user is an admin of a root organisation
SELECT EXISTS (
        SELECT 1
        FROM public.users_permissions up
            JOIN public.organizations o ON o.id = up.organization_id
        WHERE up.user_id = auth.uid()
            AND up.is_organization_admin = true
            AND o.type = 'root'
    ) INTO is_root_admin;
-- ── Strictly immutable columns (no exceptions for regular admins) ──────────
IF NEW.plot_id IS DISTINCT
FROM OLD.plot_id THEN RAISE EXCEPTION 'Column plot_id is immutable and cannot be changed by users' USING ERRCODE = '42501';
END IF;
IF NEW.cluster_id IS DISTINCT
FROM OLD.cluster_id THEN RAISE EXCEPTION 'Column cluster_id is immutable and cannot be changed by users' USING ERRCODE = '42501';
END IF;
IF NEW.cluster_name IS DISTINCT
FROM OLD.cluster_name THEN RAISE EXCEPTION 'Column cluster_name is immutable and cannot be changed by users' USING ERRCODE = '42501';
END IF;
IF NEW.plot_name IS DISTINCT
FROM OLD.plot_name THEN RAISE EXCEPTION 'Column plot_name is immutable and cannot be changed by users' USING ERRCODE = '42501';
END IF;
IF NEW.responsible_administration IS DISTINCT
FROM OLD.responsible_administration THEN RAISE EXCEPTION 'Column responsible_administration is immutable and cannot be changed by users' USING ERRCODE = '42501';
END IF;
IF NEW.is_training IS DISTINCT
FROM OLD.is_training THEN RAISE EXCEPTION 'Column is_training is immutable and cannot be changed by users' USING ERRCODE = '42501';
END IF;
IF NEW.previous_position_data IS DISTINCT
FROM OLD.previous_position_data THEN RAISE EXCEPTION 'Column previous_position_data is immutable and cannot be changed by users' USING ERRCODE = '42501';
END IF;
IF NEW.cluster IS DISTINCT
FROM OLD.cluster THEN RAISE EXCEPTION 'Column cluster is immutable and cannot be changed by users' USING ERRCODE = '42501';
END IF;
IF NEW.previous_properties IS DISTINCT
FROM OLD.previous_properties THEN RAISE EXCEPTION 'Column previous_properties is immutable and cannot be changed by users' USING ERRCODE = '42501';
END IF;
-- ── Columns editable by root-organisation admins ──────────────────────────
IF NEW.responsible_state IS DISTINCT
FROM OLD.responsible_state
    AND NOT is_root_admin THEN RAISE EXCEPTION 'Column responsible_state can only be changed by root organisation admins' USING ERRCODE = '42501';
END IF;
RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.guard_records_immutable_columns() IS 'Prevents authenticated users from modifying server-managed columns on records. service_role bypasses this guard. responsible_state may be changed by admins of root organisations.';