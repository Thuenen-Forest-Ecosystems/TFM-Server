-- ============================================================================
-- MIGRATION: Backup record when updated_by changes
-- ============================================================================
-- The existing on_record_updated trigger uses UPDATE OF column_name syntax,
-- which fires only when the listed columns appear in the SET clause of the
-- UPDATE statement. Because updated_by is set automatically by the
-- handle_updated_by BEFORE trigger (not by the caller), it never appears in
-- the SET clause and cannot be detected with UPDATE OF.
--
-- Solution: drop the column-list trigger and recreate it as a plain AFTER
-- UPDATE trigger with a WHEN condition. The WHEN condition is evaluated
-- AFTER all BEFORE triggers have run, so NEW.updated_by already reflects the
-- value set by handle_updated_by — making the comparison reliable.
-- ============================================================================

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
    OR OLD.record_changes_id IS DISTINCT FROM NEW.record_changes_id
    OR OLD.updated_by IS DISTINCT FROM NEW.updated_by
)
EXECUTE FUNCTION public.handle_record_changes();
