-- ============================================================================
-- GUARD: Immutable columns on public.records for authenticated users
-- ============================================================================
-- Prevents authenticated users from changing fields that are only managed
-- by server-side processes (data import, admin operations, etc.).
-- service_role and other elevated roles bypass this trigger.
-- Protected columns:
--   plot_id, cluster_id, cluster_name, plot_name,
--   responsible_administration, responsible_state,
--   is_training, previous_position_data, cluster, previous_properties
-- ============================================================================
CREATE OR REPLACE FUNCTION public.guard_records_immutable_columns() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$ BEGIN -- Allow service_role and internal processes to update any column
    IF auth.role() IS DISTINCT
FROM 'authenticated' THEN RETURN NEW;
END IF;
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
IF NEW.responsible_state IS DISTINCT
FROM OLD.responsible_state THEN RAISE EXCEPTION 'Column responsible_state is immutable and cannot be changed by users' USING ERRCODE = '42501';
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
RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.guard_records_immutable_columns() IS 'Prevents authenticated users from modifying server-managed columns on records. service_role bypasses this guard.';
-- Apply trigger
DROP TRIGGER IF EXISTS guard_records_immutable_columns ON public.records;
CREATE TRIGGER guard_records_immutable_columns BEFORE
UPDATE ON public.records FOR EACH ROW EXECUTE FUNCTION public.guard_records_immutable_columns();