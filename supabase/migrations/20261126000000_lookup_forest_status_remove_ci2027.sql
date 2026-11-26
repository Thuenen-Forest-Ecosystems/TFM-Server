-- Waldentscheid 6, 7, 8, 9, 73, 74, 75 in ci2027 nicht mehr auswählbar (TFM-client-app #517).
--
-- Die App blendet im Auswahldialog jeden Lookup-Code aus, dessen interval kein
-- 'ci2027' enthält (generic-enum-dialog.dart, _isIndexEnabled). Gespeicherte
-- Werte bleiben erhalten und werden weiter angezeigt; das Validierungsschema
-- (enum) bleibt unverändert, es entsteht also kein Validierungsfehler.
--
-- Hebt für 73-75 die Ergänzung aus 20261027000000 auf; 6/7 stammen aus dem
-- Snippet "Untitled query 664" (Feb. 2026), 8/9 hatten ci2027 seit dem Seed.
-- Idempotent: ändert nur Zeilen, die ci2027 noch enthalten.

UPDATE lookup.lookup_forest_status
SET interval = array_remove(interval, 'ci2027')
WHERE code IN (6, 7, 8, 9, 73, 74, 75)
    AND interval @> '{ci2027}';
