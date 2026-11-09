-- ============================================================================
-- #437: 55 Bäume mit doppelt vergebener Baumnummer umnummerieren
-- ============================================================================
-- Grundlage: 437-tree-number-conflicts.sql, Klasse 1_umnummerieren, gelaufen
-- am 2026-11-09 gegen den Prod-Abzug vom 06.11. Die neue Nummer ist das Maximum aus
-- properties und allen früheren Inventuren der Ecke + 1, in Array-Reihenfolge.
--
-- Nicht enthalten:
--   - Testtrakt 9999949/1
--   - 18283/3 Nr. 8: soll gelöscht werden, nicht umnummeriert (separat)
--   - die 3 Lageprobleme 13124/2 Nr. 1, 13124/3 Nr. 5 und 25592/1 Nr. 1
--     (warten auf fachliche Bestätigung)
--
-- Die Liste ist fest eingetragen und wird vor dem Schreiben geprüft. Das Skript
-- bricht ab (nichts geschrieben), wenn
--   - eine Ecke nicht existiert oder cluster/plot nicht zur record-id passen,
--   - an der Array-Position nicht mehr die alte Nummer steht oder der Baum
--     inzwischen eine Archiv-UUID trägt (Trupp hat weiter bearbeitet),
--   - die neue Nummer in der Ecke schon vergeben ist (properties oder Archiv).
--
-- Was geschrieben wird:
--   - nur properties->'tree'[i].tree_number der 55 Bäume
--   - updated_at wird bewusst gesetzt, damit PowerSync den neuen Stand an die
--     Geräte verteilt. updated_by bleibt (auth.uid() ist als postgres NULL).
--   - Abgenommene Ecken (completed_at_administration) schreibt der Trigger
--     sync_inventory_archive automatisch neu nach ci2027.
--   - record_changes bekommt keinen Eintrag (on_record_updated reagiert nicht
--     auf properties), deshalb die Sicherung unten.
--
-- Sicherung: backup_restore.records_437_renumber_20261109 (id, properties,
-- updated_at, updated_by) vor dem Update. Nicht in public, siehe PostgREST.
-- Rückweg:
--   UPDATE public.records r SET properties = b.properties
--   FROM backup_restore.records_437_renumber_20261109 b WHERE r.id = b.id;
--
-- Aufruf (Prod, VPN). Standard ist ein Probelauf mit ROLLBACK:
--   psql "$DB_URL" -X -v ON_ERROR_STOP=1 -f scripts/oneoff/437-renumber-trees.sql
-- Schreiben:
--   psql "$DB_URL" -X -v ON_ERROR_STOP=1 -v commit=1 -f scripts/oneoff/437-renumber-trees.sql
--
-- Vorher: Trupps der betroffenen Ecken sollen ausstehende Änderungen
-- synchronisieren. Ein Gerät mit altem, noch nicht hochgeladenem Stand
-- überschreibt beim nächsten Upload sonst die Umnummerierung (die Vorschau
-- zeigt updated_at je Ecke).
-- ============================================================================

\set ON_ERROR_STOP 1
\if :{?commit}
\else
  \set commit 0
\endif

BEGIN;

CREATE TEMP TABLE renumber (
    record_id     uuid,
    cluster_name  int,
    plot_name     int,
    ord           int,      -- 1-basierte Position in properties->'tree'
    alte_nummer   int,
    neue_nummer   int
) ON COMMIT DROP;

