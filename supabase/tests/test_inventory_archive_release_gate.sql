-- ============================================================================
-- DRY-RUN TEST: Sichtbarkeitsmatrix der Archivfreigabe (release_gate)
-- ============================================================================
-- Prueft die beiden Zusagen der Migrationen 20260904000000 / 20260904000100:
--
--   1. WIRKSAM   -- eine echte ci2027-Aufnahme (Plot in einem Trakt, der kein
--                   Schulungstrakt ist, samt Baum und Koordinaten) ist fuer
--                   anon und authenticated unsichtbar, solange der Stichtag
--                   nicht erreicht ist, und sichtbar, sobald er es ist.
--   2. UNVERAENDERT -- Bestandsintervalle, Schulungstrakte und die Regel
--                   "anon sieht keine Geometrien" verhalten sich in jedem
--                   Zustand des Stichtags exakt wie vorher.
--
-- Der Stichtag wird dafuer durch alle drei Zustaende gefahren:
-- NULL (gesperrt), Zukunft (Termin steht), Vergangenheit (freigegeben).
--
-- SAFE BY DESIGN (gegen Produktion lauffaehig):
--   * genau ein BEGIN und ein ROLLBACK, kein COMMIT
--   * Fixtures (Nutzende, Plot, Baum, Koordinaten) existieren nur innerhalb
--     der Transaktion
--   * der echte ci2027-Plot wird angelegt, nicht gesucht -- es wird keine
--     vorhandene Zeile veraendert
--
-- Run:  ./run_release_gate.sh [--remote]
-- ============================================================================
\set ON_ERROR_STOP on
\pset pager off
\timing off

BEGIN;

\echo ''
\echo '=== Umgebung =============================================================='
SELECT current_database() AS database,
       current_setting('server_version') AS pg_version,
       session_user,
       now() AS at;

\echo '=== Freigabestand ========================================================='
SELECT interval_name, published_at, exempt_training, note
FROM inventory_archive.interval_release
ORDER BY interval_name;

\echo '=== release_gate-Policies ================================================='
SELECT c.relname AS tabelle,
       p.polpermissive AS permissive,
       p.polroles::regrole[] AS rollen,
       pg_get_expr(p.polqual, p.polrelid) AS bedingung
FROM pg_policy p
JOIN pg_class c ON c.oid = p.polrelid
WHERE p.polname = 'release_gate'
  AND c.relnamespace = 'inventory_archive'::regnamespace
ORDER BY c.relname;

-- ── Ergebnistabelle (gewoehnliche Tabelle, verschwindet mit dem ROLLBACK) ────
CREATE TABLE public._rg_results (
    ord      int,
    zustand  text,
    persona  text,
    objekt   text,
    erwartet int,
    gesehen  text,
    status   text
);

DO $$
DECLARE
    -- Fixtures
    v_extern_uid  uuid := gen_random_uuid();
    v_admin_uid   uuid := gen_random_uuid();
    v_org         uuid;
    v_cluster     uuid;
    v_cluster_no  int;
    v_plot_no     int;
    v_bestand     uuid;
    v_training    uuid;
    v_real        uuid;
    v_tree        uuid;
    v_ti_read_ok  boolean := false;
    -- Schleifen
    zst           record;
    pers          record;
    obj           record;
    v_count       int;
    v_seen        text;
    v_expected    int;
    v_ord         int := 0;
