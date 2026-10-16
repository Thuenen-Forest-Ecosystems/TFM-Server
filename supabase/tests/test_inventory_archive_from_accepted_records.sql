-- ============================================================================
-- DRY-RUN TEST: Abnahme durch die BIL schreibt ins Archiv (20261018000000)
-- ============================================================================
-- Prueft:
--   1. Abnahme legt den ci2027-Plot samt Fachdaten an, die Vorinventur bleibt
--      unberuehrt (properties traegt deren ids).
--   2. Erneute Abnahme ist ein Upsert: gleiche Plot-id, keine Duplikate.
--   3. Aenderung von properties an einer abgenommenen Ecke kommt im Archiv an,
--      entfernte Zeilen verschwinden.
--   4. Ruecknahme loescht den Plot samt Fachdaten und Koordinaten.
--   5. Schulungstrakte werden archiviert; ein von records.plot_id
--      referenzierter ci2027-Plot wird bei Ruecknahme nur geleert.
--   6. Ungueltige Daten brechen die Abnahme mit Trakt/Ecke in der Meldung ab.
--   7. authenticated darf die Archivfunktionen nicht direkt aufrufen.
--
-- SAFE BY DESIGN: genau ein BEGIN und ein ROLLBACK, kein COMMIT.
--
-- Run:  psql "$DB_URL" -f supabase/tests/test_inventory_archive_from_accepted_records.sql
-- ============================================================================
\set ON_ERROR_STOP on
\pset pager off
\timing off

BEGIN;
SET LOCAL client_min_messages = warning;

-- Testecke: kein Schulungstrakt, noch nicht abgenommen, mit Baeumen, darunter
-- mindestens einer mit Vorinventur-id und einer, der nicht _deprecated ist.
CREATE TEMP TABLE t_case ON COMMIT DROP AS
SELECT r.id, r.cluster_name, r.plot_name,
       (SELECT count(*) FROM jsonb_array_elements(r.properties->'tree') el
        WHERE coalesce((el->>'_deprecated')::boolean, false) = false) AS expected_trees
FROM public.records r
JOIN inventory_archive.cluster c ON c.id = r.cluster_id AND NOT c.is_training
WHERE r.completed_at_administration IS NULL
  AND r.completed_at_state IS NOT NULL
  AND jsonb_typeof(r.properties->'tree') = 'array'
  AND EXISTS (SELECT 1 FROM jsonb_array_elements(r.properties->'tree') el
              JOIN inventory_archive.tree t ON t.id = (el->>'id')::uuid)
  AND (SELECT count(*) FROM jsonb_array_elements(r.properties->'tree') el
       WHERE coalesce((el->>'_deprecated')::boolean, false) = false) >= 2
  AND NOT EXISTS (SELECT 1 FROM inventory_archive.plot p
                  WHERE p.cluster_name = r.cluster_name AND p.plot_name = r.plot_name
                    AND p.interval_name = 'ci2027')
ORDER BY r.cluster_name, r.plot_name
LIMIT 1;

DO $$
DECLARE
    tc          record;
    v_plot      uuid;
    v_plot2     uuid;
    v_trees     bigint;
    v_prev      bigint;
    v_prev_after bigint;
    v_tree_id   uuid;
