-- =============================================================================
-- Integration tests for derived.* PostgreSQL functions
-- Run against local supabase: psql -f test-derived-calculations.sql
-- Reference values from MSSQL BWI2022 (derived.tree_small.csv, etc.)
-- =============================================================================
\
set ON_ERROR_STOP on DO $$
DECLARE _passes int := 0;
_fails int := 0;
_val real;
_tol real;
-- Helper: assert approximate equality
PROCEDURE assert_approx(label text, got real, expected real, tol real) IS BEGIN IF got IS NULL
AND expected IS NOT NULL THEN RAISE WARNING 'FAIL [%]: got NULL, expected %',
label,
expected;
_fails := _fails + 1;
ELSIF abs(got - expected) > tol THEN RAISE WARNING 'FAIL [%]: got %, expected % (tol %)',
label,
got,
expected,
tol;
_fails := _fails + 1;
ELSE _passes := _passes + 1;
END IF;
END;
BEGIN RAISE NOTICE '=== PG function unit tests ===';
-- ── calc_basal_area ────────────────────────────────────────────────────────
RAISE NOTICE '-- calc_basal_area';
CALL assert_approx(
    'basal_area(491)',
    derived.calc_basal_area(491::smallint),
    0.18934457,
    1e -5
);
CALL assert_approx(
    'basal_area(97)',
    derived.calc_basal_area(97::smallint),
    0.007389812,
    1e -6
);
CALL assert_approx(
    'basal_area(213)',
    derived.calc_basal_area(213::smallint),
    0.03563273,
    1e -6
);
CALL assert_approx(
    'basal_area(688)',
    derived.calc_basal_area(688::smallint),
    0.37176353,
    1e -5
);
CALL assert_approx(
    'basal_area(789)',
    derived.calc_basal_area(789::smallint),
    0.48892683,
    1e -5
);
CALL assert_approx(
    'basal_area(25)',
    derived.calc_basal_area(25::smallint),
    0.00049087,
    1e -7
);
-- ── calc_trees_per_hectare ─────────────────────────────────────────────────
RAISE NOTICE '-- calc_trees_per_hectare';
CALL assert_approx(
    'n_ha(491)',
    derived.calc_trees_per_hectare(491::smallint, 4),
    21.125505,
    1e -3
);
CALL assert_approx(
    'n_ha(97)',
    derived.calc_trees_per_hectare(97::smallint, 4),
    541.2858,
    0.1
);
CALL assert_approx(
    'n_ha(688)',
    derived.calc_trees_per_hectare(688::smallint, 4),
    10.759528,
    1e -3
);
-- ── species_to_biomass_group ───────────────────────────────────────────────
RAISE NOTICE '-- species_to_biomass_group';
IF derived.species_to_biomass_group(10) != 'FI' THEN RAISE WARNING 'FAIL [species_group(10)]: got %, expected FI',
derived.species_to_biomass_group(10);
_fails := _fails + 1;
ELSE _passes := _passes + 1;
END IF;
IF derived.species_to_biomass_group(20) != 'KI' THEN RAISE WARNING 'FAIL [species_group(20)]: got %, expected KI',
derived.species_to_biomass_group(20);
_fails := _fails + 1;
ELSE _passes := _passes + 1;
END IF;
IF derived.species_to_biomass_group(100) != 'BU' THEN RAISE WARNING 'FAIL [species_group(100)]: got %, expected BU',
derived.species_to_biomass_group(100);
_fails := _fails + 1;
ELSE _passes := _passes + 1;
END IF;
IF derived.species_to_biomass_group(110) != 'EI' THEN RAISE WARNING 'FAIL [species_group(110)]: got %, expected EI',
derived.species_to_biomass_group(110);
_fails := _fails + 1;
ELSE _passes := _passes + 1;
END IF;
-- ── calc_below_ground_biomass ──────────────────────────────────────────────
RAISE NOTICE '-- calc_below_ground_biomass';
CALL assert_approx(
    'biom_u(FI,491)',
    derived.calc_below_ground_biomass(10, 491::smallint),
    154.20262,
    0.1
);
CALL assert_approx(
    'biom_u(KI,97)',
    derived.calc_below_ground_biomass(20, 97::smallint),
    3.5701513,
    0.01
);
CALL assert_approx(
    'biom_u(BU,213)',
    derived.calc_below_ground_biomass(100, 213::smallint),
    22.17681,
    0.05
);
CALL assert_approx(
    'biom_u(BU,346)',
    derived.calc_below_ground_biomass(100, 346::smallint),
    68.41253,
    0.1
);
CALL assert_approx(
    'biom_u(FI,688)',
    derived.calc_below_ground_biomass(10, 688::smallint),
    503.43616,
    0.5
);
CALL assert_approx(
    'biom_u(FI,789)',
    derived.calc_below_ground_biomass(10, 789::smallint),
    738.0131,
    1.0
);
CALL assert_approx(
    'biom_u(FI,0)',
    derived.calc_below_ground_biomass(10, 0::smallint),
    0.0,
    1e -10
);
-- ── calc_deadwood_biomass ──────────────────────────────────────────────────
RAISE NOTICE '-- calc_deadwood_biomass';
-- NDH (conifer) decomposition classes from k_biom_tot
CALL assert_approx(
    'dw_biom(NDH,1)',
    derived.calc_deadwood_biomass(0.8237099, 10, 1),
    306.42007,
    0.5
);
CALL assert_approx(
    'dw_biom(NDH,2)',
    derived.calc_deadwood_biomass(0.15527584, 10, 2),
    47.825,
    1.0
);
-- LBH (broadleaf excl. oak)
CALL assert_approx(
    'dw_biom(LBH,1)',
    derived.calc_deadwood_biomass(0.056572232, 100, 1),
    32.812,
    0.5
);
-- ── Integration: derived.tree vs reference CSV ─────────────────────────────
RAISE NOTICE '-- Integration: derived.tree spot checks';
-- -tree-8-1-1- (FI, dbh=491)
SELECT basal_area INTO _val
FROM derived.tree
WHERE intkey = '-tree-8-1-1-_bwi2022';
IF FOUND THEN CALL assert_approx('tree-8-1-1 basal_area', _val, 0.18934457, 1e -5);
ELSE RAISE WARNING 'SKIP [tree-8-1-1]: not found in derived.tree';
END IF;
SELECT trees_per_hectare INTO _val
FROM derived.tree
WHERE intkey = '-tree-8-1-1-_bwi2022';
IF FOUND THEN CALL assert_approx('tree-8-1-1 n_ha', _val, 21.125505, 1e -3);
ELSE RAISE WARNING 'SKIP [tree-8-1-1 n_ha]: not found';
END IF;
SELECT below_ground_biomass INTO _val
FROM derived.tree
WHERE intkey = '-tree-8-1-1-_bwi2022';
IF FOUND THEN CALL assert_approx('tree-8-1-1 biom_u', _val, 154.20262, 0.1);
ELSE RAISE WARNING 'SKIP [tree-8-1-1 biom_u]: not found';
END IF;
-- -tree-8-4-8- (FI, dbh=688)
SELECT basal_area INTO _val
FROM derived.tree
WHERE intkey = '-tree-8-4-8-_bwi2022';
IF FOUND THEN CALL assert_approx('tree-8-4-8 basal_area', _val, 0.37176353, 1e -5);
ELSE RAISE WARNING 'SKIP [tree-8-4-8]: not found';
END IF;
-- R-computed fields (only if R has processed)
SELECT above_ground_biomass INTO _val
FROM derived.tree
WHERE intkey = '-tree-8-1-1-_bwi2022';
IF _val IS NOT NULL THEN CALL assert_approx('tree-8-1-1 biom_o', _val, 1030.8289, 20);
ELSE RAISE WARNING 'SKIP [tree-8-1-1 biom_o]: null (R not yet processed)';
END IF;
SELECT volume_fao INTO _val
FROM derived.tree
WHERE intkey = '-tree-8-1-1-_bwi2022';
IF _val IS NOT NULL THEN CALL assert_approx('tree-8-1-1 vol_fao', _val, 1.299812, 0.05);
ELSE RAISE WARNING 'SKIP [tree-8-1-1 vol_fao]: null (rBDAT not yet processed)';
END IF;
SELECT diameter_30perc INTO _val
FROM derived.tree
WHERE intkey = '-tree-8-1-1-_bwi2022';
IF _val IS NOT NULL THEN CALL assert_approx('tree-8-1-1 d30', _val, 376.0, 5.0);
ELSE RAISE WARNING 'SKIP [tree-8-1-1 d30]: null (rBDAT not yet processed)';
END IF;
-- ── Integration: derived.deadwood vs reference CSV ─────────────────────────
RAISE NOTICE '-- Integration: derived.deadwood spot checks';
SELECT volume INTO _val
FROM derived.deadwood
WHERE intkey = '-deadwood-8-4-1-_bwi2022';
IF FOUND
AND _val IS NOT NULL THEN CALL assert_approx('dw-8-4-1 volume', _val, 0.8237099, 0.01);
ELSE RAISE WARNING 'SKIP [dw-8-4-1 volume]: not found or null';
END IF;
SELECT biomass INTO _val
FROM derived.deadwood
WHERE intkey = '-deadwood-8-4-1-_bwi2022';
IF FOUND
AND _val IS NOT NULL THEN CALL assert_approx('dw-8-4-1 biomass', _val, 306.42007, 1.0);
ELSE RAISE WARNING 'SKIP [dw-8-4-1 biomass]: not found or null';
END IF;
SELECT volume INTO _val
FROM derived.deadwood
WHERE intkey = '-deadwood-12-4-1-_bwi2022';
IF FOUND
AND _val IS NOT NULL THEN CALL assert_approx('dw-12-4-1 volume', _val, 0.15527584, 0.005);
ELSE RAISE WARNING 'SKIP [dw-12-4-1 volume]: not found or null';
END IF;
-- ── Integration: derived.regeneration vs reference CSV ─────────────────────
RAISE NOTICE '-- Integration: derived.regeneration spot checks';
SELECT basal_area INTO _val
FROM derived.regeneration
WHERE intkey = '-regeneration-23202-3-130-0-2-1-0-2001-_bwi2022';
IF FOUND
AND _val IS NOT NULL THEN CALL assert_approx(
    'regen-23202 basal_area',
    _val,
    0.000490874,
    1e -7
);
ELSE RAISE WARNING 'SKIP [regen-23202 basal_area]: not found or null';
END IF;
SELECT trees_per_hectare INTO _val
FROM derived.regeneration
WHERE intkey = '-regeneration-23202-3-130-0-2-1-0-2001-_bwi2022';
IF FOUND
AND _val IS NOT NULL THEN CALL assert_approx('regen-23202 n_ha', _val, 795.775, 0.01);
ELSE RAISE WARNING 'SKIP [regen-23202 n_ha]: not found or null';
END IF;
SELECT above_ground_biomass INTO _val
FROM derived.regeneration
WHERE intkey = '-regeneration-23202-3-130-0-2-1-0-2001-_bwi2022';
IF FOUND
AND _val IS NOT NULL THEN -- k2 model result for BU, dbh=25mm
CALL assert_approx('regen-23202 biom_o', _val, 1.47, 0.5);
ELSE RAISE WARNING 'SKIP [regen-23202 biom_o]: not found or null';
END IF;
-- ── Summary ────────────────────────────────────────────────────────────────
RAISE NOTICE '================================================';
RAISE NOTICE 'PASSED: %  |  FAILED: %',
_passes,
_fails;
RAISE NOTICE '================================================';
IF _fails > 0 THEN RAISE EXCEPTION '% test(s) failed!',
_fails;
END IF;
END;
$$;