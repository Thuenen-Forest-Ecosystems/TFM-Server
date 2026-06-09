-- ============================================================================
-- TEST: derived calculation values against MSSQL reference (BWI2022)
-- ============================================================================
-- Run:
--   psql -h <host> -p <port> -U postgres -d postgres -f test_derived_calculations.sql
--
-- Tests PG-computed values (basal_area, trees_per_hectare, below_ground_biomass)
-- and R-computed values (volume_fao, above_ground_biomass, diameter_30perc, etc.)
-- against reference data from the old MSSQL system.
--
-- Tolerances:
--   PG math:  0.1% relative (deterministic formulas)
--   R/rBDAT:  2%   relative (minor model version differences allowed)
-- ============================================================================
BEGIN;
-- ── Config ──────────────────────────────────────────────────────────────────
\
set pg_tol 0.001 \
set r_tol 0.02 -- ── Reference data: trees (from derived.tree_small.csv) ────────────────────
    CREATE TEMP TABLE _expected_tree (
        intkey text PRIMARY KEY,
        exp_dbh numeric,
        exp_n_ha numeric,
        exp_tree_height numeric,
        exp_d30 numeric,
        exp_d7 numeric,
        exp_basal_area numeric,
        exp_volume_fao numeric,
        exp_volume_harvest numeric,
        exp_biom_o numeric,
        exp_biom_u numeric,
        exp_growing_space numeric
    );