BEGIN
    SELECT * INTO tc FROM t_case;
    IF tc.id IS NULL THEN
        RAISE EXCEPTION 'Keine geeignete Testecke gefunden';
    END IF;
    RAISE WARNING 'Testecke: Trakt % Ecke %, % Baeume erwartet', tc.cluster_name, tc.plot_name, tc.expected_trees;

    -- Vorinventur-Baeume, auf deren ids properties zeigt
    SELECT count(*) INTO v_prev
    FROM public.records r, jsonb_array_elements(r.properties->'tree') el
    JOIN inventory_archive.tree t ON t.id = (el->>'id')::uuid
    WHERE r.id = tc.id;

    -- 1. Abnahme
    UPDATE public.records SET completed_at_administration = now() WHERE id = tc.id;

    SELECT id INTO v_plot FROM inventory_archive.plot
    WHERE cluster_name = tc.cluster_name AND plot_name = tc.plot_name AND interval_name = 'ci2027';
    IF v_plot IS NULL THEN RAISE EXCEPTION '1: kein ci2027-Plot angelegt'; END IF;

    SELECT count(*) INTO v_trees FROM inventory_archive.tree WHERE plot_id = v_plot;
    IF v_trees <> tc.expected_trees THEN
        RAISE EXCEPTION '1: % Baeume im Archiv, % erwartet', v_trees, tc.expected_trees;
    END IF;
    IF EXISTS (SELECT 1 FROM inventory_archive.tree t
               LEFT JOIN inventory_archive.tree_coordinates c ON c.tree_id = t.id
               WHERE t.plot_id = v_plot AND c.id IS NULL) THEN
        RAISE EXCEPTION '1: Baum ohne tree_coordinates';
    END IF;

    SELECT count(*) INTO v_prev_after
    FROM public.records r, jsonb_array_elements(r.properties->'tree') el
    JOIN inventory_archive.tree t ON t.id = (el->>'id')::uuid
    WHERE r.id = tc.id AND t.plot_id <> v_plot;
    IF v_prev_after <> v_prev THEN
        RAISE EXCEPTION '1: Vorinventur veraendert (% statt % Baeume)', v_prev_after, v_prev;
    END IF;
    RAISE WARNING '1 ok: Plot %, % Baeume, Vorinventur unberuehrt', v_plot, v_trees;

    -- 2. Erneute Abnahme
    UPDATE public.records SET completed_at_administration = now() + interval '1 second' WHERE id = tc.id;
    SELECT id INTO v_plot2 FROM inventory_archive.plot
    WHERE cluster_name = tc.cluster_name AND plot_name = tc.plot_name AND interval_name = 'ci2027';
    IF v_plot2 IS DISTINCT FROM v_plot THEN RAISE EXCEPTION '2: Plot-id gewechselt'; END IF;
    SELECT count(*) INTO v_trees FROM inventory_archive.tree WHERE plot_id = v_plot;
    IF v_trees <> tc.expected_trees THEN RAISE EXCEPTION '2: % Baeume nach erneuter Abnahme', v_trees; END IF;
    RAISE WARNING '2 ok: Upsert, Plot-id stabil, keine Duplikate';

    -- 3. properties aendern: letzten nicht entfernten Baum herausnehmen
    UPDATE public.records r
    SET properties = jsonb_set(r.properties, '{tree}', (
        SELECT jsonb_agg(el ORDER BY o) FROM jsonb_array_elements(r.properties->'tree') WITH ORDINALITY x(el, o)
        WHERE o <> (SELECT max(o2) FROM jsonb_array_elements(r.properties->'tree') WITH ORDINALITY y(el2, o2)
                    WHERE coalesce((el2->>'_deprecated')::boolean, false) = false)))
    WHERE r.id = tc.id;
    SELECT count(*) INTO v_trees FROM inventory_archive.tree WHERE plot_id = v_plot;
    IF v_trees <> tc.expected_trees - 1 THEN
        RAISE EXCEPTION '3: % Baeume nach Aenderung, % erwartet', v_trees, tc.expected_trees - 1;
    END IF;
    RAISE WARNING '3 ok: Aenderung von properties synchronisiert';

    -- 4. Ruecknahme
    SELECT id INTO v_tree_id FROM inventory_archive.tree WHERE plot_id = v_plot LIMIT 1;
    UPDATE public.records SET completed_at_administration = NULL WHERE id = tc.id;
    IF EXISTS (SELECT 1 FROM inventory_archive.plot WHERE id = v_plot) THEN
        RAISE EXCEPTION '4: Plot nach Ruecknahme noch da';
    END IF;
    IF EXISTS (SELECT 1 FROM inventory_archive.tree WHERE plot_id = v_plot)
       OR EXISTS (SELECT 1 FROM inventory_archive.tree_coordinates WHERE tree_id = v_tree_id) THEN
        RAISE EXCEPTION '4: Fachdaten nach Ruecknahme noch da';
    END IF;
    SELECT count(*) INTO v_prev_after
    FROM public.records r, jsonb_array_elements(r.properties->'tree') el
    JOIN inventory_archive.tree t ON t.id = (el->>'id')::uuid
    WHERE r.id = tc.id;
    IF v_prev_after < v_prev - 1 THEN
        RAISE EXCEPTION '4: Ruecknahme hat Vorinventur geloescht';
    END IF;
    RAISE WARNING '4 ok: Ruecknahme loescht Plot und Fachdaten';
END $$;

-- 5. Schulungstrakte
-- Uebungsdaten sind oft unvollstaendig (lokal 73 von 796 Ecken); gesucht wird
-- daher eine Ecke, die sich fehlerfrei archivieren laesst. Die Probe laeuft in
-- einer Subtransaktion und hinterlaesst nichts.
CREATE FUNCTION pg_temp.archives_cleanly(p_id uuid) RETURNS boolean
LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        PERFORM inventory_archive.sync_record_to_archive(p_id);
        RAISE EXCEPTION USING ERRCODE = 'P0099';
    EXCEPTION
        WHEN SQLSTATE 'P0099' THEN RETURN true;
        WHEN OTHERS THEN RETURN false;
    END;
END;
$$;

--   a) Ecke ohne ci2027-Plot: wird angelegt und bei Ruecknahme geloescht.
--   b) Ecke, deren records.plot_id auf einen ci2027-Plot zeigt: der Plot wird
--      beschrieben und bei Ruecknahme nur geleert, nicht geloescht.
DO $$
DECLARE
    v_rec   uuid;
    v_cl    int;
    v_pl    int;
    v_plot  uuid;
    v_n     bigint;
