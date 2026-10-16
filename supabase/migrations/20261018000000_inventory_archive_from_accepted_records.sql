-- ============================================================================
-- MIGRATION: Abgenommene Ecken nach inventory_archive uebernehmen
-- ============================================================================
-- Nimmt die Bundesinventurleitung im Verwaltungstool einen Trakt ab
-- (FinishDialog.vue, organization_type 'root'), setzt sie
-- records.completed_at_administration. Ab dann gehoeren die Aufnahmedaten aus
-- records.properties ins Archiv, als Plot des laufenden Intervalls (ci2027).
-- Nimmt sie die Abnahme zurueck (ListOfClusterRecord.vue, Rueckgabe an die
-- LIL), wird completed_at_administration wieder NULL und der Archivplot
-- verschwindet samt Fachdaten.
--
-- Die Freigabesperre aus 20260904000000/20260904000100 greift automatisch: die
-- neuen ci2027-Plots sind fuer anon und authenticated bis zum Stichtag
-- unsichtbar.
--
-- WARUM DIE ECKE DER SCHLUESSEL IST UND NICHT DIE IDs AUS properties
-- properties wurde aus dem Archiv vorbelegt. Die id eines Baums oder einer
-- Kante dort ist die id der bwi2022-Zeile (am lokalen Prod-Abzug: 15.889 von
-- 15.889 Baum-ids mit Treffer gehoeren zu bwi2022-Plots derselben Ecke, weitere
-- 3.287 zu bwi2012/ci2017). Ein Upsert ueber diese ids wuerde die Vorinventur
-- ueberschreiben. Aus demselben Grund wird properties.interval_name ignoriert,
-- es steht fast ueberall noch auf 'bwi2022'.
--
-- Upsert heisst deshalb: der Plot wird ueber (cluster_name, plot_name,
-- interval_name) eingefuegt oder aktualisiert und behaelt seine id. Die
-- Fachdaten darunter werden vollstaendig ersetzt -- ausser tree hat keine
-- Fachtabelle einen natuerlichen Schluessel, und nur so verschwinden auch
-- Zeilen, die zwischen zwei Abnahmen aus properties entfernt wurden. Beliebig
-- oft ausgefuehrt ergibt das denselben Archivstand.
--
-- WARUM DIE SPALTEN AUS DEM KATALOG KOMMEN
-- Die Schluessel in properties sind die Spaltennamen des Archivs (properties
-- wurde daraus erzeugt). insert_from_json() liest die Spaltenliste daher aus
-- pg_attribute: eine neue Archivspalte wie upper_diameter (20261013000000)
-- oder nesting_tree (20261017000000) wird ohne weitere Migration mitgenommen.
-- Unbekannte Schluessel (_deprecated, __validation_status__, dbh_previous ...)
-- fallen bei jsonb_populate_recordset heraus. JSON-null auf einer Spalte mit
-- Default ergibt den Default -- sonst scheiterten die NOT-NULL-Schadmerkmale
-- (damage_dead ... DEFAULT false) an jedem neuen Baum ohne Angabe.
--
-- WAS NICHT UEBERNOMMEN WIRD
--   * Baeume mit _deprecated = true: in einer Vorinventur entnommen oder
--     abgestorben (20260610091036/20260610091117), in ci2027 nicht mehr da.
--   * Stuetzpunkte ohne azimuth oder distance: leere Vorlagenzeilen der App;
--     beide Spalten sind NOT NULL.
--   * notes und plot_coordinates: stehen nicht in properties. plot_coordinates
--     ist ohnehin intervalluebergreifend eine Zeile je Ecke (20261014000000).
--
-- SCHULUNGSTRAKTE
-- werden wie alle anderen archiviert. 396 ihrer Ecken haben aber schon seit dem
-- Anlegen der Trakte einen ci2027-Plot, auf den records.plot_id zeigt. Den
-- aktualisiert die Abnahme wie jeden anderen. Eine Rueckgabe darf ihn nicht
-- loeschen (FK ON DELETE RESTRICT), sie leert dort nur die Fachdaten.
-- Sichtbarkeit: interval_release.exempt_training nimmt Schulungstrakte von der
-- Freigabesperre aus, ihre archivierten Daten sind also sofort oeffentlich.
-- Sollen sie gesperrt sein, ist das ein UPDATE auf dieser Spalte.
--
-- FEHLER BRECHEN DIE ABNAHME AB
-- Laesst sich eine Ecke nicht ins Archiv schreiben, schlaegt das UPDATE auf
-- records fehl und die Ecke bleibt unabgenommen. Abgenommen heisst damit immer
-- auch archiviert; das Verwaltungstool zeigt die Meldung im Snackbar an.
-- ============================================================================