INSERT INTO _expected_tree
VALUES (
        '-tree-8-1-1-_bwi2022',
        491,
        21.125505,
        146,
        376,
        344,
        0.18934457,
        1.299812,
        1.164147,
        1030.8289,
        154.20262,
        473.36145
    ),
    (
        '-tree-8-3-1-_bwi2022',
        97,
        541.2858,
        71,
        85,
        2,
        0.007389812,
        0.028041406,
        0.017969243,
        30.937487,
        3.5701513,
        18.474527
    ),
    (
        '-tree-8-4-1-_bwi2022',
        213,
        112.25635,
        182,
        165,
        154,
        0.03563273,
        0.28148735,
        0.22887214,
        222.88873,
        22.17681,
        8.356348
    ),
    (
        '-tree-8-4-3-_bwi2022',
        346,
        42.542,
        242,
        270,
        272,
        0.09402472,
        1.0206225,
        0.86116934,
        766.5722,
        68.41253,
        20.534828
    ),
    (
        '-tree-8-4-8-_bwi2022',
        688,
        10.759528,
        307,
        502,
        525,
        0.37176353,
        4.179688,
        3.587809,
        2197.3623,
        503.43616,
        52.380135
    ),
    (
        '-tree-11-2-1-_bwi2022',
        342,
        43.542953,
        177,
        265,
        254,
        0.09186331,
        0.70509887,
        0.6294882,
        382.46466,
        71.49196,
        29.202265
    ),
    (
        '-tree-11-2-7-_bwi2022',
        573,
        15.511752,
        261,
        450,
        457,
        0.257869,
        3.2059276,
        2.7748291,
        2341.08,
        220.7168,
        110.67324
    ),
    (
        '-tree-11-4-1-_bwi2022',
        789,
        12.767105,
        297,
        563,
        586,
        0.48892683,
        5.0615754,
        4.397519,
        2690.2305,
        738.0131,
        783.26294
    ),
    (
        '-tree-12-4-1-_bwi2022',
        489,
        21.298666,
        216,
        364,
        358,
        0.18780519,
        1.5731432,
        1.3333422,
        892.68665,
        194.03445,
        38.215073
    ),
    (
        '-tree-12-4-8-_bwi2022',
        741,
        9.275422,
        241,
        525,
        529,
        0.4312472,
        3.6100092,
        3.1633506,
        2094.5686,
        619.36237,
        84.17461
    ),
    (
        '-tree-15-1-1-_bwi2022',
        548,
        16.959341,
        344,
        417,
        440,
        0.23585819,
        3.246097,
        2.7415786,
        1567.4277,
        266.7023,
        63.901314
    ),
    (
        '-tree-15-1-4-_bwi2022',
        676,
        11.144914,
        393,
        507,
        540,
        0.35890812,
        5.439174,
        4.676462,
        2565.2751,
        479.29733,
        95.29405
    ),
    (
        '-tree-18-1-1-_bwi2022',
        853,
        6.999581,
        371,
        617,
        654,
        0.57146275,
        7.5144196,
        6.5346665,
        3583.143,
        917.594,
        85.1808
    ),
    (
        '-tree-18-1-5-_bwi2022',
        694,
        10.574288,
        352,
        513,
        543,
        0.37827605,
        4.986578,
        4.255541,
        2475.892,
        515.7923,
        57.10298
    ),
    (
        '-tree-18-1-10-_bwi2022',
        894,
        6.3722835,
        374,
        643,
        682,
        0.62771845,
        8.206664,
        7.5157647,
        3850.3667,
        1046.1277,
        93.35703
    ),
    (
        '-tree-18-2-2-_bwi2022',
        748,
        9.102631,
        292,
        537,
        558,
        0.43943346,
        4.539425,
        3.9370708,
        2443.3936,
        635.83966,
        75.89798
    ),
    (
        '-tree-20-1-1-_bwi2022',
        533,
        17.927334,
        370,
        409,
        435,
        0.22312297,
        3.3684123,
        2.8603134,
        1565.3827,
        246.81311,
        26.856817
    ),
    (
        '-tree-20-1-10-_bwi2022',
        723,
        9.743018,
        405,
        539,
        575,
        0.4105504,
        6.322175,
        5.4570384,
        2954.9856,
        578.25793,
        48.030113
    ),
    (
        '-tree-20-2-8-_bwi2022',
        794,
        8.07847,
        369,
        644,
        667,
        0.49514332,
        9.433452,
        8.366332,
        6433.5938,
        470.74222,
        70.088036
    ),
    (
        '-tree-20-2-16-_bwi2022',
        1090,
        4.286641,
        370,
        882,
        898,
        0.93313164,
        18.994207,
        17.710966,
        11824.248,
        982.43506,
        131.53554
    ),
    (
        '-tree-23-2-1-_bwi2022',
        212,
        113.31786,
        202,
        175,
        170,
        0.035298936,
        0.33861455,
        0.27606604,
        161.44588,
        18.805698,
        5.099764
    ),
    (
        '-tree-23-3-8-_bwi2022',
        72,
        982.4379,
        79,
        65,
        19,
        0.004071504,
        0.018006962,
        0.0038697931,
        12.014883,
        0.9217516,
        1.4518265
    ),
    (
        '-tree-23-4-17-_bwi2022',
        260,
        75.339615,
        160,
        200,
        181,
        0.05309291,
        0.37414122,
        0.28202003,
        158.72565,
        52.20535,
        9.676134
    ),
    (
        '-tree-19-2-1-_bwi2022',
        458,
        32.090733,
        293,
        352,
        365,
        0.16474827,
        1.9809357,
        1.6708341,
        981.204,
        161.60382,
        35.29094
    );