BEGIN
    -- ────────────────────────────────────────────────────────────────────
    -- Vorbedingungen
    -- ────────────────────────────────────────────────────────────────────
    IF to_regclass('inventory_archive.interval_release') IS NULL THEN
        RAISE EXCEPTION 'Setup: Migration 20260904000000 ist nicht eingespielt.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'release_gate') THEN
        RAISE EXCEPTION 'Setup: Migration 20260904000100 ist nicht eingespielt.';
    END IF;

    -- Referenzzeile aus dem Bestand
    SELECT id INTO v_bestand FROM inventory_archive.plot
    WHERE interval_name = 'bwi2022' LIMIT 1;
    IF v_bestand IS NULL THEN
        RAISE EXCEPTION 'Setup: kein bwi2022-Plot vorhanden.';
    END IF;

    -- Schulungstrakt-Ecke aus ci2027 (kann fehlen -- dann entfaellt die Probe)
    SELECT p.id INTO v_training
    FROM inventory_archive.plot p
    JOIN inventory_archive.cluster c ON c.id = p.cluster_id
    WHERE p.interval_name = 'ci2027' AND c.is_training
    LIMIT 1;

    -- ────────────────────────────────────────────────────────────────────
    -- Fixtures: ein externer und ein interner (Org-Admin) Zugang
    -- ────────────────────────────────────────────────────────────────────
    INSERT INTO public.organizations (name, type) VALUES ('_rg_org', 'provider')
    RETURNING id INTO v_org;

    INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, created_at, updated_at)
    VALUES
        ('00000000-0000-0000-0000-000000000000', v_extern_uid, 'authenticated', 'authenticated', 'rg_extern@releasegate.test', '', now(), now()),
        ('00000000-0000-0000-0000-000000000000', v_admin_uid,  'authenticated', 'authenticated', 'rg_admin@releasegate.test',  '', now(), now());
    INSERT INTO public.users_profile (id, email, is_admin, is_organization_admin) VALUES
        (v_extern_uid, 'rg_extern@releasegate.test', false, false),
        (v_admin_uid,  'rg_admin@releasegate.test',  false, true);
    INSERT INTO public.users_permissions (user_id, organization_id, created_by) VALUES
        (v_extern_uid, v_org, v_extern_uid);

    -- ti_read ist ein Login-Rolle ohne Mitgliedschaft des Ausfuehrenden; ohne
    -- diese (mit dem ROLLBACK wieder verschwindende) Mitgliedschaft laesst sich
    -- die Persona nicht nachstellen. Scheitert das, werden ihre Proben als
    -- uebersprungen gemeldet statt als Fehler -- ti_read steht ohnehin nicht in
    -- der TO-Liste der Policy und kann von ihr nicht getroffen werden.
    BEGIN
        EXECUTE format('GRANT ti_read TO %I', current_user);
        v_ti_read_ok := true;
    EXCEPTION WHEN OTHERS THEN
        v_ti_read_ok := false;
        RAISE NOTICE 'ti_read kann nicht nachgestellt werden (%): Proben werden uebersprungen.', SQLERRM;
    END;

    -- ────────────────────────────────────────────────────────────────────
    -- Fixture: eine echte ci2027-Aufnahme in einem Nicht-Schulungstrakt
    -- ────────────────────────────────────────────────────────────────────
    SELECT c.id, c.cluster_name INTO v_cluster, v_cluster_no
    FROM inventory_archive.cluster c
    WHERE NOT c.is_training
      AND NOT EXISTS (
          SELECT 1 FROM inventory_archive.plot p
          WHERE p.cluster_id = c.id AND p.interval_name = 'ci2027')
    LIMIT 1;
    IF v_cluster IS NULL THEN
        RAISE EXCEPTION 'Setup: kein Trakt ohne ci2027-Ecke gefunden.';
    END IF;
    SELECT COALESCE(max(plot_name), 0) + 1 INTO v_plot_no
    FROM inventory_archive.plot
    WHERE cluster_name = v_cluster_no AND interval_name = 'ci2027';

    INSERT INTO inventory_archive.plot
        (interval_name, cluster_id, cluster_name, plot_name, federal_state)
    VALUES ('ci2027', v_cluster, v_cluster_no, v_plot_no,
            (SELECT code FROM lookup.lookup_state ORDER BY code LIMIT 1))
    RETURNING id INTO v_real;

    INSERT INTO inventory_archive.plot_coordinates (plot_id, cartesian_x, cartesian_y)
    VALUES (v_real, 0, 0);

    INSERT INTO inventory_archive.tree (plot_id, tree_number, azimuth)
    VALUES (v_real, 1, 0)
    RETURNING id INTO v_tree;

    INSERT INTO inventory_archive.tree_coordinates (tree_id, tree_location)
    VALUES (v_tree, extensions.ST_SetSRID(extensions.ST_MakePoint(10.0, 52.0), 4326));

    -- ci2027 muss gesperrt sein, sonst testet der Rest nichts
    INSERT INTO inventory_archive.interval_release (interval_name, published_at, note)
    VALUES ('ci2027', NULL, '_rg_test')
    ON CONFLICT (interval_name) DO NOTHING;

    -- ────────────────────────────────────────────────────────────────────
    -- Probenmatrix
    -- ────────────────────────────────────────────────────────────────────
    FOR zst IN
        SELECT * FROM (VALUES
            (1, 'Stichtag NULL (gesperrt)',   NULL::timestamptz),
            (2, 'Stichtag in der Zukunft',    now() + interval '30 days'),
            (3, 'Stichtag erreicht',          now() - interval '1 day')
        ) AS s(nr, label, ts)
    LOOP
        UPDATE inventory_archive.interval_release
        SET published_at = zst.ts WHERE interval_name = 'ci2027';

        FOR pers IN
            SELECT * FROM (VALUES
                (1, 'anon',                  'anon',          NULL::uuid, false, false),
                (2, 'authenticated/extern',  'authenticated', v_extern_uid, false, true),
                (3, 'authenticated/Admin',   'authenticated', v_admin_uid,  true,  true),
                (4, 'ti_read',               'ti_read',       NULL::uuid, true,  true),
                (5, 'service_role',          'service_role',  NULL::uuid, true,  true),
                (6, 'postgres (Eigentuemer)','none',          NULL::uuid, true,  true)
            ) AS p(nr, label, pg_role, uid, intern, geometrien)
        LOOP
            FOR obj IN
                SELECT * FROM (VALUES
                    (1, 'plot / Bestand bwi2022',            'bestand',
                        format('SELECT count(*) FROM inventory_archive.plot WHERE id = %L', v_bestand)),
                    (2, 'plot / Schulungstrakt ci2027',      'training',
                        format('SELECT count(*) FROM inventory_archive.plot WHERE id = %L', v_training)),
                    (3, 'plot_coord / Schulungstrakt',       'training_geom',
                        format('SELECT count(*) FROM inventory_archive.plot_coordinates WHERE plot_id = %L', v_training)),
                    (4, 'plot / echte ci2027-Aufnahme',      'gesperrt',
                        format('SELECT count(*) FROM inventory_archive.plot WHERE id = %L', v_real)),
                    (5, 'tree / echte ci2027-Aufnahme',      'gesperrt',
                        format('SELECT count(*) FROM inventory_archive.tree WHERE plot_id = %L', v_real)),
                    (6, 'tree_coord / echte ci2027-Aufnahme','gesperrt_geom',
                        format('SELECT count(*) FROM inventory_archive.tree_coordinates WHERE tree_id = %L', v_tree))
                ) AS o(nr, label, art, sql)
            LOOP
                v_ord := v_ord + 1;

                -- Erwartungswert
                v_expected := CASE obj.art
                    WHEN 'bestand'        THEN 1
                    WHEN 'training'       THEN CASE WHEN v_training IS NULL THEN 0 ELSE 1 END
                    WHEN 'training_geom'  THEN CASE WHEN v_training IS NULL OR NOT pers.geometrien THEN 0 ELSE 1 END
                    WHEN 'gesperrt'       THEN CASE WHEN pers.intern OR zst.nr = 3 THEN 1 ELSE 0 END
                    WHEN 'gesperrt_geom'  THEN CASE WHEN NOT pers.geometrien THEN 0
                                                    WHEN pers.intern OR zst.nr = 3 THEN 1 ELSE 0 END
                END;

                IF pers.pg_role = 'ti_read' AND NOT v_ti_read_ok THEN
                    INSERT INTO public._rg_results
                    VALUES (v_ord, zst.label, pers.label, obj.label, v_expected,
                            'n/a', 'uebersprungen');
                    CONTINUE;
                END IF;

                BEGIN
                    PERFORM set_config('request.jwt.claim.sub', COALESCE(pers.uid::text, ''), true);
                    PERFORM set_config('role', pers.pg_role, true);
                    EXECUTE obj.sql INTO v_count;
                    v_seen := v_count::text;
                EXCEPTION WHEN OTHERS THEN
                    v_seen := 'FEHLER ' || SQLSTATE;
                END;
                PERFORM set_config('role', 'none', true);
                PERFORM set_config('request.jwt.claim.sub', '', true);

                INSERT INTO public._rg_results
                VALUES (v_ord, zst.label, pers.label, obj.label, v_expected, v_seen,
                        CASE WHEN v_seen = v_expected::text THEN 'ok' ELSE 'FEHLER' END);
            END LOOP;
        END LOOP;
    END LOOP;
