-- ============================================================================
-- CLEANUP: Trigger before_record_insert_or_update entfernen
-- ============================================================================
-- Der Trigger (BEFORE INSERT OR UPDATE OF previous_properties_updated_at,
-- plot_id, cluster_name → public.fill_previous_properties()) steht in keiner
-- Migration, ist auf Prod deaktiviert (tgenabled = 'D', 2026-11-02), lokal aber
-- aktiv. Wieder eingeschaltet wuerde er previous_properties aus der Matview
-- plot_nested_json_cached (nur bwi2022-Baeume, ohne BHD-Ergaenzung aus
-- 20261102100000) ueberschreiben bzw. auf '{}' setzen, wenn die Matview fuer
-- die Ecke keine Zeile hat.
--
-- previous_properties wird nur noch ueber die Stapelfunktion
-- public.fill_previous_properties(integer, integer, boolean) geschrieben.
--
-- Mit entfernt: die Altfunktionen batch_update_records(integer) und
-- set_previous_properties(integer, integer). Beide schalten den Trigger am
-- Ende per ENABLE TRIGGER wieder ein (so ist er lokal aktiv geworden);
-- set_previous_properties schreibt previous_properties zudem aus der View
-- plot_nested_json ohne BHD-Ergaenzung. Ersetzt durch
-- fill_previous_properties(integer, integer, boolean); Aufrufer gab es nur
-- noch in nfi2022/migration-script/README.md.
--
-- Bewusst NICHT entfernt (eigene Pruefung, ob noch genutzt):
--   plot_nested_json_cached, get_plot_nested_json_by_id(...),
--   derived.fill_previous_properties(), refresh_plot_nested_json_cached().
-- ============================================================================

DROP FUNCTION IF EXISTS public.batch_update_records(integer);
DROP FUNCTION IF EXISTS public.set_previous_properties(integer, integer);

-- Abbrechen, falls noch eine Funktion den Trigger umschaltet
-- (ALTER TABLE ... ENABLE/DISABLE TRIGGER wuerde nach dem DROP fehlschlagen).
DO $$
DECLARE
    v_refs text;
BEGIN
    SELECT string_agg(p.oid::regprocedure::text, ', ')
    INTO v_refs
    FROM pg_proc p
    WHERE p.prosrc ILIKE '%before_record_insert_or_update%';

    IF v_refs IS NOT NULL THEN
        RAISE EXCEPTION 'before_record_insert_or_update wird noch referenziert von: %', v_refs;
    END IF;
END;
$$;

DROP TRIGGER IF EXISTS before_record_insert_or_update ON public.records;

-- Trigger-Variante; die Stapelvariante (integer, integer, boolean) bleibt.
DROP FUNCTION IF EXISTS public.fill_previous_properties();