INSERT INTO renumber VALUES
    ('bf970e97-4a6e-476b-9dab-aef5a8f873d2'::uuid, 13124, 2, 2, 2, 18),
    ('bf970e97-4a6e-476b-9dab-aef5a8f873d2'::uuid, 13124, 2, 3, 3, 19),
    ('bf970e97-4a6e-476b-9dab-aef5a8f873d2'::uuid, 13124, 2, 4, 4, 20),
    ('a609dd86-ccec-41a5-b30a-ae40a602cad5'::uuid, 13124, 3, 1, 1, 18),
    ('a609dd86-ccec-41a5-b30a-ae40a602cad5'::uuid, 13124, 3, 2, 2, 19),
    ('a609dd86-ccec-41a5-b30a-ae40a602cad5'::uuid, 13124, 3, 3, 3, 20),
    ('a609dd86-ccec-41a5-b30a-ae40a602cad5'::uuid, 13124, 3, 4, 4, 21),
    ('a609dd86-ccec-41a5-b30a-ae40a602cad5'::uuid, 13124, 3, 6, 6, 22),
    ('a609dd86-ccec-41a5-b30a-ae40a602cad5'::uuid, 13124, 3, 7, 7, 23),
    ('a609dd86-ccec-41a5-b30a-ae40a602cad5'::uuid, 13124, 3, 8, 8, 24),
    ('a609dd86-ccec-41a5-b30a-ae40a602cad5'::uuid, 13124, 3, 9, 9, 25),
    ('157d2ad9-0696-4074-9d8e-a76166b51cfd'::uuid, 16031, 4, 1, 1, 5),
    ('559cb0e3-8bdb-4f00-aac6-f026f92af9e3'::uuid, 16507, 2, 1, 1, 5),
    ('559cb0e3-8bdb-4f00-aac6-f026f92af9e3'::uuid, 16507, 2, 2, 2, 6),
    ('6dd2bca1-5d6c-4851-a6c5-fe6bd9df2074'::uuid, 16873, 2, 2, 12, 16),
    ('6dd2bca1-5d6c-4851-a6c5-fe6bd9df2074'::uuid, 16873, 2, 3, 13, 17),
    ('5ec9a223-dfc3-4f4f-b988-8f00ce534f57'::uuid, 18282, 2, 1, 1, 16),
    ('5ec9a223-dfc3-4f4f-b988-8f00ce534f57'::uuid, 18282, 2, 2, 2, 17),
    ('5ec9a223-dfc3-4f4f-b988-8f00ce534f57'::uuid, 18282, 2, 3, 3, 18),
    ('5ec9a223-dfc3-4f4f-b988-8f00ce534f57'::uuid, 18282, 2, 4, 4, 19),
    ('5ec9a223-dfc3-4f4f-b988-8f00ce534f57'::uuid, 18282, 2, 5, 5, 20),
    ('db4db5b3-ba99-45f8-947d-fcd4831e20c2'::uuid, 18283, 3, 4, 7, 9),
    ('b7ccfc8d-d255-4e6e-8cbe-2d853a260206'::uuid, 18360, 3, 1, 1, 13),
    ('b7ccfc8d-d255-4e6e-8cbe-2d853a260206'::uuid, 18360, 3, 2, 2, 14),
    ('b7ccfc8d-d255-4e6e-8cbe-2d853a260206'::uuid, 18360, 3, 3, 3, 15),
    ('8d3a076d-ff57-4ea6-9f51-dfd56ba6cf00'::uuid, 18506, 2, 4, 10, 11),
    ('653c2f18-0b7a-47df-bfd8-7b8e9c4665e5'::uuid, 18506, 4, 1, 1, 15),
    ('653c2f18-0b7a-47df-bfd8-7b8e9c4665e5'::uuid, 18506, 4, 2, 2, 16),
    ('653c2f18-0b7a-47df-bfd8-7b8e9c4665e5'::uuid, 18506, 4, 3, 3, 17),
    ('232a79e7-db0e-4b4c-af45-87f5d352acf3'::uuid, 18974, 1, 4, 3, 4),
    ('103dd708-ec9b-40be-a752-f219f0360374'::uuid, 19250, 2, 11, 9, 11),
    ('d9c44fc3-50c6-4c83-bd6b-b7a1c21c4c70'::uuid, 20603, 3, 1, 1, 4),
    ('d9c44fc3-50c6-4c83-bd6b-b7a1c21c4c70'::uuid, 20603, 3, 2, 2, 5),
    ('a0bd9b92-1822-4597-8689-d506be9756c3'::uuid, 20924, 3, 8, 19, 20),
    ('b691fc68-d175-494b-96ab-1acc343f7ddd'::uuid, 21884, 1, 2, 3, 5),
    ('ecbb505a-9740-4d8e-87b9-e0ba82828707'::uuid, 22502, 1, 7, 9, 10),
    ('93273d11-16c5-4d8e-adf1-1093f58aa954'::uuid, 22728, 2, 8, 10, 12),
    ('84fab52b-49aa-4684-96f2-177ac079463b'::uuid, 32915, 4, 1, 1, 17),
    ('84fab52b-49aa-4684-96f2-177ac079463b'::uuid, 32915, 4, 2, 2, 18),
    ('84fab52b-49aa-4684-96f2-177ac079463b'::uuid, 32915, 4, 3, 3, 19),
    ('84fab52b-49aa-4684-96f2-177ac079463b'::uuid, 32915, 4, 4, 4, 20),
    ('84fab52b-49aa-4684-96f2-177ac079463b'::uuid, 32915, 4, 5, 5, 21),
    ('84fab52b-49aa-4684-96f2-177ac079463b'::uuid, 32915, 4, 6, 6, 22),
    ('84fab52b-49aa-4684-96f2-177ac079463b'::uuid, 32915, 4, 7, 7, 23),
    ('84fab52b-49aa-4684-96f2-177ac079463b'::uuid, 32915, 4, 8, 8, 24),
    ('84fab52b-49aa-4684-96f2-177ac079463b'::uuid, 32915, 4, 9, 9, 25),
    ('84fab52b-49aa-4684-96f2-177ac079463b'::uuid, 32915, 4, 10, 10, 26),
    ('84fab52b-49aa-4684-96f2-177ac079463b'::uuid, 32915, 4, 11, 11, 27),
    ('a2801e6e-18c4-4042-9db0-62aa7af1f857'::uuid, 37085, 2, 5, 3, 5),
    ('a2801e6e-18c4-4042-9db0-62aa7af1f857'::uuid, 37085, 2, 6, 4, 6),
    ('8c21c889-3bef-4d8a-af65-f882baa1f76d'::uuid, 37568, 3, 14, 28, 33),
    ('a4bd6f9e-0145-4871-84f5-8045f1304b7c'::uuid, 38119, 2, 8, 27, 30),
    ('d509f6c7-cbf4-4a20-b392-7cb210911855'::uuid, 38119, 3, 12, 32, 33),
    ('b8cd3d05-5f5f-496a-93e3-d38a82372532'::uuid, 48898, 2, 8, 9, 10),
    ('0c6ed908-b881-4e92-8dee-7ac6d357c6b1'::uuid, 52457, 4, 1, 1, 8)