END $$;

\echo ''
\echo '=== Sichtbarkeitsmatrix ==================================================='
\echo '    (gesehene Zeilen; erwartet in Klammern)'
SELECT persona,
       objekt,
       max(CASE WHEN zustand = 'Stichtag NULL (gesperrt)' THEN gesehen || ' (' || erwartet || ')' END) AS "gesperrt",
       max(CASE WHEN zustand = 'Stichtag in der Zukunft'  THEN gesehen || ' (' || erwartet || ')' END) AS "Termin steht",
       max(CASE WHEN zustand = 'Stichtag erreicht'        THEN gesehen || ' (' || erwartet || ')' END) AS "freigegeben",
       CASE WHEN bool_and(status = 'ok') THEN 'ok'
            WHEN bool_and(status = 'uebersprungen') THEN 'uebersprungen'
            ELSE 'FEHLER' END AS status
FROM public._rg_results
GROUP BY persona, objekt
ORDER BY min(ord);

\echo ''
\echo '=== Abdeckung: Tabellen ohne release_gate ================================='
SELECT c.relname AS ungeschuetzt
FROM pg_class c
WHERE c.relnamespace = 'inventory_archive'::regnamespace
  AND c.relkind = 'r'
  AND c.relname NOT IN ('cluster', 'cluster_move', 'table_template', 'interval_release')
  AND NOT EXISTS (SELECT 1 FROM pg_policy p WHERE p.polrelid = c.oid AND p.polname = 'release_gate')
