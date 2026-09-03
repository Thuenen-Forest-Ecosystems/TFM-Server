-- ============================================================================
-- MIGRATION: Zusammengesetzte Indizes fuer die seitenweise Ecken-Abfrage
-- ============================================================================
-- Das Verwaltungstool laedt die Ecken einer Organisation seitenweise aus
-- public.view_records_details:
--
--   WHERE responsible_administration = $1   (bzw. _state / _provider)
--   AND   plot_id > $2                      Cursor der vorigen Seite
--   ORDER BY plot_id ASC
--   LIMIT 10000
--
-- Bis zum 02.09.2026 lief das ueber OFFSET. Damit musste der Server alle Zeilen
-- bis offset+limit erzeugen, sortieren und die uebersprungenen wegwerfen -- bei
-- ~60.000 Ecken kostete die siebte Seite das Siebenfache der ersten und lief in
-- den statement_timeout. PostgREST meldete das als HTTP 500 ("canceling
-- statement due to statement timeout"). TFM-Documentation paginiert deshalb
-- jetzt ueber einen Cursor auf plot_id (components/Utils.js,
-- fetchAllRecordsByCursor).
--
-- Diese Indizes bedienen genau diese Form: fuehrende Spalte fuer die
-- Gleichheit, plot_id fuer Cursor UND Sortierung. Damit wird jede Seite ein
-- begrenzter Index Range Scan, der nach 10.000 Treffern abbricht -- ohne sie
-- muss der Planer entweder ueber idx_records_responsible_* alle Zeilen der
-- Organisation holen und sortieren oder ueber den plot_id-Index laufen und die
-- fremden Organisationen wegfiltern. Beides waechst mit der Gesamtzahl der
-- Ecken, dieser Plan nicht.
--
-- plot_id ist der Cursor, weil die Spalte in public.records UNIQUE NOT NULL ist
-- (20250115140818_public.sql). cluster_id waere dafuer untauglich: pro Trakt
-- gibt es mehrere Ecken, also wuerde jede Seitengrenze Zeilen verschlucken.
--
-- Die einspaltigen Indizes idx_records_responsible_* aus 20250312143840 und
-- 20250115140818 bleiben absichtlich bestehen. Sie sind zwar durch die
-- fuehrende Spalte hier fachlich abgedeckt, aber ihr Wegfall betraefe jede
-- andere Abfrage auf public.records -- eine Aufraeumaktion gehoert in eine
-- eigene Migration mit Blick auf pg_stat_user_indexes, nicht hierher.
--
-- Kein NOTIFY pgrst: Indizes aendern den Schema-Cache von PostgREST nicht.
-- ============================================================================

SET search_path TO public;

CREATE INDEX IF NOT EXISTS idx_records_responsible_administration_plot_id
    ON public.records (responsible_administration, plot_id)
    WHERE responsible_administration IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_records_responsible_state_plot_id
    ON public.records (responsible_state, plot_id)
    WHERE responsible_state IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_records_responsible_provider_plot_id
    ON public.records (responsible_provider, plot_id)
    WHERE responsible_provider IS NOT NULL;

COMMENT ON INDEX public.idx_records_responsible_administration_plot_id IS
    'Cursor-Pagination der Ecken-Liste: responsible_administration = $1 AND plot_id > $2 ORDER BY plot_id LIMIT n.';
COMMENT ON INDEX public.idx_records_responsible_state_plot_id IS
    'Cursor-Pagination der Ecken-Liste: responsible_state = $1 AND plot_id > $2 ORDER BY plot_id LIMIT n.';
COMMENT ON INDEX public.idx_records_responsible_provider_plot_id IS
    'Cursor-Pagination der Ecken-Liste: responsible_provider = $1 AND plot_id > $2 ORDER BY plot_id LIMIT n.';
