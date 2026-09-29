-- ============================================================================
-- MIGRATION: Freigabesperre auf den Archivtabellen (Teil 2/2)
-- ============================================================================
-- Konzept "Archivfreigabe CI 2027". Setzt 20260904000000 voraus.
--
-- Diese Migration aendert am heutigen Verhalten nichts: gesperrt ist nur das
-- Intervall ci2027, und dessen einzige bereits vorhandene Zeilen sind die 396
-- Plots der 99 Schulungstrakte, die ueber exempt_training ausgenommen bleiben.
-- embargoed_plots() liefert damit heute die leere Menge, und eine leere Menge
-- in einem NOT IN laesst jede Zeile durch. Wirksam wird die Sperre erst mit
-- den ci2027-Aufnahmedaten.
--
-- WARUM RESTRICTIVE
-- Auf den Archivtabellen liegen bereits permissive Policies mit USING (true)
-- (20250115140841): default_select_ti_read_and_authenticated auf allen Tabellen,
-- default_select_anon auf allen ausser den Geometrietabellen. Permissive
-- Policies werden mit ODER verknuepft -- eine weitere permissive Regel neben
-- einem USING (true) waere wirkungslos. Restriktive Policies werden mit UND
-- verknuepft. Damit gilt:
--
--   * die bestehende Schicht entscheidet weiterhin, WER WELCHE Tabelle sieht
--     (inklusive "anon sieht keine Geometrien"), unveraendert;
--   * die neue Schicht entscheidet nur, AB WANN.
--
-- Nebeneffekt, der hier den Ausschlag gab: ein erneuter Aufruf von
-- enable_rls_for_schema('inventory_archive', ...) -- etwa nach einem Restore --
-- legt die gleichnamigen default_select_*-Policies neu an und wuerde eine in
-- sie hineingeschriebene Bedingung stillschweigend entfernen. Eine eigene
-- restriktive Policy ueberlebt das.
--
-- WARUM NUR anon UND authenticated IN DER TO-LISTE
-- ti_read ist laut Festlegung intern und soll die Daten sofort sehen; steht die
-- Rolle nicht in der TO-Liste, wird die Policy fuer sie gar nicht erst
-- ausgewertet -- die grossen Auswertungsabfragen ueber ti_read behalten damit
-- exakt ihren heutigen Plan. postgres und service_role haben BYPASSRLS und sind
-- ohnehin nicht betroffen; das ist die dokumentierte Grenze des Verfahrens.
-- Preis der expliziten Liste: eine spaeter angelegte Leserolle waere nicht
-- erfasst. Dagegen sichert der Test test_inventory_archive_release_gate.sql ab.
-- ============================================================================

SET search_path TO inventory_archive;

-- ============================================================================
-- Die 15 gesperrten Tabellen und ihr Anker
-- ============================================================================
-- Jede Zeile im Archiv haengt am Intervall ihres Plots. Unterschiedlich ist nur
-- die Tiefe: plot traegt interval_name selbst, elf Fachtabellen haengen ueber
-- plot_id daran, die drei Koordinatentabellen ueber ihren Elterndatensatz.
--
-- Nicht gesperrt: cluster und cluster_move (intervalluebergreifend, ohne
-- Aufnahmewerte), table_template (leere Vorlage) und interval_release selbst.
--
-- Die Liste steht bewusst ausgeschrieben da und wird nicht aus dem Katalog
-- abgeleitet: eine neue Tabelle im Schema soll auffallen und nicht automatisch
-- eine Regel bekommen, die vielleicht gar nicht passt. Der Abgleich unten
-- erzwingt genau das.
DO $$
DECLARE
    spec record;
BEGIN
    FOR spec IN
        SELECT * FROM (VALUES
            ('plot',                                   'id',                            'embargoed_plots',    'plot_id'),
            ('plot_coordinates',                       'plot_id',                       'embargoed_plots',    'plot_id'),
            ('plot_support_points',                    'plot_id',                       'embargoed_plots',    'plot_id'),
            ('notes',                                  'plot_id',                       'embargoed_plots',    'plot_id'),
            ('tree',                                   'plot_id',                       'embargoed_plots',    'plot_id'),
            ('position',                               'plot_id',                       'embargoed_plots',    'plot_id'),
            ('edges',                                  'plot_id',                       'embargoed_plots',    'plot_id'),
            ('regeneration',                           'plot_id',                       'embargoed_plots',    'plot_id'),
            ('structure_lt4m',                         'plot_id',                       'embargoed_plots',    'plot_id'),
            ('structure_gt4m',                         'plot_id',                       'embargoed_plots',    'plot_id'),
            ('deadwood',                               'plot_id',                       'embargoed_plots',    'plot_id'),
            ('subplots_relative_position',             'plot_id',                       'embargoed_plots',    'plot_id'),
            ('tree_coordinates',                       'tree_id',                       'embargoed_trees',    'tree_id'),
            ('edges_coordinates',                      'edge_id',                       'embargoed_edges',    'edge_id'),
            ('subplots_relative_position_coordinates', 'subplots_relative_position_id',  'embargoed_subplots', 'subplot_id')
        ) AS t(table_name, id_column, source_function, source_column)
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS release_gate ON inventory_archive.%I', spec.table_name);
        EXECUTE format(
            'CREATE POLICY release_gate ON inventory_archive.%I '
            'AS RESTRICTIVE FOR SELECT TO anon, authenticated '
            'USING (%I NOT IN (SELECT e.%I FROM inventory_archive.%I() e))',
            spec.table_name, spec.id_column, spec.source_column, spec.source_function
        );
    END LOOP;
END $$;

-- ============================================================================
-- Abgleich: keine Basistabelle ohne Entscheidung
-- ============================================================================
-- Schlaegt fehl, wenn eine Tabelle im Schema weder eine release_gate-Policy hat
-- noch ausdruecklich ausgenommen ist. Der Fehler ist gewollt: eine neue
-- Archivtabelle soll beim Deployment auffallen und nicht still ungeschuetzt
-- bleiben.
DO $$
DECLARE
    ungated text[];
BEGIN
    SELECT array_agg(c.relname ORDER BY c.relname) INTO ungated
    FROM pg_class c
    WHERE c.relnamespace = 'inventory_archive'::regnamespace
      AND c.relkind = 'r'
      AND c.relname NOT IN ('cluster', 'cluster_move', 'table_template', 'interval_release')
      AND NOT EXISTS (
          SELECT 1 FROM pg_policy p
          WHERE p.polrelid = c.oid AND p.polname = 'release_gate'
      );

    IF ungated IS NOT NULL THEN
        RAISE EXCEPTION
            'Archivtabellen ohne release_gate-Policy: %. Entweder in die Liste oben aufnehmen oder ausdruecklich ausnehmen.',
            array_to_string(ungated, ', ');
    END IF;
END $$;

-- Gegenprobe: heute darf sich nichts aendern. Gibt es zum Zeitpunkt des
-- Deployments bereits gesperrte Zeilen, ist das kein Fehler, aber eine Meldung
-- wert -- dann verschwinden mit dieser Migration tatsaechlich Zeilen aus der
-- Sicht von anon und authenticated.
DO $$
DECLARE
    betroffen bigint;
BEGIN
    SELECT count(*) INTO betroffen FROM inventory_archive.embargoed_plots();
    IF betroffen > 0 THEN
        RAISE NOTICE 'release_gate aktiv: % Plot(s) sind ab sofort nur noch intern sichtbar.', betroffen;
    ELSE
        RAISE NOTICE 'release_gate installiert, aktuell 0 gesperrte Plots -- Sichtbarkeit unveraendert.';
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';