ORDER BY 1;

\echo ''
\echo '=== Abdeckung: Leserollen ohne Beruecksichtigung ==========================='
\echo '    (Rollen mit SELECT-Recht im Schema, die weder in release_gate stehen'
\echo '     noch RLS umgehen -- jede Zeile hier ist eine Luecke)'
SELECT DISTINCT r.rolname AS rolle
FROM pg_roles r
WHERE has_table_privilege(r.rolname, 'inventory_archive.plot', 'SELECT')
  AND NOT r.rolsuper
  AND NOT r.rolbypassrls
  AND r.rolname NOT IN ('ti_read')          -- intern, absichtlich ungefiltert
  AND r.rolname NOT LIKE 'pg\_%'
  AND NOT EXISTS (
      SELECT 1 FROM pg_policy p
      WHERE p.polrelid = 'inventory_archive.plot'::regclass
        AND p.polname = 'release_gate'
        AND r.oid = ANY (p.polroles))
ORDER BY 1;

\echo ''
\echo '=== Ergebnis =============================================================='
SELECT count(*) FILTER (WHERE status = 'ok')            AS bestanden,
       count(*) FILTER (WHERE status = 'FEHLER')        AS fehlgeschlagen,
       count(*) FILTER (WHERE status = 'uebersprungen') AS uebersprungen
FROM public._rg_results;

SELECT * FROM public._rg_results WHERE status = 'FEHLER' ORDER BY ord;

DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n FROM public._rg_results WHERE status = 'FEHLER';
    IF n > 0 THEN
        RAISE EXCEPTION '% Probe(n) fehlgeschlagen -- siehe Tabelle oben.', n;
    END IF;
    RAISE NOTICE 'Alle Proben bestanden.';
END $$;

ROLLBACK;