-- ── Reference data: deadwood (from derived.deadwood_small.csv) ─────────────
CREATE TEMP TABLE _expected_deadwood (
    intkey text PRIMARY KEY,
    exp_volume numeric,
    exp_vol_top numeric,
    exp_biomass numeric
);
INSERT INTO _expected_deadwood
VALUES (
        '-deadwood-8-4-1-_bwi2022',
        0.8237099,
        0.8237099,
        306.42007
    ),
    (
        '-deadwood-12-4-1-_bwi2022',
        0.15527584,
        0.15527584,
        32.607925
    ),
    (
        '-deadwood-14-2-1-_bwi2022',
        0.39213362,
        0.39213362,
        48.232437
    ),
    (
        '-deadwood-14-3-5-_bwi2022',
        0.64126194,
        0.64126194,
        90.41793
    ),
    (
        '-deadwood-15-1-1-_bwi2022',
        0.026405087,
        0.026405087,
        15.31495
    ),
    (
        '-deadwood-18-1-6-_bwi2022',
        0.4959763,
        0.4959763,
        61.005085
    ),
    (
        '-deadwood-18-2-1-_bwi2022',
        1.3477616,
        1.3477616,
        415.1106
    ),
    (
        '-deadwood-20-3-1-_bwi2022',
        0.673737,
        0.70742387,
        410.30585
    ),
    (
        '-deadwood-20-4-1-_bwi2022',
        0.11309735,
        0.11309735,
        13.910974
    ),
    (
        '-deadwood-23-1-1-_bwi2022',
        0.24686179,
        0.24904418,
        76.705605
    ),
    (
        '-deadwood-23-4-1-_bwi2022',
        0.09165723,
        0.09165723,
        33.913174
    ),
    (
        '-deadwood-24-2-1-_bwi2022',
        0.017105974,
        0.017105974,
        6.3292103
    );
