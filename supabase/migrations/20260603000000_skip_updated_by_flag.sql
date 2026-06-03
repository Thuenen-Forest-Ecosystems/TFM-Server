-- ==========================================================================
-- MIGRATION: Allow opt-out of updated_by auto-update via session flag
-- ==========================================================================
-- If app.skip_updated_by = 'on' is set in the current session, the trigger
-- leaves updated_by unchanged. Otherwise it behaves as before.
-- ==========================================================================

CREATE OR REPLACE FUNCTION public.update_updated_by_column() RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF current_setting('app.skip_updated_by', true) = 'on' THEN
    RETURN NEW;
  END IF;

  NEW.updated_by = auth.uid();
  RETURN NEW;
END;
$$;
