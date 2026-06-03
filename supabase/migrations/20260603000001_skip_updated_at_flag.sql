-- ==========================================================================
-- MIGRATION: Allow opt-out of updated_at auto-update via session flag
-- ==========================================================================
-- If app.skip_updated_at = 'on' is set in the current session, the trigger
-- leaves updated_at unchanged. Otherwise it behaves as before.
-- ==========================================================================

CREATE OR REPLACE FUNCTION public.update_updated_at_column() RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF current_setting('app.skip_updated_at', true) = 'on' THEN
    RETURN NEW;
  END IF;

  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS handle_updated_at ON public.records;
CREATE TRIGGER handle_updated_at BEFORE
UPDATE ON public.records FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
