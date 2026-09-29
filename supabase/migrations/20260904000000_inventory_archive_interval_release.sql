-- ============================================================================
-- MIGRATION: Freigabesteuerung fuer Inventurintervalle im Archiv (Teil 1/2)
-- ============================================================================
-- Konzept "Archivfreigabe CI 2027".
--
-- Ziel: Die Aufnahmen der laufenden Inventur koennen nach inventory_archive
-- geladen werden, bevor sie oeffentlich sein duerfen. Sichtbar sind sie bis zu
-- einem Stichtag nur fuer interne Nutzende; der Stichtag steht heute noch nicht
-- fest und muss ohne Deployment setzbar und verschiebbar sein.
--
-- Diese Migration legt nur die Datengrundlage an (Tabelle + Praedikate). Sie
-- aendert noch KEIN Sichtbarkeitsverhalten -- das tut erst Teil 2
-- (20260904000100_inventory_archive_release_gate.sql) mit den Policies.
--
-- Zwei Entwurfsentscheidungen, die den Rest erklaeren:
--
--   1. OPT-IN-SPERRE. Ein Intervall ohne Zeile in interval_release gilt als
--      freigegeben. Nur ci2027 bekommt eine Zeile. Damit koennen die
--      Bestandsintervalle (bwi1987 ... bwi2022, ci2012, ci2017) gar nicht
--      versehentlich gesperrt werden.
--
--   2. MENGE STATT PRAEDIKAT PRO ZEILE. Die Policies fragen spaeter
--      "plot_id NOT IN (SELECT ... FROM embargoed_plots())". Postgres baut
--      daraus einen gehashten SubPlan und ruft die Funktion einmal pro
--      Abfrage (bzw. pro parallelem Worker) auf statt einmal pro Zeile.
--      Gemessen am lokalen Produktionsabzug -- 783.532 Plots, 1,72 Mio.
--      Baeume -- mit count(*) als authenticated:
--
--        tree, Full Scan, grosses gesperrtes Intervall
--          ohne Policy                                52 ms
--          Mengen-Subquery (diese Loesung)           446 ms
--          Skalarfunktion pro Zeile               15.495 ms
--
--        plot WHERE interval_name = 'bwi2022' (261.312 Zeilen)
--          ohne Policy                                30 ms
--          mit Policy, 0 gesperrte Plots (heute)     100 ms
--          mit Policy, 260.912 gesperrte Plots       222 ms
--
--      Aus demselben Grund steht is_internal() INNERHALB der Mengenfunktion
--      und nicht als "OR is_internal()" in der Policy: dort waere es pro
--      Zeile ausgewertet worden. In der Funktion ist es ein Qual ohne
--      Spaltenbezug und wird als One-Time-Filter genau einmal geprueft.
--
--      PARALLEL SAFE gehoert zu dieser Entscheidung: ohne die Markierung
--      verliert jede betroffene Abfrage den parallelen Scan (im mittleren
--      Fall oben 143 ms statt 100 ms). Die Funktionen lesen nur.
-- ============================================================================

SET search_path TO inventory_archive;

-- ============================================================================
-- TABELLE: interval_release -- der Stichtag als Datum, nicht als Schalter
-- ============================================================================
-- published_at IS NULL      -> bis auf Weiteres gesperrt (Zustand beim Laden)
-- published_at > now()      -> Termin steht, noch nicht erreicht
-- published_at <= now()     -> freigegeben, ohne dass jemand etwas ausloest
--
-- Ein Datum statt eines Booleans, weil dann am Stichtag selbst nichts passieren
-- muss: kein Cronjob, kein Deployment, kein Wartungsfenster. Ausserdem ist der
-- Zustand im Test in beide Richtungen stellbar.
--
-- exempt_training = true nimmt Schulungstrakte (cluster.is_training) von der
-- Sperre aus. Das ist nicht Kosmetik, sondern die Bedingung dafuer, dass diese
-- Migration nichts am heutigen Verhalten aendert: im Archiv liegen bereits
-- 396 ci2027-Plots (99 Schulungstrakte x 4 Ecken, ohne Messwerte), die anon und
-- authenticated heute sehen. Sollen sie doch mitgesperrt werden, ist das ein
-- UPDATE auf dieser Spalte und keine neue Migration.
CREATE TABLE IF NOT EXISTS inventory_archive.interval_release (
    interval_name   text PRIMARY KEY REFERENCES lookup.lookup_interval (code)
                         ON UPDATE RESTRICT ON DELETE RESTRICT,
    published_at    timestamptz NULL,
    exempt_training boolean NOT NULL DEFAULT true,
    note            text NULL,
    updated_at      timestamptz NOT NULL DEFAULT now(),
    updated_by      uuid NULL REFERENCES auth.users (id) ON DELETE SET NULL
);