SET search_path TO inventory_archive;

-- ============================================================================
-- 0. Index fuer das Ersetzen der Probekreise
-- ============================================================================
-- subplots_relative_position ist die einzige Fachtabelle ohne Index auf
-- plot_id. Ohne ihn kostet jedes Ersetzen und jedes Loeschen einer Ecke einen
-- Seq Scan ueber 342.000 Zeilen.
CREATE INDEX IF NOT EXISTS idx_subplots_relative_position_plot_id
    ON inventory_archive.subplots_relative_position (plot_id);

-- ============================================================================
-- 1. Generisches Einfuegen aus einem JSON-Array
-- ============================================================================
-- p_rows: Array von Objekten, deren Schluessel Spaltennamen von p_table sind.
-- id und intkey kommen nie aus dem JSON: id wuerde die Vorinventur treffen
-- (siehe oben), intkey ist UNIQUE und haelt dort ebenfalls den Schluessel der
-- Vorinventur.
-- p_conflict: Spaltenliste fuer ON CONFLICT ... DO UPDATE; NULL = reines INSERT.
CREATE OR REPLACE FUNCTION inventory_archive.insert_from_json(
    p_table    text,
    p_rows     jsonb,
    p_conflict text[] DEFAULT NULL
) RETURNS SETOF uuid
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
    v_rel     regclass := format('inventory_archive.%I', p_table)::regclass;
    v_cols    text;
    v_exprs   text;
    v_update  text;
    v_sql     text;
BEGIN
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RETURN;
    END IF;

    SELECT string_agg(quote_ident(a.attname), ', ' ORDER BY a.attnum),
           string_agg(CASE WHEN d.adbin IS NOT NULL
                           THEN format('COALESCE(x.%I, %s)', a.attname, pg_get_expr(d.adbin, d.adrelid))
                           ELSE format('x.%I', a.attname)
                      END, ', ' ORDER BY a.attnum),
           string_agg(format('%I = EXCLUDED.%I', a.attname, a.attname), ', ' ORDER BY a.attnum)
               FILTER (WHERE a.attname <> ALL (coalesce(p_conflict, '{}')))
      INTO v_cols, v_exprs, v_update
    FROM pg_attribute a
    LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
    WHERE a.attrelid = v_rel
      AND a.attnum > 0
      AND NOT a.attisdropped
      AND a.attgenerated = ''
      AND a.attname NOT IN ('id', 'intkey');

    v_sql := format(
        'INSERT INTO %s (%s) SELECT %s FROM jsonb_populate_recordset(NULL::%s, $1) x',
        v_rel, v_cols, v_exprs, v_rel
    );
    IF p_conflict IS NOT NULL THEN
        v_sql := v_sql || format(
            ' ON CONFLICT (%s) DO UPDATE SET %s',
            (SELECT string_agg(quote_ident(c), ', ') FROM unnest(p_conflict) c),
            v_update
        );
    END IF;

    RETURN QUERY EXECUTE v_sql || ' RETURNING id' USING p_rows;
END;
$$;

COMMENT ON FUNCTION inventory_archive.insert_from_json(text, jsonb, text[]) IS
    'Fuegt ein JSON-Array in eine Archivtabelle ein; Spalten aus dem Katalog, JSON-null ergibt den Spalten-Default, id/intkey nie aus dem JSON. Hilfsfunktion fuer sync_record_to_archive().';