;

-- ---------------------------------------------------------------------------
-- Prüfungen
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    n_liste int;
    n_ecken int;
    fehler  text;
BEGIN
    SELECT count(*), count(DISTINCT record_id) INTO n_liste, n_ecken FROM renumber;
    IF n_liste <> 55 THEN
        RAISE EXCEPTION 'Liste hat % statt 55 Einträge', n_liste;
    END IF;

    -- Ecke existiert und passt
    SELECT string_agg(format('%s/%s', x.cluster_name, x.plot_name), ', ') INTO fehler
    FROM (SELECT DISTINCT record_id, cluster_name, plot_name FROM renumber) x
    LEFT JOIN public.records r
           ON r.id = x.record_id
          AND r.cluster_name = x.cluster_name AND r.plot_name = x.plot_name
    WHERE r.id IS NULL;
    IF fehler IS NOT NULL THEN
        RAISE EXCEPTION 'record-id passt nicht zu Ecke: %', fehler;
    END IF;

    -- Baum steht unverändert an der Position, ohne Archiv-UUID
    SELECT string_agg(format('%s/%s Pos %s: erwartet Nr %s, gefunden %s (id %s)',
                             x.cluster_name, x.plot_name, x.ord, x.alte_nummer,
                             coalesce(t.e->>'tree_number', 'kein Baum'),
                             coalesce(t.e->>'id', '-')), E'\n') INTO fehler
    FROM renumber x
    JOIN public.records r ON r.id = x.record_id
    LEFT JOIN LATERAL (
        SELECT e FROM jsonb_array_elements(
                   CASE WHEN jsonb_typeof(r.properties->'tree') = 'array'
                        THEN r.properties->'tree' END)
                   WITH ORDINALITY AS a(e, ord)
        WHERE a.ord = x.ord
    ) t ON true
    WHERE t.e IS NULL
       OR (t.e->>'tree_number')::int IS DISTINCT FROM x.alte_nummer
       OR coalesce(t.e->>'id', '') ~* '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$';
    IF fehler IS NOT NULL THEN
        RAISE EXCEPTION E'Ecke inzwischen verändert:\n%', fehler;
    END IF;

    -- neue Nummer innerhalb der Liste eindeutig
    SELECT string_agg(format('%s/%s Nr %s', cluster_name, plot_name, neue_nummer), ', ')
      INTO fehler
    FROM (SELECT cluster_name, plot_name, neue_nummer FROM renumber
          GROUP BY 1, 2, 3 HAVING count(*) > 1) d;
    IF fehler IS NOT NULL THEN
        RAISE EXCEPTION 'neue Nummer doppelt in der Liste: %', fehler;
    END IF;

    -- neue Nummer in der Ecke frei: aktuelle Bäume ...
    SELECT string_agg(format('%s/%s Nr %s', x.cluster_name, x.plot_name, x.neue_nummer), ', ')
      INTO fehler
    FROM renumber x
    JOIN public.records r ON r.id = x.record_id
    CROSS JOIN LATERAL jsonb_array_elements(r.properties->'tree') e
    WHERE (e->>'tree_number')::int = x.neue_nummer;
    IF fehler IS NOT NULL THEN
        RAISE EXCEPTION 'neue Nummer schon in properties vergeben: %', fehler;
    END IF;

    -- ... und alle früheren Inventuren
    SELECT string_agg(format('%s/%s Nr %s (%s)', x.cluster_name, x.plot_name,
                             x.neue_nummer, pl.interval_name), ', ')
      INTO fehler
    FROM renumber x
    JOIN inventory_archive.plot pl
      ON pl.cluster_name = x.cluster_name AND pl.plot_name = x.plot_name
    JOIN inventory_archive.tree t ON t.plot_id = pl.id
    WHERE pl.interval_name <> 'ci2027'
      AND t.tree_number = x.neue_nummer;
    IF fehler IS NOT NULL THEN
        RAISE EXCEPTION 'neue Nummer im Archiv vergeben: %', fehler;
    END IF;

    RAISE NOTICE 'Prüfungen bestanden: % Bäume in % Ecken', n_liste, n_ecken;