COMMENT ON TABLE inventory_archive.interval_release IS
    'Freigabesteuerung pro Inventurintervall. Opt-in-Sperre: Intervalle ohne Zeile sind freigegeben. Schreiben nur service_role/postgres.';
COMMENT ON COLUMN inventory_archive.interval_release.published_at IS
    'Stichtag. NULL = bis auf Weiteres gesperrt, Zukunft = Termin steht, Vergangenheit = oeffentlich sichtbar.';
COMMENT ON COLUMN inventory_archive.interval_release.exempt_training IS
    'true: Plots in Schulungstrakten (cluster.is_training) bleiben trotz Sperre sichtbar.';

-- Rechte: lesen darf jeder -- das Freigabedatum ist keine Verschlusssache und
-- die Oberflaeche kann "oeffentlich ab ..." anzeigen. Schreiben ist ein
-- administrativer Akt.
--
-- Das REVOKE ist nicht optional: 20250115140817 setzt
-- ALTER DEFAULT PRIVILEGES ... GRANT ALL ON TABLES TO anon, authenticated,
-- service_role fuer dieses Schema. Ohne das REVOKE haetten anon und
-- authenticated INSERT/UPDATE/DELETE auf der Freigabetabelle -- die RLS unten
-- wuerde es zwar blockieren, aber auf eine Zeile Konfiguration will man sich
-- nicht doppelt verlassen.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON inventory_archive.interval_release
    FROM anon, authenticated;
GRANT SELECT ON inventory_archive.interval_release TO anon, authenticated, ti_read;

ALTER TABLE inventory_archive.interval_release ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_archive.interval_release FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS default_select_anon_and_authenticated_and_ti_read
    ON inventory_archive.interval_release;
CREATE POLICY default_select_anon_and_authenticated_and_ti_read
    ON inventory_archive.interval_release
    FOR SELECT TO anon, authenticated, ti_read
    USING (true);

-- ============================================================================
-- FUNKTION: is_internal() -- wer sieht gesperrte Intervalle trotzdem
-- ============================================================================
-- Intern sind Administratoren von Organisationen. Die Definition greift die
-- bereits etablierte Admin-Pruefung aus guard_records_properties_admin()
-- (20260625000000) auf und erweitert sie um die Organisations-Admins.
--
-- ti_read gehoert ebenfalls zu "intern", steht hier aber bewusst NICHT drin:
-- Rollenzugehoerigkeit wird ueber die TO-Liste der Policies ausgedrueckt
-- (Teil 2), nicht hier. Das hat einen harten Grund -- in einer SECURITY
-- DEFINER-Funktion ist current_user der Eigentuemer (postgres) und nicht der
-- aufrufende Login. Eine Rollenpruefung waere an dieser Stelle schlicht falsch.
CREATE OR REPLACE FUNCTION inventory_archive.is_internal()
RETURNS boolean
LANGUAGE sql STABLE PARALLEL SAFE SECURITY DEFINER SET search_path = '' AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.users_profile p
        WHERE p.id = auth.uid()
          AND (p.is_admin OR p.is_organization_admin)
    )
    OR EXISTS (
        SELECT 1
        FROM public.users_permissions up
        LEFT JOIN public.organizations o ON o.id = up.organization_id
        WHERE up.user_id = auth.uid()
          AND (up.is_organization_admin OR o.type = 'root')
    );
$$;

COMMENT ON FUNCTION inventory_archive.is_internal() IS
    'true fuer Administratoren von Organisationen (users_profile.is_admin/is_organization_admin, users_permissions.is_organization_admin, Root-Organisation). Enthaelt bewusst keine Rollenpruefung: in SECURITY DEFINER ist current_user der Eigentuemer.';