-- ── Helpers ─────────────────────────────────────────────────────────────────
DO $$
DECLARE tol_pg float := 0.001;
-- 0.1% tolerance for PG-computed
tol_r float := 0.02;
-- 2% tolerance for R-computed
rec record;
act record;
passed int := 0;
failed int := 0;
skipped int := 0;
msg text;
-- helper: relative error check
-- returns true if |actual - expected| / expected <= tol
-- or if both are null/zero
function_unused boolean;
BEGIN RAISE NOTICE '════════════════════════════════════════════════════════════';
RAISE NOTICE 'TEST: derived tree calculations (PG-computed)';
RAISE NOTICE '════════════════════════════════════════════════════════════';
-- ── TREE: PG-computed fields ────────────────────────────────────────
FOR rec IN
SELECT *
FROM _expected_tree
ORDER BY intkey LOOP
SELECT * INTO act
FROM derived.tree
WHERE intkey = rec.intkey;
IF NOT FOUND THEN RAISE NOTICE 'SKIP  % — not in derived.tree',
rec.intkey;
skipped := skipped + 1;
CONTINUE;
END IF;
-- dbh
IF act.dbh IS NOT NULL
AND rec.exp_dbh IS NOT NULL
AND act.dbh = rec.exp_dbh::int THEN passed := passed + 1;
ELSIF act.dbh IS NULL
AND rec.exp_dbh IS NULL THEN passed := passed + 1;
ELSE RAISE NOTICE 'FAIL  % dbh: got=% expected=%',
rec.intkey,
act.dbh,
rec.exp_dbh;
failed := failed + 1;
END IF;
-- basal_area (PG)
IF act.basal_area IS NOT NULL
AND rec.exp_basal_area IS NOT NULL
AND abs(act.basal_area - rec.exp_basal_area) / GREATEST(abs(rec.exp_basal_area), 1e -12) <= tol_pg THEN passed := passed + 1;
ELSIF act.basal_area IS NULL
AND rec.exp_basal_area IS NULL THEN passed := passed + 1;
ELSE RAISE NOTICE 'FAIL  % basal_area: got=% expected=%',
rec.intkey,
act.basal_area,
rec.exp_basal_area;
failed := failed + 1;
END IF;
-- trees_per_hectare (PG)
IF act.trees_per_hectare IS NOT NULL
AND rec.exp_n_ha IS NOT NULL
AND abs(act.trees_per_hectare - rec.exp_n_ha) / GREATEST(abs(rec.exp_n_ha), 1e -12) <= tol_pg THEN passed := passed + 1;
ELSIF act.trees_per_hectare IS NULL
AND rec.exp_n_ha IS NULL THEN passed := passed + 1;
ELSE RAISE NOTICE 'FAIL  % trees_per_hectare: got=% expected=%',
rec.intkey,
act.trees_per_hectare,
rec.exp_n_ha;
failed := failed + 1;
END IF;
-- below_ground_biomass (PG)
IF act.below_ground_biomass IS NOT NULL
AND rec.exp_biom_u IS NOT NULL
AND abs(act.below_ground_biomass - rec.exp_biom_u) / GREATEST(abs(rec.exp_biom_u), 1e -12) <= tol_pg THEN passed := passed + 1;
ELSIF act.below_ground_biomass IS NULL
AND rec.exp_biom_u IS NULL THEN passed := passed + 1;
ELSE RAISE NOTICE 'FAIL  % below_ground_biomass: got=% expected=%',
rec.intkey,
act.below_ground_biomass,
rec.exp_biom_u;
failed := failed + 1;
END IF;
END LOOP;
RAISE NOTICE '──────────────────────────────────────────────────────────';
RAISE NOTICE 'PG tree: % passed, % failed, % skipped',
passed,
failed,
skipped;
RAISE NOTICE '';
-- ── TREE: R-computed fields (volume, biomass, diameters, growing space)
passed := 0;
failed := 0;
skipped := 0;
RAISE NOTICE '════════════════════════════════════════════════════════════';
RAISE NOTICE 'TEST: derived tree calculations (R-computed)';
RAISE NOTICE '════════════════════════════════════════════════════════════';
FOR rec IN
SELECT *
FROM _expected_tree
ORDER BY intkey LOOP
SELECT * INTO act
FROM derived.tree
WHERE intkey = rec.intkey;
IF NOT FOUND THEN skipped := skipped + 1;
CONTINUE;
END IF;
-- Skip if R hasn't processed this row yet
IF act.needs_r_calculation THEN RAISE NOTICE 'SKIP  % — needs_r_calculation=true (R not run yet)',
rec.intkey;
skipped := skipped + 1;
CONTINUE;
END IF;
-- volume_fao
IF act.volume_fao IS NOT NULL
AND rec.exp_volume_fao IS NOT NULL
AND abs(act.volume_fao - rec.exp_volume_fao) / GREATEST(abs(rec.exp_volume_fao), 1e -12) <= tol_r THEN passed := passed + 1;
ELSIF act.volume_fao IS NULL
AND rec.exp_volume_fao IS NULL THEN passed := passed + 1;
ELSE RAISE NOTICE 'FAIL  % volume_fao: got=% expected=%',
rec.intkey,
act.volume_fao,
rec.exp_volume_fao;
failed := failed + 1;
END IF;
-- volume_harvest
IF act.volume_harvest IS NOT NULL
AND rec.exp_volume_harvest IS NOT NULL
AND abs(act.volume_harvest - rec.exp_volume_harvest) / GREATEST(abs(rec.exp_volume_harvest), 1e -12) <= tol_r THEN passed := passed + 1;
ELSIF act.volume_harvest IS NULL
AND rec.exp_volume_harvest IS NULL THEN passed := passed + 1;
ELSE RAISE NOTICE 'FAIL  % volume_harvest: got=% expected=%',
rec.intkey,
act.volume_harvest,
rec.exp_volume_harvest;
failed := failed + 1;
END IF;
-- above_ground_biomass
IF act.above_ground_biomass IS NOT NULL
AND rec.exp_biom_o IS NOT NULL
AND abs(act.above_ground_biomass - rec.exp_biom_o) / GREATEST(abs(rec.exp_biom_o), 1e -12) <= tol_r THEN passed := passed + 1;
ELSIF act.above_ground_biomass IS NULL
AND rec.exp_biom_o IS NULL THEN passed := passed + 1;
ELSE RAISE NOTICE 'FAIL  % above_ground_biomass: got=% expected=%',
rec.intkey,
act.above_ground_biomass,
rec.exp_biom_o;
failed := failed + 1;
END IF;
-- diameter_30perc
IF act.diameter_30perc IS NOT NULL
AND rec.exp_d30 IS NOT NULL
AND abs(act.diameter_30perc - rec.exp_d30) / GREATEST(abs(rec.exp_d30), 1e -12) <= tol_r THEN passed := passed + 1;
ELSIF act.diameter_30perc IS NULL
AND rec.exp_d30 IS NULL THEN passed := passed + 1;
ELSE RAISE NOTICE 'FAIL  % diameter_30perc: got=% expected=%',
rec.intkey,
act.diameter_30perc,
rec.exp_d30;
failed := failed + 1;
END IF;
-- diameter_7m
IF act.diameter_7m IS NOT NULL
AND rec.exp_d7 IS NOT NULL
AND abs(act.diameter_7m - rec.exp_d7) / GREATEST(abs(rec.exp_d7), 1e -12) <= tol_r THEN passed := passed + 1;
ELSIF act.diameter_7m IS NULL
AND rec.exp_d7 IS NULL THEN passed := passed + 1;
ELSE RAISE NOTICE 'FAIL  % diameter_7m: got=% expected=%',
rec.intkey,
act.diameter_7m,
rec.exp_d7;
failed := failed + 1;
END IF;
-- growing_space
IF act.growing_space IS NOT NULL
AND rec.exp_growing_space IS NOT NULL
AND abs(act.growing_space - rec.exp_growing_space) / GREATEST(abs(rec.exp_growing_space), 1e -12) <= tol_r THEN passed := passed + 1;
ELSIF act.growing_space IS NULL
AND rec.exp_growing_space IS NULL THEN passed := passed + 1;
ELSE RAISE NOTICE 'FAIL  % growing_space: got=% expected=%',
rec.intkey,
act.growing_space,
rec.exp_growing_space;
failed := failed + 1;
END IF;
END LOOP;
RAISE NOTICE '──────────────────────────────────────────────────────────';
RAISE NOTICE 'R tree: % passed, % failed, % skipped',
passed,
failed,
skipped;
RAISE NOTICE '';
-- ── DEADWOOD ────────────────────────────────────────────────────────
passed := 0;
failed := 0;
skipped := 0;
RAISE NOTICE '════════════════════════════════════════════════════════════';
RAISE NOTICE 'TEST: derived deadwood calculations';
RAISE NOTICE '════════════════════════════════════════════════════════════';
FOR rec IN
SELECT *
FROM _expected_deadwood
ORDER BY intkey LOOP
SELECT * INTO act
FROM derived.deadwood
WHERE intkey = rec.intkey;
IF NOT FOUND THEN RAISE NOTICE 'SKIP  % — not in derived.deadwood',
rec.intkey;
skipped := skipped + 1;
CONTINUE;
END IF;
-- volume (PG-computed via truncated cone)
IF act.volume IS NOT NULL
AND rec.exp_volume IS NOT NULL
AND abs(act.volume - rec.exp_volume) / GREATEST(abs(rec.exp_volume), 1e -12) <= tol_pg THEN passed := passed + 1;
ELSIF act.volume IS NULL
AND rec.exp_volume IS NULL THEN passed := passed + 1;
ELSE RAISE NOTICE 'FAIL  % volume: got=% expected=%',
rec.intkey,
act.volume,
rec.exp_volume;
failed := failed + 1;
END IF;
-- biomass (PG-computed via k_biom_tot)
IF act.biomass IS NOT NULL
AND rec.exp_biomass IS NOT NULL
AND abs(act.biomass - rec.exp_biomass) / GREATEST(abs(rec.exp_biomass), 1e -12) <= tol_pg THEN passed := passed + 1;
ELSIF act.biomass IS NULL
AND rec.exp_biomass IS NULL THEN passed := passed + 1;
ELSE RAISE NOTICE 'FAIL  % biomass: got=% expected=%',
rec.intkey,
act.biomass,
rec.exp_biomass;
failed := failed + 1;
END IF;
-- volume_with_top (PG for simple types, R for standing)
-- Use wider tolerance since standing types need rBDAT
IF act.volume_with_top IS NOT NULL
AND rec.exp_vol_top IS NOT NULL
AND abs(act.volume_with_top - rec.exp_vol_top) / GREATEST(abs(rec.exp_vol_top), 1e -12) <= tol_r THEN passed := passed + 1;
ELSIF act.volume_with_top IS NULL
AND rec.exp_vol_top IS NOT NULL THEN RAISE NOTICE 'SKIP  % volume_with_top: null (R not run yet), expected=%',
rec.intkey,
rec.exp_vol_top;
skipped := skipped + 1;
ELSIF act.volume_with_top IS NULL
AND rec.exp_vol_top IS NULL THEN passed := passed + 1;
ELSE RAISE NOTICE 'FAIL  % volume_with_top: got=% expected=%',
rec.intkey,
act.volume_with_top,
rec.exp_vol_top;
failed := failed + 1;
END IF;
END LOOP;
RAISE NOTICE '──────────────────────────────────────────────────────────';
RAISE NOTICE 'deadwood: % passed, % failed, % skipped',
passed,
failed,
skipped;
RAISE NOTICE '';
-- ── PG function unit tests ──────────────────────────────────────────
passed := 0;
failed := 0;
RAISE NOTICE '════════════════════════════════════════════════════════════';
RAISE NOTICE 'TEST: PG function unit tests';
RAISE NOTICE '════════════════════════════════════════════════════════════';
-- calc_basal_area
IF abs(derived.calc_basal_area(491) - 0.18934457) / 0.18934457 <= tol_pg THEN passed := passed + 1;
ELSE RAISE NOTICE 'FAIL  calc_basal_area(491) = % expected 0.18934457',
derived.calc_basal_area(491);
failed := failed + 1;
END IF;
IF abs(derived.calc_basal_area(97) - 0.007389812) / 0.007389812 <= tol_pg THEN passed := passed + 1;
ELSE RAISE NOTICE 'FAIL  calc_basal_area(97) = % expected 0.007389812',
derived.calc_basal_area(97);
failed := failed + 1;
END IF;
-- calc_trees_per_hectare
IF abs(
    derived.calc_trees_per_hectare(491, 4) - 21.125505
) / 21.125505 <= tol_pg THEN passed := passed + 1;
ELSE RAISE NOTICE 'FAIL  calc_trees_per_hectare(491,4) = % expected 21.125505',
derived.calc_trees_per_hectare(491, 4);
failed := failed + 1;
END IF;
IF abs(derived.calc_trees_per_hectare(97, 4) - 541.2858) / 541.2858 <= tol_pg THEN passed := passed + 1;
ELSE RAISE NOTICE 'FAIL  calc_trees_per_hectare(97,4) = % expected 541.2858',
derived.calc_trees_per_hectare(97, 4);
failed := failed + 1;
END IF;
-- calc_deadwood_biomass: NDH group (TBagr=1), Tzg=1 → factor=372
IF abs(
    derived.calc_deadwood_biomass(0.8237099, 1, 1) - 306.42007
) / 306.42007 <= tol_pg THEN passed := passed + 1;
ELSE RAISE NOTICE 'FAIL  calc_deadwood_biomass(0.8237,1,1) = % expected 306.42',
derived.calc_deadwood_biomass(0.8237099, 1, 1);
failed := failed + 1;
END IF;
RAISE NOTICE '──────────────────────────────────────────────────────────';
RAISE NOTICE 'PG functions: % passed, % failed',
passed,
failed;
RAISE NOTICE '';
RAISE NOTICE '════════════════════════════════════════════════════════════';
RAISE NOTICE 'ALL TESTS COMPLETE';
RAISE NOTICE '════════════════════════════════════════════════════════════';
END $$;
ROLLBACK;