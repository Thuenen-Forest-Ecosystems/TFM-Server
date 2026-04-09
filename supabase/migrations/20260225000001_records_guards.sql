-- ============================================================================
-- GUARD: Restrict record writes to the TFM Flutter app
-- ============================================================================
-- Prevents users from modifying records via R, Python, or other REST clients.
-- The supabase_flutter SDK automatically sends an X-Client-Info header
-- (e.g. "supabase-flutter/2.10.3") on every request.
-- Raw HTTP clients (httr, requests, curl) do not send this header.
--
-- RLS policies remain unchanged → PowerSync sync (SELECT) is unaffected.
-- No app changes required.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.guard_records_write() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE headers json;
client_info text;
BEGIN -- PostgREST exposes request headers via a GUC variable
headers := current_setting('request.headers', true)::json;
client_info := headers->>'x-client-info';
-- Allow writes from the Flutter app (supabase-flutter SDK)
IF client_info IS NOT NULL
AND client_info LIKE 'supabase-flutter%' THEN RETURN NEW;
END IF;
-- Block everything else
RAISE EXCEPTION 'Direct API writes are not permitted. Use the TFM app to modify records.' USING ERRCODE = '42501';
-- insufficient_privilege
RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.guard_records_write() IS 'Blocks record writes not originating from the Flutter app (supabase-flutter SDK). Admins are exempt.';
-- Apply trigger to records table
DROP TRIGGER IF EXISTS guard_records_write ON public.records;
-- ============================================================================
-- GUARD: Immutable columns on public.records for authenticated users
-- ============================================================================
-- Prevents authenticated users from changing fields that are only managed
-- by server-side processes (data import, admin operations, etc.).
-- service_role and other elevated roles bypass this trigger.
-- Root organisation admins may update responsible_state.
-- Protected columns:
--   plot_id, cluster_id, cluster_name, plot_name,
--   responsible_administration, responsible_state (except root admins),
--   is_training, previous_position_data, cluster, previous_properties
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
-- Apply trigger
DROP TRIGGER IF EXISTS guard_records_immutable_columns ON public.records;
CREATE TRIGGER guard_records_immutable_columns BEFORE
UPDATE ON public.records FOR EACH ROW EXECUTE FUNCTION public.guard_records_immutable_columns();