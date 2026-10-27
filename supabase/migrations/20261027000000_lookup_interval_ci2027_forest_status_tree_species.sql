-- ci2027 in lookup.*.interval nachtragen, wo es nur auf einer Seite von Hand gesetzt war:
--   lookup_forest_status 73-75: lokal mit ci2027, Production ohne
--   lookup_tree_species 195 (Stechpalme): Production mit ci2027, lokal ohne
-- Das ci2027-Validierungsschema (TFM-validation build/validation.json) erlaubt alle vier Codes.
-- Idempotent: ändert nur Zeilen, denen ci2027 noch fehlt.

UPDATE lookup.lookup_forest_status
SET interval = array_append(interval, 'ci2027')
WHERE code IN (73, 74, 75)
    AND NOT interval @> '{ci2027}';

UPDATE lookup.lookup_tree_species
SET interval = array_append(interval, 'ci2027')
WHERE code = 195
    AND NOT interval @> '{ci2027}';