END $$;

-- ---------------------------------------------------------------------------
-- Vorschau
-- ---------------------------------------------------------------------------
SELECT r.cluster_name || '/' || r.plot_name AS ecke,
       string_agg(x.alte_nummer || '→' || x.neue_nummer, ', ' ORDER BY x.ord) AS umnummerierung,
       r.updated_at::timestamp(0)              AS zuletzt_geaendert,
       r.completed_at_troop IS NOT NULL        AS trupp_fertig,
       r.completed_at_administration IS NOT NULL AS abgenommen
FROM renumber x
JOIN public.records r ON r.id = x.record_id
GROUP BY r.id, r.cluster_name, r.plot_name, r.updated_at,
         r.completed_at_troop, r.completed_at_administration
ORDER BY r.cluster_name, r.plot_name;

-- ---------------------------------------------------------------------------
-- Sicherung
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE records_437_renumber_20261109 ON COMMIT DROP AS
SELECT r.id, r.cluster_name, r.plot_name, r.properties, r.updated_at, r.updated_by
FROM public.records r
WHERE r.id IN (SELECT record_id FROM renumber);

\if :commit
CREATE SCHEMA IF NOT EXISTS backup_restore;
REVOKE ALL ON SCHEMA backup_restore FROM anon, authenticated;
-- bricht ab, falls die Tabelle schon existiert (Skript lief bereits)
CREATE TABLE backup_restore.records_437_renumber_20261109 AS
SELECT * FROM pg_temp.records_437_renumber_20261109;
\endif

