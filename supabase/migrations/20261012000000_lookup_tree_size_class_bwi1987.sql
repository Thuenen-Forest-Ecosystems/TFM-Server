-- BWI1987 (b1_jung.Gr) uses diameter classes 7, 8 and 9 (= 9,0 bis 9,9 cm BHD)
-- that x_gr does not contain. Code 9 is taken by bwi2002 (Nebenbestand), so the
-- 1987 class 9 is stored as 10. Mirrors additional_rows in
-- nfi2022/migration-script/lookup_tables.json.

INSERT INTO lookup.lookup_tree_size_class (code, name_de, name_en, sort, interval)
VALUES
    (7, '7,0 bis 7,9 cm BHD', '7.0 to 7.9 cm DBH', 2003, '{bwi1987}'),
    (8, '8,0 bis 8,9 cm BHD', '8.0 to 8.9 cm DBH', 2004, '{bwi1987}'),
    (10, '9,0 bis 9,9 cm BHD', '9.0 to 9.9 cm DBH', 2005, '{bwi1987}')
ON CONFLICT (code) DO UPDATE
SET name_de = EXCLUDED.name_de,
    name_en = EXCLUDED.name_en,
    sort = EXCLUDED.sort,
    interval = EXCLUDED.interval;