-- ============================================================================
-- 2. Fachdaten eines Plots leeren
-- ============================================================================
-- Koordinaten- und derived-Tabellen haengen per ON DELETE CASCADE daran.
-- notes bleibt stehen: es kommt nicht aus properties.
CREATE OR REPLACE FUNCTION inventory_archive.clear_plot_children(p_plot_id uuid)
RETURNS void
LANGUAGE sql
SET search_path = ''
AS $$
    DELETE FROM inventory_archive.position                   WHERE plot_id = p_plot_id;
    DELETE FROM inventory_archive.tree                       WHERE plot_id = p_plot_id;
    DELETE FROM inventory_archive.deadwood                   WHERE plot_id = p_plot_id;
    DELETE FROM inventory_archive.regeneration               WHERE plot_id = p_plot_id;
    DELETE FROM inventory_archive.structure_lt4m             WHERE plot_id = p_plot_id;
    DELETE FROM inventory_archive.structure_gt4m             WHERE plot_id = p_plot_id;
    DELETE FROM inventory_archive.edges                      WHERE plot_id = p_plot_id;
    DELETE FROM inventory_archive.subplots_relative_position WHERE plot_id = p_plot_id;
    DELETE FROM inventory_archive.plot_support_points        WHERE plot_id = p_plot_id;
$$;

COMMENT ON FUNCTION inventory_archive.clear_plot_children(uuid) IS
    'Loescht alle aus properties stammenden Fachdaten eines Archivplots. Hilfsfunktion fuer sync_record_to_archive()/remove_record_from_archive().';