BEGIN
    SELECT r.id, r.cluster_name, r.plot_name INTO v_rec, v_cl, v_pl
    FROM public.records r
    JOIN inventory_archive.cluster c ON c.id = r.cluster_id AND c.is_training
    WHERE jsonb_array_length(coalesce(r.properties->'tree', '[]')) > 0
      AND NOT EXISTS (SELECT 1 FROM inventory_archive.plot p
                      WHERE p.cluster_name = r.cluster_name AND p.plot_name = r.plot_name
                        AND p.interval_name = 'ci2027')
      AND pg_temp.archives_cleanly(r.id)
    LIMIT 1;
    IF v_rec IS NULL THEN
        RAISE WARNING '5a uebersprungen: keine Schulungsecke ohne ci2027-Plot';
    ELSE
        UPDATE public.records SET completed_at_administration = now() WHERE id = v_rec;
        SELECT id INTO v_plot FROM inventory_archive.plot
        WHERE cluster_name = v_cl AND plot_name = v_pl AND interval_name = 'ci2027';
        IF v_plot IS NULL THEN RAISE EXCEPTION '5a: Schulungsecke nicht archiviert'; END IF;
        UPDATE public.records SET completed_at_administration = NULL WHERE id = v_rec;
        IF EXISTS (SELECT 1 FROM inventory_archive.plot WHERE id = v_plot) THEN
            RAISE EXCEPTION '5a: Plot nach Ruecknahme noch da';
        END IF;
        RAISE WARNING '5a ok: Trakt % Ecke % archiviert und wieder entfernt', v_cl, v_pl;
    END IF;

    v_rec := NULL;
    SELECT r.id, r.plot_id INTO v_rec, v_plot
    FROM public.records r
    JOIN inventory_archive.cluster c ON c.id = r.cluster_id AND c.is_training
    JOIN inventory_archive.plot p ON p.id = r.plot_id AND p.interval_name = 'ci2027'
    WHERE jsonb_array_length(coalesce(r.properties->'tree', '[]')) > 0
      AND pg_temp.archives_cleanly(r.id)
    LIMIT 1;
    IF v_rec IS NULL THEN
        RAISE WARNING '5b uebersprungen: keine Schulungsecke mit referenziertem ci2027-Plot und Baeumen';
        RETURN;
    END IF;

    UPDATE public.records SET completed_at_administration = now() WHERE id = v_rec;
    SELECT count(*) INTO v_n FROM inventory_archive.tree WHERE plot_id = v_plot;
    IF v_n = 0 THEN RAISE EXCEPTION '5b: referenzierter Schulungsplot nicht beschrieben'; END IF;

    UPDATE public.records SET completed_at_administration = NULL WHERE id = v_rec;
    IF NOT EXISTS (SELECT 1 FROM inventory_archive.plot WHERE id = v_plot) THEN
        RAISE EXCEPTION '5b: referenzierter Plot wurde geloescht';
    END IF;
    IF EXISTS (SELECT 1 FROM inventory_archive.tree WHERE plot_id = v_plot) THEN
        RAISE EXCEPTION '5b: Fachdaten nach Ruecknahme noch da';
    END IF;
    RAISE WARNING '5b ok: referenzierter Plot beschrieben (% Baeume), bei Ruecknahme geleert', v_n;
END $$;

-- 6. Ungueltige Daten
DO $$
DECLARE
    tc record;
BEGIN
    SELECT * INTO tc FROM t_case;
    UPDATE public.records r
    SET properties = jsonb_set(r.properties, '{tree,0,azimuth}', '400'::jsonb)
    WHERE r.id = tc.id;
    BEGIN
        UPDATE public.records SET completed_at_administration = now() WHERE id = tc.id;
        RAISE EXCEPTION '6: Abnahme mit azimuth 400 ging durch';
    EXCEPTION WHEN check_violation THEN
        IF SQLERRM NOT LIKE format('Archivierung Trakt %s Ecke %s%%', tc.cluster_name, tc.plot_name) THEN
            RAISE EXCEPTION '6: unerwartete Meldung: %', SQLERRM;
        END IF;
        RAISE WARNING '6 ok: %', SQLERRM;
    END;
    IF (SELECT completed_at_administration FROM public.records WHERE id = tc.id) IS NOT NULL THEN
        RAISE EXCEPTION '6: Ecke trotz Fehler abgenommen';
    END IF;
END $$;

-- 7. Rechte
SET LOCAL ROLE authenticated;
DO $$
BEGIN
    PERFORM inventory_archive.sync_record_to_archive((SELECT id FROM t_case));
    RAISE EXCEPTION '7: authenticated darf sync_record_to_archive aufrufen';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE WARNING '7 ok: authenticated ohne EXECUTE';
END $$;
RESET ROLE;

\echo ''
\echo 'Alle Pruefungen bestanden.'
ROLLBACK;
