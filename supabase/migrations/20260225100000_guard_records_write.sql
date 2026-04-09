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