-- ============================================================================
-- FUNKTIONEN: die gesperrten Zeilenmengen
-- ============================================================================
-- embargoed_plots() ist die einzige Stelle, an der die Regel steht. Alle
-- anderen Funktionen und alle 15 Policies leiten sich davon ab.
--
-- Sichtbarkeit dieser Funktionen: anon und authenticated brauchen EXECUTE,
-- weil Policy-Ausdruecke mit den Rechten des Aufrufers laufen. Ein direkter
-- Aufruf liefert damit die uuids der gesperrten Zeilen -- keine Attribute,
-- keine Koordinaten, keine Messwerte. Das ist der bewusst in Kauf genommene
-- Preis dafuer, dass die Pruefung einmal pro Abfrage statt einmal pro Zeile
-- laeuft.
CREATE OR REPLACE FUNCTION inventory_archive.embargoed_plots()
RETURNS TABLE (plot_id uuid)
LANGUAGE sql STABLE PARALLEL SAFE SECURITY DEFINER SET search_path = '' AS $$
    SELECT p.id
    FROM inventory_archive.plot p
    JOIN inventory_archive.interval_release r ON r.interval_name = p.interval_name
    WHERE NOT inventory_archive.is_internal()
      AND (r.published_at IS NULL OR r.published_at > now())
      AND NOT (
            r.exempt_training
            AND EXISTS (
                SELECT 1 FROM inventory_archive.cluster c
                WHERE c.id = p.cluster_id AND c.is_training
            )
      );
$$;

COMMENT ON FUNCTION inventory_archive.embargoed_plots() IS
    'Plot-IDs, die der aufrufenden Rolle wegen eines noch nicht erreichten Stichtags verborgen bleiben. Leer fuer interne Nutzende und fuer freigegebene Intervalle.';

-- Die drei Koordinatentabellen haengen nicht am Plot, sondern an ihrem
-- Elterndatensatz. Der Umweg ueber eine eigene Funktion ist notwendig, nicht
-- bequem: ein Unterabfrage auf inventory_archive.tree direkt in der Policy
-- unterlaege selbst der RLS von tree -- die gesperrte Baumzeile waere dort
-- unsichtbar, das NOT IN damit wahr und die Koordinate faelschlich sichtbar.
-- SECURITY DEFINER schliesst diese Umkehrung aus.
CREATE OR REPLACE FUNCTION inventory_archive.embargoed_trees()
RETURNS TABLE (tree_id uuid)
LANGUAGE sql STABLE PARALLEL SAFE SECURITY DEFINER SET search_path = '' AS $$
    SELECT t.id
    FROM inventory_archive.tree t
    WHERE t.plot_id IN (SELECT e.plot_id FROM inventory_archive.embargoed_plots() e);
$$;

CREATE OR REPLACE FUNCTION inventory_archive.embargoed_edges()
RETURNS TABLE (edge_id uuid)
LANGUAGE sql STABLE PARALLEL SAFE SECURITY DEFINER SET search_path = '' AS $$
    SELECT e.id
    FROM inventory_archive.edges e
    WHERE e.plot_id IN (SELECT x.plot_id FROM inventory_archive.embargoed_plots() x);
$$;

CREATE OR REPLACE FUNCTION inventory_archive.embargoed_subplots()
RETURNS TABLE (subplot_id uuid)
LANGUAGE sql STABLE PARALLEL SAFE SECURITY DEFINER SET search_path = '' AS $$
    SELECT s.id
    FROM inventory_archive.subplots_relative_position s
    WHERE s.plot_id IN (SELECT x.plot_id FROM inventory_archive.embargoed_plots() x);
$$;

COMMENT ON FUNCTION inventory_archive.embargoed_trees() IS
    'Baum-IDs gesperrter Plots. Fuer die Policy auf tree_coordinates.';
COMMENT ON FUNCTION inventory_archive.embargoed_edges() IS
    'Kanten-IDs gesperrter Plots. Fuer die Policy auf edges_coordinates.';
COMMENT ON FUNCTION inventory_archive.embargoed_subplots() IS
    'IDs der Unterflaechen gesperrter Plots. Fuer die Policy auf subplots_relative_position_coordinates.';

GRANT EXECUTE ON FUNCTION
    inventory_archive.is_internal(),
    inventory_archive.embargoed_plots(),
    inventory_archive.embargoed_trees(),
    inventory_archive.embargoed_edges(),
    inventory_archive.embargoed_subplots()
    TO anon, authenticated, service_role;

-- ============================================================================
-- ci2027 sperren, Stichtag offen
-- ============================================================================
-- ON CONFLICT DO NOTHING: ein spaeterer Lauf dieser Migration darf einen
-- bereits gesetzten Stichtag nicht zurueckdrehen.
INSERT INTO inventory_archive.interval_release (interval_name, published_at, note)
VALUES ('ci2027', NULL, 'Stichtag noch nicht festgelegt')
ON CONFLICT (interval_name) DO NOTHING;

NOTIFY pgrst, 'reload schema';
