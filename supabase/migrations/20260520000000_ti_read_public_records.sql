-- Grant read access in public schema for external read-only role.
GRANT USAGE ON SCHEMA public TO ti_read;

GRANT SELECT ON TABLE public.records TO ti_read;

DO $$
BEGIN
    IF to_regclass('public.record_changes') IS NOT NULL THEN
        EXECUTE 'GRANT SELECT ON TABLE public.record_changes TO ti_read';
    END IF;

    IF to_regclass('public.records_changes') IS NOT NULL THEN
        EXECUTE 'GRANT SELECT ON TABLE public.records_changes TO ti_read';
    END IF;
END $$;

DROP POLICY IF EXISTS ti_read_select_records ON public.records;
CREATE POLICY ti_read_select_records ON public.records
FOR SELECT TO ti_read
USING (true);

DO $$
BEGIN
    IF to_regclass('public.record_changes') IS NOT NULL THEN
        EXECUTE 'DROP POLICY IF EXISTS ti_read_select_record_changes ON public.record_changes';
        EXECUTE 'CREATE POLICY ti_read_select_record_changes ON public.record_changes FOR SELECT TO ti_read USING (true)';
    END IF;

    IF to_regclass('public.records_changes') IS NOT NULL THEN
        EXECUTE 'DROP POLICY IF EXISTS ti_read_select_records_changes ON public.records_changes';
        EXECUTE 'CREATE POLICY ti_read_select_records_changes ON public.records_changes FOR SELECT TO ti_read USING (true)';
    END IF;
END $$;