-- ============================================================================
-- 3. Eine Ecke ins Archiv schreiben (Upsert)
-- ============================================================================
-- Gibt die id des Archivplots zurueck.
-- Auch von Hand aufrufbar, etwa fuer Ecken, die vor dieser Migration
-- abgenommen wurden:
--   SELECT inventory_archive.sync_record_to_archive(id)
--   FROM public.records WHERE completed_at_administration IS NOT NULL;
CREATE OR REPLACE FUNCTION inventory_archive.sync_record_to_archive(
    p_record_id     uuid,
    p_interval_name text DEFAULT 'ci2027'
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    rec       public.records;
    v_props   jsonb;
    v_plot_id uuid;
    v_pc_id   uuid;
    v_parent  jsonb;
BEGIN
    SELECT * INTO rec FROM public.records WHERE id = p_record_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Datensatz % existiert nicht', p_record_id;
    END IF;
    IF rec.cluster_id IS NULL OR rec.cluster_name IS NULL OR rec.plot_name IS NULL THEN
        RAISE EXCEPTION 'Datensatz % hat keine Traktecke (cluster_id/cluster_name/plot_name), Archivierung nicht moeglich', p_record_id;
    END IF;

    v_props := coalesce(rec.properties, '{}'::jsonb);

    -- Plot: Identitaet der Ecke aus records, nicht aus properties
    SELECT id INTO v_plot_id
    FROM inventory_archive.insert_from_json(
        'plot',
        jsonb_build_array(v_props || jsonb_build_object(
            'interval_name', p_interval_name,
            'cluster_id',    rec.cluster_id,
            'cluster_name',  rec.cluster_name,
            'plot_name',     rec.plot_name
        )),
        ARRAY['cluster_name', 'plot_name', 'interval_name']
    ) AS t(id);

    PERFORM inventory_archive.clear_plot_children(v_plot_id);

    v_parent := jsonb_build_object('plot_id', v_plot_id);

    -- position zuerst: der Trigger auf edges berechnet die Kantengeometrie
    -- vom position_mean des Plots aus. Die App liefert die Punkte als
    -- {latitude, longitude}; geometry nimmt EWKT als Texteingabe.
    IF jsonb_typeof(v_props->'position') = 'object'
       AND v_props->'position'->'position_mean'->>'latitude'  IS NOT NULL
       AND v_props->'position'->'position_mean'->>'longitude' IS NOT NULL
    THEN
        PERFORM inventory_archive.insert_from_json(
            'position',
            jsonb_build_array(
                (v_props->'position')
                || v_parent
                || jsonb_build_object(
                    'position_mean', format('SRID=4326;POINT(%s %s)',
                        v_props->'position'->'position_mean'->>'longitude',
                        v_props->'position'->'position_mean'->>'latitude'),
                    'position_median', CASE
                        WHEN v_props->'position'->'position_median'->>'latitude'  IS NOT NULL
                         AND v_props->'position'->'position_median'->>'longitude' IS NOT NULL
                        THEN format('SRID=4326;POINT(%s %s)',
                            v_props->'position'->'position_median'->>'longitude',
                            v_props->'position'->'position_median'->>'latitude')
                    END
                )
            )
        );
    END IF;

    PERFORM inventory_archive.insert_from_json('edges',
        (SELECT jsonb_agg(el || v_parent) FROM jsonb_array_elements(
            CASE WHEN jsonb_typeof(v_props->'edges') = 'array' THEN v_props->'edges' END) el));

    PERFORM inventory_archive.insert_from_json('tree',
        (SELECT jsonb_agg(el || v_parent) FROM jsonb_array_elements(
            CASE WHEN jsonb_typeof(v_props->'tree') = 'array' THEN v_props->'tree' END) el
         WHERE coalesce((el->>'_deprecated')::boolean, false) = false));

    PERFORM inventory_archive.insert_from_json('deadwood',
        (SELECT jsonb_agg(el || v_parent) FROM jsonb_array_elements(
            CASE WHEN jsonb_typeof(v_props->'deadwood') = 'array' THEN v_props->'deadwood' END) el));

    PERFORM inventory_archive.insert_from_json('regeneration',
        (SELECT jsonb_agg(el || v_parent) FROM jsonb_array_elements(
            CASE WHEN jsonb_typeof(v_props->'regeneration') = 'array' THEN v_props->'regeneration' END) el));

    PERFORM inventory_archive.insert_from_json('structure_lt4m',
        (SELECT jsonb_agg(el || v_parent) FROM jsonb_array_elements(
            CASE WHEN jsonb_typeof(v_props->'structure_lt4m') = 'array' THEN v_props->'structure_lt4m' END) el));

    PERFORM inventory_archive.insert_from_json('structure_gt4m',
        (SELECT jsonb_agg(el || v_parent) FROM jsonb_array_elements(
            CASE WHEN jsonb_typeof(v_props->'structure_gt4m') = 'array' THEN v_props->'structure_gt4m' END) el));

    PERFORM inventory_archive.insert_from_json('plot_support_points',
        (SELECT jsonb_agg(el || v_parent) FROM jsonb_array_elements(
            CASE WHEN jsonb_typeof(v_props->'plot_support_points') = 'array' THEN v_props->'plot_support_points' END) el
         WHERE el->>'azimuth' IS NOT NULL AND el->>'distance' IS NOT NULL));

    -- Probekreise haengen zusaetzlich an der Ecke in plot_coordinates; deren
    -- Trigger berechnet daraus die Kreisgeometrie.
    IF jsonb_typeof(v_props->'subplots_relative_position') = 'array'
       AND jsonb_array_length(v_props->'subplots_relative_position') > 0
    THEN
        SELECT pc.id INTO v_pc_id
        FROM inventory_archive.plot_coordinates pc
        WHERE pc.cluster_name = rec.cluster_name AND pc.plot_name = rec.plot_name;
        IF v_pc_id IS NULL THEN
            RAISE EXCEPTION 'Trakt % Ecke %: keine Zeile in plot_coordinates, Probekreise koennen nicht archiviert werden',
                rec.cluster_name, rec.plot_name;
        END IF;

        PERFORM inventory_archive.insert_from_json('subplots_relative_position',
            (SELECT jsonb_agg(el || v_parent || jsonb_build_object('plot_coordinates_id', v_pc_id))
             FROM jsonb_array_elements(v_props->'subplots_relative_position') el));
    END IF;

    RETURN v_plot_id;
EXCEPTION
    WHEN OTHERS THEN
        -- Trakt und Ecke in die Meldung, damit das Verwaltungstool sagen kann,
        -- woran die Abnahme gescheitert ist.
        RAISE EXCEPTION 'Archivierung Trakt % Ecke % fehlgeschlagen: %', rec.cluster_name, rec.plot_name, SQLERRM
            USING ERRCODE = SQLSTATE;
END;
$$;

COMMENT ON FUNCTION inventory_archive.sync_record_to_archive(uuid, text) IS
    'Schreibt records.properties einer Ecke als Plot des Intervalls (Default ci2027) ins Archiv. Upsert: Plot ueber (cluster_name, plot_name, interval_name), Fachdaten werden ersetzt.';

-- ============================================================================
-- 4. Eine Ecke aus dem Archiv entfernen
-- ============================================================================
-- Zeigt records oder record_changes auf den Plot (die ci2027-Plots, die beim
-- Anlegen der Schulungstrakte entstanden sind), bleibt er stehen und verliert
-- nur seine Fachdaten. Sonst wird er geloescht.
CREATE OR REPLACE FUNCTION inventory_archive.remove_record_from_archive(
    p_record_id     uuid,
    p_interval_name text DEFAULT 'ci2027'
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_plot_id uuid;
BEGIN
    SELECT p.id INTO v_plot_id
    FROM inventory_archive.plot p
    JOIN public.records r ON r.cluster_name = p.cluster_name AND r.plot_name = p.plot_name
    WHERE r.id = p_record_id
      AND p.interval_name = p_interval_name;

    IF v_plot_id IS NULL THEN
        RETURN NULL;
    END IF;

    IF EXISTS (SELECT 1 FROM public.records x WHERE x.plot_id = v_plot_id)
       OR EXISTS (SELECT 1 FROM public.record_changes x WHERE x.plot_id = v_plot_id)
    THEN
        PERFORM inventory_archive.clear_plot_children(v_plot_id);
    ELSE
        DELETE FROM inventory_archive.plot WHERE id = v_plot_id;
    END IF;

    RETURN v_plot_id;
END;
$$;

COMMENT ON FUNCTION inventory_archive.remove_record_from_archive(uuid, text) IS
    'Loescht den Archivplot einer Ecke im Intervall (Default ci2027) samt Fachdaten. Gegenstueck zu sync_record_to_archive(); ein von records/record_changes referenzierter Plot bleibt stehen und wird nur geleert.';

-- Schreiben ins Archiv ist kein Recht von anon/authenticated. Die Trigger-
-- funktion unten braucht kein EXECUTE beim Aufrufer.
REVOKE ALL ON FUNCTION inventory_archive.insert_from_json(text, jsonb, text[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION inventory_archive.clear_plot_children(uuid)              FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION inventory_archive.sync_record_to_archive(uuid, text)   FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION inventory_archive.remove_record_from_archive(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION inventory_archive.sync_record_to_archive(uuid, text)     TO service_role;
GRANT EXECUTE ON FUNCTION inventory_archive.remove_record_from_archive(uuid, text) TO service_role;

-- ============================================================================
-- 5. Trigger auf public.records
-- ============================================================================
-- Feuert bei
--   * Abnahme                (NULL -> Zeitpunkt)     -> Upsert
--   * erneuter Abnahme       (Zeitpunkt -> Zeitpunkt; FinishDialog setzt bei
--                             jedem Klick new Date()) -> Upsert
--   * Aenderung von properties an einer abgenommenen Ecke -> Upsert, damit
--     das Archiv nie einen anderen Stand haelt als die abgenommene Ecke
--   * Ruecknahme             (Zeitpunkt -> NULL)     -> Loeschen
CREATE OR REPLACE FUNCTION inventory_archive.on_record_administration_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NEW.completed_at_administration IS NULL THEN
        PERFORM inventory_archive.remove_record_from_archive(NEW.id);
    ELSE
        PERFORM inventory_archive.sync_record_to_archive(NEW.id);
    END IF;
    RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION inventory_archive.on_record_administration_change() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS sync_inventory_archive ON public.records;
CREATE TRIGGER sync_inventory_archive
    AFTER UPDATE OF completed_at_administration, properties ON public.records
    FOR EACH ROW
    WHEN (
        OLD.completed_at_administration IS DISTINCT FROM NEW.completed_at_administration
        OR (NEW.completed_at_administration IS NOT NULL AND OLD.properties IS DISTINCT FROM NEW.properties)
    )
    EXECUTE FUNCTION inventory_archive.on_record_administration_change();

COMMENT ON TRIGGER sync_inventory_archive ON public.records IS
    'Abnahme durch die BIL schreibt die Ecke nach inventory_archive (ci2027), Ruecknahme loescht sie wieder. Siehe 20261018000000.';

NOTIFY pgrst, 'reload schema';