-- ---------------------------------------------------------------------------
-- Update
-- ---------------------------------------------------------------------------
UPDATE public.records r
SET properties = jsonb_set(r.properties, '{tree}', neu.tree)
FROM (
    SELECT r2.id,
           jsonb_agg(CASE WHEN x.neue_nummer IS NOT NULL
                          THEN jsonb_set(a.e, '{tree_number}', to_jsonb(x.neue_nummer))
                          ELSE a.e END
                     ORDER BY a.ord) AS tree
    FROM public.records r2
    CROSS JOIN LATERAL jsonb_array_elements(r2.properties->'tree') WITH ORDINALITY AS a(e, ord)
    LEFT JOIN renumber x ON x.record_id = r2.id AND x.ord = a.ord
    WHERE r2.id IN (SELECT record_id FROM renumber)
    GROUP BY r2.id
) neu
WHERE r.id = neu.id;

-- ---------------------------------------------------------------------------
-- Kontrolle
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    n_geaendert int;
    n_andere    int;
    n_doppelt   int;
BEGIN
    -- genau die 55 Nummern stehen jetzt da
    SELECT count(*) INTO n_geaendert
    FROM renumber x
    JOIN public.records r ON r.id = x.record_id
    CROSS JOIN LATERAL jsonb_array_elements(r.properties->'tree') WITH ORDINALITY AS a(e, ord)
    WHERE a.ord = x.ord AND (a.e->>'tree_number')::int = x.neue_nummer;
    IF n_geaendert <> 55 THEN
        RAISE EXCEPTION 'Kontrolle: nur % von 55 Bäumen umnummeriert', n_geaendert;
    END IF;

    -- sonst hat sich nichts geändert: properties ohne tree_number gleich der Sicherung
    SELECT count(*) INTO n_andere
    FROM public.records r
    JOIN pg_temp.records_437_renumber_20261109 b ON b.id = r.id
    WHERE (SELECT jsonb_agg(e - 'tree_number' ORDER BY o)
           FROM jsonb_array_elements(r.properties->'tree') WITH ORDINALITY AS t(e, o))
          IS DISTINCT FROM
          (SELECT jsonb_agg(e - 'tree_number' ORDER BY o)
           FROM jsonb_array_elements(b.properties->'tree') WITH ORDINALITY AS t(e, o))
       OR (r.properties - 'tree') IS DISTINCT FROM (b.properties - 'tree');
    IF n_andere > 0 THEN
        RAISE EXCEPTION 'Kontrolle: % Ecken mit Änderungen außerhalb tree_number', n_andere;
    END IF;

    -- keine doppelten Nummern mehr in den betroffenen Ecken
    SELECT count(*) INTO n_doppelt
    FROM (SELECT r.id, (e->>'tree_number')::int
          FROM public.records r
          CROSS JOIN LATERAL jsonb_array_elements(r.properties->'tree') e
          WHERE r.id IN (SELECT record_id FROM renumber)
          GROUP BY 1, 2 HAVING count(*) > 1) d;
    IF n_doppelt > 0 THEN
        RAISE EXCEPTION 'Kontrolle: % doppelte Nummern innerhalb properties', n_doppelt;
    END IF;

    RAISE NOTICE 'Kontrolle bestanden: 55 Bäume umnummeriert, sonst keine Änderung';
END $$;

\if :commit
COMMIT;
\echo 'COMMIT: Umnummerierung geschrieben, Sicherung in backup_restore.records_437_renumber_20261109'
\else
ROLLBACK;
\echo 'Probelauf: ROLLBACK, nichts geschrieben. Schreiben mit -v commit=1'
\endif
