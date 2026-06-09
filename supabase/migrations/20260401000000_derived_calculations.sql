-- =============================================================================
-- Migration: Derived calculations for inventory_archive trees, regeneration, deadwood
-- 
-- Implements PostgreSQL functions and triggers that automatically compute derived
-- values when tree/regeneration/deadwood records are inserted or updated.
--
-- Simple calculations (basal_area, trees_per_hectare, below_ground_biomass) run
-- directly in PostgreSQL. Complex calculations requiring BDAT (volume_fao,
-- volume_harvest, diameter_30perc, diameter_7m, above_ground_biomass, growing_space)
-- are deferred to the R-Server via pg_notify.
--
-- Source: MSSQL ew-hr22/DB_bwi/ableitungen/400_wzp4/ and DB_bwi/Funktionen/
-- =============================================================================
SET default_transaction_read_only = OFF;
-- Ensure derived schema exists
CREATE SCHEMA IF NOT EXISTS derived;
ALTER SCHEMA derived OWNER TO postgres;
COMMENT ON SCHEMA derived IS 'Derived data computed from inventory_archive';
GRANT USAGE ON SCHEMA derived TO anon,
    authenticated,
    service_role;
GRANT ALL ON ALL TABLES IN SCHEMA derived TO anon,
    authenticated,
    service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA derived
GRANT ALL ON TABLES TO anon,
    authenticated,
    service_role;
-- =============================================================================
-- derived.tree — one row per inventory_archive.tree
-- =============================================================================
CREATE TABLE IF NOT EXISTS derived.tree (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tree_id uuid NOT NULL UNIQUE REFERENCES inventory_archive.tree(id) ON DELETE CASCADE,
    intkey varchar(50) NULL,
    dbh smallint NULL,
    -- [mm] from source or modelled
    trees_per_hectare real NULL,
    -- N/ha from angle-count sampling
    tree_height smallint NULL,
    -- [dm] measured or modelled
    stem_height smallint NULL,
    -- [dm] measured or modelled
    diameter_30perc smallint NULL,
    -- [mm] BDAT shaft curve at 30% height
    diameter_7m smallint NULL,
    -- [mm] BDAT shaft curve at 7m
    basal_area real NULL,
    -- [m²] pi/4*(dbh/1000)²
    volume_fao real NULL,
    -- [m³] BDAT Derbholzvolumen mit Rinde
    volume_harvest real NULL,
    -- [m³] BDAT Erntevolumen
    above_ground_biomass real NULL,
    -- [kg] model by species group
    below_ground_biomass real NULL,
    -- [kg] a*BHD^b by species group
    growing_space real NULL,
    -- [m²] Stf_b0 + Stf_b1 * G
    needs_r_calculation boolean NOT NULL DEFAULT true,
    updated_at timestamptz DEFAULT now()
);
ALTER TABLE derived.tree OWNER TO postgres;
ALTER TABLE derived.tree ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "allow_read_derived_tree" ON derived.tree;
DROP POLICY IF EXISTS "allow_service_role_all" ON derived.tree;
CREATE POLICY "allow_read_derived_tree" ON derived.tree FOR
SELECT TO authenticated, anon USING (true);
CREATE POLICY "allow_service_role_all" ON derived.tree FOR ALL TO service_role USING (true);
-- =============================================================================
-- derived.regeneration — one row per inventory_archive.regeneration
-- =============================================================================
CREATE TABLE IF NOT EXISTS derived.regeneration (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    regeneration_id uuid NOT NULL UNIQUE REFERENCES inventory_archive.regeneration(id) ON DELETE CASCADE,
    intkey varchar(50) NULL,
    dbh smallint NULL,
    trees_per_hectare real NULL,
    tree_height smallint NULL,
    stem_height smallint NULL,
    diameter_30perc smallint NULL,
    diameter_7m smallint NULL,
    basal_area real NULL,
    volume_fao real NULL,
    volume_harvest real NULL,
    above_ground_biomass real NULL,
    below_ground_biomass real NULL,
    growing_space real NULL,
    needs_r_calculation boolean NOT NULL DEFAULT true,
    updated_at timestamptz DEFAULT now()
);
ALTER TABLE derived.regeneration OWNER TO postgres;
ALTER TABLE derived.regeneration ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "allow_read_derived_regen" ON derived.regeneration;
DROP POLICY IF EXISTS "allow_service_role_all_regen" ON derived.regeneration;
CREATE POLICY "allow_read_derived_regen" ON derived.regeneration FOR
SELECT TO authenticated, anon USING (true);
CREATE POLICY "allow_service_role_all_regen" ON derived.regeneration FOR ALL TO service_role USING (true);
-- =============================================================================
-- derived.deadwood — one row per inventory_archive.deadwood
-- =============================================================================
CREATE TABLE IF NOT EXISTS derived.deadwood (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    deadwood_id uuid NOT NULL UNIQUE REFERENCES inventory_archive.deadwood(id) ON DELETE CASCADE,
    intkey varchar(50) NULL,
    volume real NULL,
    -- [m³] cylinder or truncated cone
    volume_with_top real NULL,
    -- [m³] including top
    biomass real NULL,
    -- [kg]
    needs_r_calculation boolean NOT NULL DEFAULT true,
    updated_at timestamptz DEFAULT now()
);
ALTER TABLE derived.deadwood OWNER TO postgres;
ALTER TABLE derived.deadwood ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "allow_read_derived_dw" ON derived.deadwood;
DROP POLICY IF EXISTS "allow_service_role_all_dw" ON derived.deadwood;
CREATE POLICY "allow_read_derived_dw" ON derived.deadwood FOR
SELECT TO authenticated, anon USING (true);
CREATE POLICY "allow_service_role_all_dw" ON derived.deadwood FOR ALL TO service_role USING (true);
-- =============================================================================
-- FUNCTION: derived.calc_basal_area(dbh_mm)
-- Source: t.g.sql — G = pi/4 * (BHD/1000)²
-- =============================================================================
CREATE OR REPLACE FUNCTION derived.calc_basal_area(dbh_mm smallint) RETURNS real LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE AS $$
SELECT (pi() / 4.0 * (dbh_mm::real / 1000.0) ^ 2)::real;
$$;
-- =============================================================================
-- FUNCTION: derived.calc_trees_per_hectare(dbh_mm, baf)
-- Source: t.N_ha_WZP.sql — N_ha = 10000 / (pi * r²), r = dbh/1000 * sqrt(2500/baf)
-- =============================================================================
CREATE OR REPLACE FUNCTION derived.calc_trees_per_hectare(dbh_mm smallint, baf integer DEFAULT 4) RETURNS real LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE AS $$
SELECT (
        10000.0 / (
            pi() * (dbh_mm::real / 1000.0 * sqrt(2500.0 / baf)) ^ 2
        )
    )::real;
$$;
-- =============================================================================
-- FUNCTION: derived.species_to_biomass_group(tree_species_code)
-- Source: t.icode_to_bagr — maps BWI species codes to biomass groups
-- =============================================================================
CREATE OR REPLACE FUNCTION derived.species_to_biomass_group(species_code integer) RETURNS text LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE AS $$
SELECT CASE
        -- Fichte (FI): codes 10-19, 90-99, 914, 927, 930, 932, 933
        WHEN species_code BETWEEN 10 AND 19 THEN 'FI'
        WHEN species_code BETWEEN 90 AND 99 THEN 'FI'
        WHEN species_code IN (914, 927, 930, 932, 933) THEN 'FI' -- Tanne (TA → FI for biomass): codes 30-39, 920, 931
        WHEN species_code BETWEEN 30 AND 39 THEN 'FI'
        WHEN species_code IN (920, 931) THEN 'FI' -- Douglasie (DGL → FI for biomass): codes 40, 907
        WHEN species_code IN (40, 907) THEN 'FI' -- Kiefer (KI): codes 20-29, 918, 928, 937
        WHEN species_code BETWEEN 20 AND 29 THEN 'KI'
        WHEN species_code IN (918, 928, 937) THEN 'KI' -- Lärche (LAE → KI for biomass): codes 50-51, 910, 916, 921
        WHEN species_code IN (50, 51, 910, 916, 921) THEN 'KI' -- Buche (BU): code 100, 906
        WHEN species_code IN (100, 906) THEN 'BU' -- ALH → BU for biomass: codes 120-199, various 900s
        WHEN species_code BETWEEN 120 AND 199 THEN 'BU'
        WHEN species_code IN (
            901,
            902,
            904,
            909,
            912,
            913,
            915,
            917,
            922,
            925,
            926,
            934
        ) THEN 'BU' -- Eiche (EI): codes 110-114, 908, 924
        WHEN species_code BETWEEN 110 AND 114 THEN 'EI'
        WHEN species_code IN (908, 924) THEN 'EI' -- ALN → ALN for below_ground, PA for above_ground: codes 200-299, various 900s
        WHEN species_code BETWEEN 200 AND 299 THEN 'ALN'
        WHEN species_code IN (903, 905, 911, 919, 923, 929, 935, 936) THEN 'ALN'
        ELSE NULL
    END;
$$;
-- =============================================================================
-- FUNCTION: derived.calc_below_ground_biomass(tree_species, dbh_mm)
-- Source: t.biom_u.sql — a * BHD^b per species group (mode='norm')
-- Coefficients hardcoded from MSSQL function
-- =============================================================================
CREATE OR REPLACE FUNCTION derived.calc_below_ground_biomass(species_code integer, dbh_mm smallint) RETURNS real LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE AS $$
DECLARE bhd real;
grp text;
BEGIN IF dbh_mm <= 0 THEN RETURN 0.0;
END IF;
bhd := dbh_mm::real / 10.0;
-- convert mm to cm
grp := derived.species_to_biomass_group(species_code);
IF grp IS NULL THEN RETURN NULL;
END IF;
-- biom_u 'norm' mode: a * BHD^b
RETURN CASE
    grp
    WHEN 'FI' THEN (0.003720 * power(bhd, 2.792465))::real
    WHEN 'KI' THEN (0.006089 * power(bhd, 2.739073))::real
    WHEN 'BU' THEN (0.018256 * power(bhd, 2.321997))::real
    WHEN 'EI' THEN (0.028 * power(bhd, 2.44))::real
    WHEN 'ALN' THEN (
        (0.000010 * power(bhd * 10, 2.5290)) + (0.000116 * power(bhd * 10, 2.2903))
    )::real
    ELSE NULL
END;
END;
$$;
-- =============================================================================
-- TRIGGER FUNCTION: Auto-compute derived.tree on INSERT/UPDATE
-- Computes: basal_area, trees_per_hectare, below_ground_biomass immediately.
-- Sets needs_r_calculation = true for BDAT-dependent values.
-- Sends pg_notify to trigger R-Server for complex calculations.
-- =============================================================================
CREATE OR REPLACE FUNCTION derived.on_tree_change() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE computed_basal_area real;
computed_trees_per_ha real;
computed_biom_u real;
BEGIN -- Compute simple derived values
IF NEW.dbh IS NOT NULL
AND NEW.dbh > 0 THEN computed_basal_area := derived.calc_basal_area(NEW.dbh);
computed_trees_per_ha := derived.calc_trees_per_hectare(NEW.dbh, 4);
END IF;
IF NEW.dbh IS NOT NULL
AND NEW.tree_species IS NOT NULL THEN computed_biom_u := derived.calc_below_ground_biomass(NEW.tree_species, NEW.dbh);
END IF;
-- Upsert into derived.tree
INSERT INTO derived.tree (
        tree_id,
        intkey,
        dbh,
        basal_area,
        trees_per_hectare,
        below_ground_biomass,
        tree_height,
        stem_height,
        needs_r_calculation,
        updated_at
    )
VALUES (
        NEW.id,
        NEW.intkey,
        NEW.dbh,
        computed_basal_area,
        computed_trees_per_ha,
        computed_biom_u,
        NEW.tree_height,
        NEW.stem_height,
        true,
        now()
    ) ON CONFLICT (tree_id) DO
UPDATE
SET intkey = EXCLUDED.intkey,
    dbh = EXCLUDED.dbh,
    basal_area = EXCLUDED.basal_area,
    trees_per_hectare = EXCLUDED.trees_per_hectare,
    below_ground_biomass = EXCLUDED.below_ground_biomass,
    tree_height = EXCLUDED.tree_height,
    stem_height = EXCLUDED.stem_height,
    needs_r_calculation = true,
    updated_at = now();
-- Notify R-Server for BDAT-dependent calculations
PERFORM pg_notify(
    'derived_tree_changed',
    json_build_object(
        'tree_id',
        NEW.id,
        'tree_species',
        NEW.tree_species,
        'dbh',
        NEW.dbh,
        'tree_height',
        NEW.tree_height,
        'stem_height',
        NEW.stem_height,
        'stem_breakage',
        NEW.stem_breakage,
        'stem_form',
        NEW.stem_form
    )::text
);
RETURN NEW;
END;
$$;
-- =============================================================================
-- FUNCTION: derived.calc_deadwood_biomass(species_group, decomposition, volume)
-- Source: xyk1.k_biom_tot — biomass [kg] = volume [m³] × factor
-- TBagr: 1=NDH (conifers), 2=LBH (broadleaves excl. oak), 3=EI (oak)
-- Tzg: 1=unzersetzt, 2=beginnende Zersetzung, 3=fortgeschrittene, 4=stark vermodert
-- =============================================================================
CREATE OR REPLACE FUNCTION derived.calc_deadwood_biomass(
        species_group integer,
        decomposition integer,
        volume real
    ) RETURNS real LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
SELECT CASE
        WHEN species_group IS NULL
        OR decomposition IS NULL
        OR volume IS NULL THEN NULL
        ELSE volume * (
            SELECT factor_kg
            FROM (
                    VALUES (1, 1, 372.0),
                        (1, 2, 308.0),
                        (1, 3, 141.0),
                        (1, 4, 123.0),
                        (2, 1, 580.0),
                        (2, 2, 370.0),
                        (2, 3, 210.0),
                        (2, 4, 260.0),
                        (3, 1, 580.0),
                        (3, 2, 370.0),
                        (3, 3, 210.0),
                        (3, 4, 260.0)
                ) AS t(tbagr, tzg, factor_kg)
            WHERE t.tbagr = species_group
                AND t.tzg = decomposition
        )
    END;
$$;
-- =============================================================================
-- TRIGGER FUNCTION: Auto-compute derived.deadwood on INSERT/UPDATE
-- Computes volume (cylinder/truncated cone) and biomass immediately.
-- =============================================================================
CREATE OR REPLACE FUNCTION derived.on_deadwood_change() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE computed_volume real;
computed_volume_with_top real;
computed_biomass real;
BEGIN -- Volume calculation based on deadwood type
-- Type determines geometry: cylinder (stump, lying log same diameter) or truncated cone
IF NEW.diameter_butt IS NOT NULL
AND NEW.length_height IS NOT NULL THEN IF NEW.diameter_top IS NOT NULL
AND NEW.diameter_top != NEW.diameter_butt THEN -- Truncated cone: pi*l/12*(d1² + d1*d2 + d2²)
-- diameter in cm, length in dm → volume in m³
computed_volume := (
    pi() * (NEW.length_height::real / 10.0) / 12.0 * (
        (NEW.diameter_butt::real / 100.0) ^ 2 + (NEW.diameter_butt::real / 100.0) * (NEW.diameter_top::real / 100.0) + (NEW.diameter_top::real / 100.0) ^ 2
    )
)::real;
ELSE -- Cylinder: pi/4 * d² * l
computed_volume := (
    pi() / 4.0 * (NEW.diameter_butt::real / 100.0) ^ 2 * (NEW.length_height::real / 10.0)
)::real;
END IF;
END IF;
-- volume_with_top: for non-BDAT types (4=Wurzelstock, 5=Abfuhrrest, 13=Teilstück)
-- equals volume. For BDAT types (2,3,11,12) stays NULL until R-Server computes via rBDAT.
IF computed_volume IS NOT NULL
AND NEW.dead_wood_type NOT IN (2, 3, 11, 12) THEN computed_volume_with_top := computed_volume;
END IF;
-- Biomass from k_biom_tot lookup
IF computed_volume IS NOT NULL
AND NEW.tree_species_group IS NOT NULL
AND NEW.decomposition IS NOT NULL THEN computed_biomass := derived.calc_deadwood_biomass(
    NEW.tree_species_group,
    NEW.decomposition,
    computed_volume
);
END IF;
INSERT INTO derived.deadwood (
        deadwood_id,
        intkey,
        volume,
        volume_with_top,
        biomass,
        needs_r_calculation,
        updated_at
    )
VALUES (
        NEW.id,
        NEW.intkey,
        computed_volume,
        computed_volume_with_top,
        computed_biomass,
        true,
        now()
    ) ON CONFLICT (deadwood_id) DO
UPDATE
SET intkey = EXCLUDED.intkey,
    volume = EXCLUDED.volume,
    volume_with_top = EXCLUDED.volume_with_top,
    biomass = EXCLUDED.biomass,
    needs_r_calculation = true,
    updated_at = now();
PERFORM pg_notify(
    'derived_deadwood_changed',
    json_build_object(
        'deadwood_id',
        NEW.id,
        'tree_species_group',
        NEW.tree_species_group,
        'dead_wood_type',
        NEW.dead_wood_type,
        'diameter_butt',
        NEW.diameter_butt,
        'diameter_top',
        NEW.diameter_top,
        'length_height',
        NEW.length_height
    )::text
);
RETURN NEW;
END;
$$;
-- =============================================================================
-- TRIGGER FUNCTION: Auto-compute derived.regeneration
-- =============================================================================
CREATE OR REPLACE FUNCTION derived.on_regeneration_change() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$ BEGIN -- Regeneration trees are counted in fixed-area circles, 
    -- derived values depend on tree_size_class (lookup x_gr) → requires R-Server
INSERT INTO derived.regeneration (
        regeneration_id,
        intkey,
        needs_r_calculation,
        updated_at
    )
VALUES (
        NEW.id,
        NEW.intkey,
        true,
        now()
    ) ON CONFLICT (regeneration_id) DO
UPDATE
SET intkey = EXCLUDED.intkey,
    needs_r_calculation = true,
    updated_at = now();
PERFORM pg_notify(
    'derived_regeneration_changed',
    json_build_object(
        'regeneration_id',
        NEW.id,
        'tree_species',
        NEW.tree_species,
        'tree_size_class',
        NEW.tree_size_class,
        'tree_count',
        NEW.tree_count
    )::text
);
RETURN NEW;
END;
$$;
-- =============================================================================
-- ATTACH TRIGGERS
-- =============================================================================
DROP TRIGGER IF EXISTS trg_derived_tree ON inventory_archive.tree;
CREATE TRIGGER trg_derived_tree
AFTER
INSERT
    OR
UPDATE OF dbh,
    tree_height,
    stem_height,
    tree_species,
    stem_breakage,
    stem_form,
    within_stand ON inventory_archive.tree FOR EACH ROW EXECUTE FUNCTION derived.on_tree_change();
DROP TRIGGER IF EXISTS trg_derived_deadwood ON inventory_archive.deadwood;
CREATE TRIGGER trg_derived_deadwood
AFTER
INSERT
    OR
UPDATE OF diameter_butt,
    diameter_top,
    length_height,
    tree_species_group,
    dead_wood_type ON inventory_archive.deadwood FOR EACH ROW EXECUTE FUNCTION derived.on_deadwood_change();
DROP TRIGGER IF EXISTS trg_derived_regeneration ON inventory_archive.regeneration;
CREATE TRIGGER trg_derived_regeneration
AFTER
INSERT
    OR
UPDATE OF tree_species,
    tree_size_class,
    tree_count ON inventory_archive.regeneration FOR EACH ROW EXECUTE FUNCTION derived.on_regeneration_change();
-- =============================================================================
-- BACKFILL: Compute derived values for all existing rows in inventory_archive.
--
-- The triggers only fire on INSERT/UPDATE, so rows that existed before this
-- migration have no derived.* entries yet. These functions perform a no-op
-- UPDATE on each source table, which fires the trigger and populates
-- the derived tables (PG-computable values immediately, BDAT via R-Server).
--
-- Usage:
--   SELECT derived.backfill_trees();        -- just trees
--   SELECT derived.backfill_deadwood();      -- just deadwood
--   SELECT derived.backfill_regeneration();  -- just regeneration
--   SELECT derived.backfill_all();           -- everything
--
-- After backfill, call the R-Server endpoint to compute BDAT-dependent values:
--   GET /run-script/tree_derived
--   GET /run-script/deadwood
-- =============================================================================
CREATE OR REPLACE FUNCTION derived.backfill_trees() RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE affected bigint;
BEGIN -- Directly insert derived rows for trees that don't have one yet.
-- Computes PG-computable values; sets needs_r_calculation=true for BDAT values.
WITH inserted AS (
    INSERT INTO derived.tree (
            tree_id,
            intkey,
            dbh,
            tree_height,
            stem_height,
            basal_area,
            trees_per_hectare,
            below_ground_biomass,
            needs_r_calculation,
            updated_at
        )
    SELECT t.id,
        t.intkey,
        t.dbh,
        t.tree_height,
        t.stem_height,
        CASE
            WHEN t.dbh IS NOT NULL
            AND t.dbh > 0 THEN derived.calc_basal_area(t.dbh)
        END,
        CASE
            WHEN t.dbh IS NOT NULL
            AND t.dbh > 0 THEN derived.calc_trees_per_hectare(t.dbh, 4)
        END,
        CASE
            WHEN t.dbh IS NOT NULL
            AND t.tree_species IS NOT NULL THEN derived.calc_below_ground_biomass(t.tree_species, t.dbh)
        END,
        true,
        now()
    FROM inventory_archive.tree t
    WHERE t.id NOT IN (
            SELECT tree_id
            FROM derived.tree
        ) ON CONFLICT (tree_id) DO NOTHING
    RETURNING 1
)
SELECT count(*) INTO affected
FROM inserted;
RAISE NOTICE 'Backfilled % tree rows into derived.tree',
affected;
-- Signal the R-Server listener to process all pending rows
IF affected > 0 THEN PERFORM pg_notify(
    'derived_tree_changed',
    json_build_object('backfill', true, 'count', affected)::text
);
END IF;
RETURN affected;
END;
$$;
CREATE OR REPLACE FUNCTION derived.backfill_deadwood() RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE affected bigint;
BEGIN WITH inserted AS (
    INSERT INTO derived.deadwood (
            deadwood_id,
            intkey,
            volume,
            volume_with_top,
            biomass,
            needs_r_calculation,
            updated_at
        )
    SELECT d.id,
        d.intkey,
        -- Volume: truncated cone or cylinder
        CASE
            WHEN d.diameter_butt IS NOT NULL
            AND d.length_height IS NOT NULL THEN CASE
                WHEN d.diameter_top IS NOT NULL
                AND d.diameter_top != d.diameter_butt THEN (
                    pi() * (d.length_height::real / 10.0) / 12.0 * (
                        (d.diameter_butt::real / 100.0) ^ 2 + (d.diameter_butt::real / 100.0) * (d.diameter_top::real / 100.0) + (d.diameter_top::real / 100.0) ^ 2
                    )
                )::real
                ELSE (
                    pi() / 4.0 * (d.diameter_butt::real / 100.0) ^ 2 * (d.length_height::real / 10.0)
                )::real
            END
        END,
        -- volume_with_top: same as volume for non-BDAT types (4,5,13), NULL for BDAT types (2,3,11,12)
        CASE
            WHEN d.diameter_butt IS NOT NULL
            AND d.length_height IS NOT NULL
            AND d.dead_wood_type NOT IN (2, 3, 11, 12) THEN CASE
                WHEN d.diameter_top IS NOT NULL
                AND d.diameter_top != d.diameter_butt THEN (
                    pi() * (d.length_height::real / 10.0) / 12.0 * (
                        (d.diameter_butt::real / 100.0) ^ 2 + (d.diameter_butt::real / 100.0) * (d.diameter_top::real / 100.0) + (d.diameter_top::real / 100.0) ^ 2
                    )
                )::real
                ELSE (
                    pi() / 4.0 * (d.diameter_butt::real / 100.0) ^ 2 * (d.length_height::real / 10.0)
                )::real
            END
        END,
        -- Biomass from k_biom_tot
        CASE
            WHEN d.diameter_butt IS NOT NULL
            AND d.length_height IS NOT NULL
            AND d.tree_species_group IS NOT NULL
            AND d.decomposition IS NOT NULL THEN derived.calc_deadwood_biomass(
                d.tree_species_group,
                d.decomposition,
                CASE
                    WHEN d.diameter_top IS NOT NULL
                    AND d.diameter_top != d.diameter_butt THEN (
                        pi() * (d.length_height::real / 10.0) / 12.0 * (
                            (d.diameter_butt::real / 100.0) ^ 2 + (d.diameter_butt::real / 100.0) * (d.diameter_top::real / 100.0) + (d.diameter_top::real / 100.0) ^ 2
                        )
                    )::real
                    ELSE (
                        pi() / 4.0 * (d.diameter_butt::real / 100.0) ^ 2 * (d.length_height::real / 10.0)
                    )::real
                END
            )
        END,
        true,
        now()
    FROM inventory_archive.deadwood d
    WHERE d.id NOT IN (
            SELECT deadwood_id
            FROM derived.deadwood
        ) ON CONFLICT (deadwood_id) DO NOTHING
    RETURNING 1
)
SELECT count(*) INTO affected
FROM inserted;
RAISE NOTICE 'Backfilled % deadwood rows into derived.deadwood',
affected;
IF affected > 0 THEN PERFORM pg_notify(
    'derived_deadwood_changed',
    json_build_object('backfill', true, 'count', affected)::text
);
END IF;
RETURN affected;
END;
$$;
CREATE OR REPLACE FUNCTION derived.backfill_regeneration() RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE affected bigint;
BEGIN WITH inserted AS (
    INSERT INTO derived.regeneration (
            regeneration_id,
            intkey,
            needs_r_calculation,
            updated_at
        )
    SELECT r.id,
        r.intkey,
        true,
        now()
    FROM inventory_archive.regeneration r
    WHERE r.id NOT IN (
            SELECT regeneration_id
            FROM derived.regeneration
        ) ON CONFLICT (regeneration_id) DO NOTHING
    RETURNING 1
)
SELECT count(*) INTO affected
FROM inserted;
RAISE NOTICE 'Backfilled % regeneration rows into derived.regeneration',
affected;
IF affected > 0 THEN PERFORM pg_notify(
    'derived_regeneration_changed',
    json_build_object('backfill', true, 'count', affected)::text
);
END IF;
RETURN affected;
END;
$$;
CREATE OR REPLACE FUNCTION derived.backfill_all() RETURNS TABLE(
        trees bigint,
        deadwood bigint,
        regeneration bigint
    ) LANGUAGE plpgsql SECURITY DEFINER AS $$ BEGIN RETURN QUERY
SELECT derived.backfill_trees() AS trees,
    derived.backfill_deadwood() AS deadwood,
    derived.backfill_regeneration() AS regeneration;
END;
$$;
-- Check counts match
-- SELECT 'source' AS tbl, count(*) FROM inventory_archive.tree
-- UNION ALL
-- SELECT 'derived', count(*) FROM derived.tree;
-- =============================================================================
-- Migration: Fix regeneration trigger (compute all PG fields) + deadwood volume_with_top
--
-- Regeneration uses x_gr lookup (mean BHD/height per size class) and
-- k_VolBhdU7 lookup (volume for BHD < 70mm) to derive:
--   N_ha, dbh, basal_area, below_ground_biomass, volume_fao
--
-- Source: MSSQL 300_jung.sql / sp3z_410baeume_insert.sql
-- =============================================================================
SET default_transaction_read_only = OFF;
-- =============================================================================
-- FUNCTION: derived.x_gr_lookup(tree_size_class)
-- Returns a composite of (MWBhd, Bio_oBhd, Bio_oHoe, Bio_uBhd) from x_gr table.
-- Source: bwi.xyk.x_gr
-- =============================================================================
CREATE OR REPLACE FUNCTION derived.x_gr_lookup(
        size_class integer,
        OUT mw_bhd smallint,
        -- [mm] mean BHD for this size class
        OUT bio_o_bhd smallint,
        -- [mm] BHD for biom_o calculation
        OUT bio_o_hoe smallint,
        -- [dm] height for biom_o calculation
        OUT bio_u_bhd smallint -- [mm] BHD for biom_u calculation
    ) RETURNS record LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE AS $$
SELECT mw_bhd,
    bio_o_bhd,
    bio_o_hoe,
    bio_u_bhd
FROM (
        VALUES -- ICode, MWBhd, Bio_oBhd, Bio_oHoe, Bio_uBhd
            (
                0,
                1::smallint,
                0::smallint,
                3::smallint,
                10::smallint
            ),
            -- 20-50cm height
            (
                1,
                1::smallint,
                0::smallint,
                9::smallint,
                20::smallint
            ),
            -- 50-130cm height
            (
                2,
                25::smallint,
                25::smallint,
                0::smallint,
                25::smallint
            ),
            -- >130cm, BHD ≤ 4.9cm
            (
                5,
                55::smallint,
                55::smallint,
                0::smallint,
                55::smallint
            ),
            -- 5.0-5.9cm BHD
            (
                6,
                65::smallint,
                65::smallint,
                0::smallint,
                65::smallint
            ),
            -- 6.0-6.9cm BHD
            (
                9,
                30::smallint,
                35::smallint,
                0::smallint,
                35::smallint
            ) -- >130cm, BHD<7cm (Nebenbestand)
    ) AS t(icode, mw_bhd, bio_o_bhd, bio_o_hoe, bio_u_bhd)
WHERE t.icode = size_class;
$$;
-- =============================================================================
-- FUNCTION: derived.species_to_babwi(tree_species_code)
-- Maps BWI species codes to BaBWI groups (1-9) for k_VolBhdU7 lookup.
-- Source: bwi.xyk.x_ba.Zu_BaBWI
-- =============================================================================
CREATE OR REPLACE FUNCTION derived.species_to_babwi(species_code integer) RETURNS integer LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE AS $$
SELECT CASE
        WHEN species_code BETWEEN 10 AND 19 THEN 1 -- Fichte
        WHEN species_code BETWEEN 30 AND 39 THEN 2 -- Tanne
        WHEN species_code IN (40) THEN 3 -- Douglasie
        WHEN species_code BETWEEN 20 AND 29 THEN 4 -- Kiefer
        WHEN species_code IN (50, 51) THEN 5 -- Lärche
        WHEN species_code BETWEEN 90 AND 99 THEN 6 -- sonstige NDH
        WHEN species_code IN (100, 130) THEN 7 -- Buche, Hainbuche
        WHEN species_code BETWEEN 110 AND 114 THEN 8 -- Eiche
        -- sonstige LBH (all other broadleaves)
        WHEN species_code BETWEEN 120 AND 299 THEN 9
        WHEN species_code >= 900 THEN 9
        ELSE NULL
    END;
$$;
-- =============================================================================
-- FUNCTION: derived.k_vol_bhd_u7(babwi, bhd_mm)
-- Volume [m³] for small trees (BHD < 70mm) from k_VolBhdU7 lookup.
-- Source: bwi.xyk.k_VolBhdU7
-- Returns NULL if BHD not in lookup (1, 25, 55, 65mm).
-- =============================================================================
CREATE OR REPLACE FUNCTION derived.k_vol_bhd_u7(babwi integer, bhd_mm integer) RETURNS real LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
SELECT CASE
        WHEN babwi IS NULL
        OR bhd_mm IS NULL THEN NULL
        ELSE (
            SELECT vol_r::real
            FROM (
                    VALUES (1, 1, 0.0),
                        (1, 25, 0.001146081),
                        (1, 55, 0.009202038),
                        (1, 65, 0.01430739),
                        (2, 1, 0.0),
                        (2, 25, 0.001065996),
                        (2, 55, 0.008451154),
                        (2, 65, 0.01310464),
                        (3, 1, 0.0),
                        (3, 25, 0.001112065),
                        (3, 55, 0.008760558),
                        (3, 65, 0.01356614),
                        (4, 1, 0.0),
                        (4, 25, 0.001211409),
                        (4, 55, 0.009051539),
                        (4, 65, 0.01386055),
                        (5, 1, 0.0),
                        (5, 25, 0.0009592844),
                        (5, 55, 0.008075253),
                        (5, 65, 0.0126819),
                        (6, 1, 0.0),
                        (6, 25, 0.0007823997),
                        (6, 55, 0.007183764),
                        (6, 65, 0.01149135),
                        (7, 1, 0.0),
                        (7, 25, 0.000968387),
                        (7, 55, 0.007765834),
                        (7, 65, 0.01207125),
                        (8, 1, 0.0),
                        (8, 25, 0.001195477),
                        (8, 55, 0.008981243),
                        (8, 65, 0.01376877),
                        (9, 1, 0.0),
                        (9, 25, 0.001265588),
                        (9, 55, 0.009745962),
                        (9, 65, 0.0150196)
                ) AS t(grp, bhd, vol_r)
            WHERE t.grp = babwi
                AND t.bhd = bhd_mm
        )
    END;
$$;
-- =============================================================================
-- FUNCTION: derived.calc_above_ground_biomass_regen(species_code, bio_o_bhd_mm, bio_o_hoe_dm)
-- Above-ground biomass for regeneration using k1 (height-only) or k2 (small-tree) model.
-- Source: MSSQL t.biom_o — 'mk' mode, BHD < 100mm only.
-- Coefficients from xyk1.x_biom_o_k1 and xyk1.x_biom_o_k2.
-- =============================================================================
CREATE OR REPLACE FUNCTION derived.calc_above_ground_biomass_regen(
        species_code integer,
        bio_o_bhd_mm smallint,
        -- [mm] BHD for biom_o from x_gr (0 for height-only model)
        bio_o_hoe_dm smallint -- [dm] height for biom_o from x_gr (0 when using BHD model)
    ) RETURNS real LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE grp text;
bhd_cm real;
hoe_m real;
-- k1 coefficients (height-only, BHD=0)
k1_b0_h real;
k1_b1_h real;
-- k2 coefficients (small tree, 0 < BHD < 10cm)
k2_b0 real;
k2_bs real;
k2_b3 real;
BEGIN IF species_code IS NULL THEN RETURN NULL;
END IF;
grp := derived.species_to_biomass_group(species_code);
-- For biom_o: ALN → PA
IF grp = 'ALN' THEN grp := 'PA';
END IF;
IF grp IS NULL THEN RETURN NULL;
END IF;
bhd_cm := COALESCE(bio_o_bhd_mm, 0)::real / 10.0;
hoe_m := COALESCE(bio_o_hoe_dm, 0)::real / 10.0;
IF bhd_cm = 0
AND hoe_m > 0 THEN -- k1: height-only model (size class 0, 1)
-- Source: xyk1.x_biom_o_k1
IF grp IN ('FI', 'KI') THEN k1_b0_h := 0.23059;
k1_b1_h := 2.20101;
-- Conifers
ELSE k1_b0_h := 0.0494;
k1_b1_h := 2.54946;
-- Broadleaves (BU, EI, PA)
END IF;
RETURN (k1_b0_h * power(hoe_m, k1_b1_h))::real;
ELSIF bhd_cm > 0
AND bhd_cm < 10 THEN -- k2: small-tree model (size class 2, 5, 6, 9)
-- Source: xyk1.x_biom_o_k2
-- Formula: biom_o = b0 + ((bs-b0)/100 + b3*(bhd_cm-10)) * bhd_cm²
CASE
    grp
    WHEN 'FI' THEN k2_b0 := 0.4108;
k2_bs := 26.63122;
k2_b3 := 0.0137;
WHEN 'KI' THEN k2_b0 := 0.4108;
k2_bs := 19.99943;
k2_b3 := 0.00916;
WHEN 'BU' THEN k2_b0 := 0.09644;
k2_bs := 33.22328;
k2_b3 := 0.01162;
WHEN 'EI' THEN k2_b0 := 0.09644;
k2_bs := 28.94782;
k2_b3 := 0.01501;
WHEN 'PA' THEN k2_b0 := 0.09644;
k2_bs := 16.86101;
k2_b3 := -0.00551;
ELSE RETURN NULL;
END CASE
;
RETURN (
    k2_b0 + (
        (k2_bs - k2_b0) / 100.0 + k2_b3 * (bhd_cm - 10.0)
    ) * bhd_cm * bhd_cm
)::real;
ELSE RETURN NULL;
-- No valid input
END IF;
END;
$$;
-- =============================================================================
-- Replace regeneration trigger: compute ALL fields directly in PG.
-- N_ha, dbh, basal_area, below_ground_biomass, volume_fao, above_ground_biomass.
-- No R-Server needed for regeneration (all BHD < 70mm → k1/k2 models).
-- =============================================================================
CREATE OR REPLACE FUNCTION derived.on_regeneration_change() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE xgr record;
computed_n_ha real;
computed_basal_area real;
computed_biom_u real;
computed_biom_o real;
computed_vol_fao real;
babwi integer;
BEGIN -- Look up mean values from x_gr
SELECT * INTO xgr
FROM derived.x_gr_lookup(NEW.tree_size_class);
IF xgr IS NOT NULL
AND xgr.mw_bhd IS NOT NULL THEN -- N_ha: all regeneration in inventory_archive uses 2m radius circle (Bnr >= 2000)
-- N_ha = Anz * 10000 / (π * r²) where r=2m → denominator = 4π = 12.566
computed_n_ha := (NEW.tree_count::real * 10000.0 / (pi() * 4.0))::real;
-- Basal area from mean BHD
IF xgr.mw_bhd > 0 THEN computed_basal_area := derived.calc_basal_area(xgr.mw_bhd);
END IF;
-- Below-ground biomass from Bio_uBhd
IF NEW.tree_species IS NOT NULL
AND xgr.bio_u_bhd IS NOT NULL
AND xgr.bio_u_bhd > 0 THEN computed_biom_u := derived.calc_below_ground_biomass(NEW.tree_species, xgr.bio_u_bhd);
END IF;
-- Volume FAO from k_VolBhdU7 for BHD < 70mm
IF NEW.tree_species IS NOT NULL
AND xgr.mw_bhd < 70 THEN babwi := derived.species_to_babwi(NEW.tree_species);
computed_vol_fao := derived.k_vol_bhd_u7(babwi, xgr.mw_bhd::integer);
END IF;
-- Above-ground biomass from k1/k2 model
IF NEW.tree_species IS NOT NULL THEN computed_biom_o := derived.calc_above_ground_biomass_regen(
    NEW.tree_species,
    xgr.bio_o_bhd,
    xgr.bio_o_hoe
);
END IF;
END IF;
INSERT INTO derived.regeneration (
        regeneration_id,
        intkey,
        dbh,
        trees_per_hectare,
        basal_area,
        below_ground_biomass,
        above_ground_biomass,
        volume_fao,
        needs_r_calculation,
        updated_at
    )
VALUES (
        NEW.id,
        NEW.intkey,
        xgr.mw_bhd,
        computed_n_ha,
        computed_basal_area,
        computed_biom_u,
        computed_biom_o,
        computed_vol_fao,
        false,
        now()
    ) ON CONFLICT (regeneration_id) DO
UPDATE
SET intkey = EXCLUDED.intkey,
    dbh = EXCLUDED.dbh,
    trees_per_hectare = EXCLUDED.trees_per_hectare,
    basal_area = EXCLUDED.basal_area,
    below_ground_biomass = EXCLUDED.below_ground_biomass,
    above_ground_biomass = EXCLUDED.above_ground_biomass,
    volume_fao = EXCLUDED.volume_fao,
    needs_r_calculation = false,
    updated_at = now();
PERFORM pg_notify(
    'derived_regeneration_changed',
    json_build_object(
        'regeneration_id',
        NEW.id,
        'tree_species',
        NEW.tree_species,
        'tree_size_class',
        NEW.tree_size_class,
        'tree_count',
        NEW.tree_count
    )::text
);
RETURN NEW;
END;
$$;
-- =============================================================================
-- Replace tree backfill: use ON CONFLICT DO UPDATE so re-running backfill
-- overwrites stale/NULL rows instead of skipping them.
-- =============================================================================
CREATE OR REPLACE FUNCTION derived.backfill_trees() RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE affected bigint;
BEGIN WITH inserted AS (
    INSERT INTO derived.tree (
            tree_id,
            intkey,
            dbh,
            tree_height,
            stem_height,
            basal_area,
            trees_per_hectare,
            below_ground_biomass,
            needs_r_calculation,
            updated_at
        )
    SELECT t.id,
        t.intkey,
        t.dbh,
        t.tree_height,
        t.stem_height,
        CASE
            WHEN t.dbh IS NOT NULL
            AND t.dbh > 0 THEN derived.calc_basal_area(t.dbh)
        END,
        CASE
            WHEN t.dbh IS NOT NULL
            AND t.dbh > 0 THEN derived.calc_trees_per_hectare(t.dbh, 4)
        END,
        CASE
            WHEN t.dbh IS NOT NULL
            AND t.tree_species IS NOT NULL THEN derived.calc_below_ground_biomass(t.tree_species, t.dbh)
        END,
        true,
        now()
    FROM inventory_archive.tree t ON CONFLICT (tree_id) DO
    UPDATE
    SET intkey = EXCLUDED.intkey,
        dbh = EXCLUDED.dbh,
        tree_height = EXCLUDED.tree_height,
        stem_height = EXCLUDED.stem_height,
        basal_area = EXCLUDED.basal_area,
        trees_per_hectare = EXCLUDED.trees_per_hectare,
        below_ground_biomass = EXCLUDED.below_ground_biomass,
        needs_r_calculation = true,
        updated_at = now()
    RETURNING 1
)
SELECT count(*) INTO affected
FROM inserted;
RAISE NOTICE 'Backfilled % tree rows into derived.tree',
affected;
IF affected > 0 THEN PERFORM pg_notify(
    'derived_tree_changed',
    json_build_object('backfill', true, 'count', affected)::text
);
END IF;
RETURN affected;
END;
$$;
-- =============================================================================
-- Replace deadwood backfill: use ON CONFLICT DO UPDATE so re-running backfill
-- overwrites stale/NULL rows instead of skipping them.
-- =============================================================================
CREATE OR REPLACE FUNCTION derived.backfill_deadwood() RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE affected bigint;
BEGIN WITH inserted AS (
    INSERT INTO derived.deadwood (
            deadwood_id,
            intkey,
            volume,
            volume_with_top,
            biomass,
            needs_r_calculation,
            updated_at
        )
    SELECT d.id,
        d.intkey,
        -- Volume: truncated cone or cylinder
        CASE
            WHEN d.diameter_butt IS NOT NULL
            AND d.length_height IS NOT NULL THEN CASE
                WHEN d.diameter_top IS NOT NULL
                AND d.diameter_top != d.diameter_butt THEN (
                    pi() * (d.length_height::real / 10.0) / 12.0 * (
                        (d.diameter_butt::real / 100.0) ^ 2 + (d.diameter_butt::real / 100.0) * (d.diameter_top::real / 100.0) + (d.diameter_top::real / 100.0) ^ 2
                    )
                )::real
                ELSE (
                    pi() / 4.0 * (d.diameter_butt::real / 100.0) ^ 2 * (d.length_height::real / 10.0)
                )::real
            END
        END,
        -- volume_with_top: same as volume for non-BDAT types (4,5,13), NULL for BDAT types (2,3,11,12)
        CASE
            WHEN d.diameter_butt IS NOT NULL
            AND d.length_height IS NOT NULL
            AND d.dead_wood_type NOT IN (2, 3, 11, 12) THEN CASE
                WHEN d.diameter_top IS NOT NULL
                AND d.diameter_top != d.diameter_butt THEN (
                    pi() * (d.length_height::real / 10.0) / 12.0 * (
                        (d.diameter_butt::real / 100.0) ^ 2 + (d.diameter_butt::real / 100.0) * (d.diameter_top::real / 100.0) + (d.diameter_top::real / 100.0) ^ 2
                    )
                )::real
                ELSE (
                    pi() / 4.0 * (d.diameter_butt::real / 100.0) ^ 2 * (d.length_height::real / 10.0)
                )::real
            END
        END,
        -- Biomass from k_biom_tot
        CASE
            WHEN d.diameter_butt IS NOT NULL
            AND d.length_height IS NOT NULL
            AND d.tree_species_group IS NOT NULL
            AND d.decomposition IS NOT NULL THEN derived.calc_deadwood_biomass(
                d.tree_species_group,
                d.decomposition,
                CASE
                    WHEN d.diameter_top IS NOT NULL
                    AND d.diameter_top != d.diameter_butt THEN (
                        pi() * (d.length_height::real / 10.0) / 12.0 * (
                            (d.diameter_butt::real / 100.0) ^ 2 + (d.diameter_butt::real / 100.0) * (d.diameter_top::real / 100.0) + (d.diameter_top::real / 100.0) ^ 2
                        )
                    )::real
                    ELSE (
                        pi() / 4.0 * (d.diameter_butt::real / 100.0) ^ 2 * (d.length_height::real / 10.0)
                    )::real
                END
            )
        END,
        true,
        now()
    FROM inventory_archive.deadwood d ON CONFLICT (deadwood_id) DO
    UPDATE
    SET intkey = EXCLUDED.intkey,
        volume = EXCLUDED.volume,
        volume_with_top = EXCLUDED.volume_with_top,
        biomass = EXCLUDED.biomass,
        needs_r_calculation = true,
        updated_at = now()
    RETURNING 1
)
SELECT count(*) INTO affected
FROM inserted;
RAISE NOTICE 'Backfilled % deadwood rows into derived.deadwood',
affected;
IF affected > 0 THEN PERFORM pg_notify(
    'derived_deadwood_changed',
    json_build_object('backfill', true, 'count', affected)::text
);
END IF;
RETURN affected;
END;
$$;
-- =============================================================================
-- Replace regeneration backfill: directly computes PG-available values.
-- =============================================================================
CREATE OR REPLACE FUNCTION derived.backfill_regeneration() RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE affected bigint;
BEGIN WITH inserted AS (
    INSERT INTO derived.regeneration (
            regeneration_id,
            intkey,
            dbh,
            trees_per_hectare,
            basal_area,
            below_ground_biomass,
            above_ground_biomass,
            volume_fao,
            needs_r_calculation,
            updated_at
        )
    SELECT r.id,
        r.intkey,
        xgr.mw_bhd,
        -- N_ha: tree_count * 10000 / (π × 4)  [2m radius circle]
        (r.tree_count::real * 10000.0 / (pi() * 4.0))::real,
        -- basal_area from mean BHD
        CASE
            WHEN xgr.mw_bhd > 0 THEN derived.calc_basal_area(xgr.mw_bhd)
        END,
        -- below_ground_biomass from Bio_uBhd
        CASE
            WHEN r.tree_species IS NOT NULL
            AND xgr.bio_u_bhd > 0 THEN derived.calc_below_ground_biomass(r.tree_species, xgr.bio_u_bhd)
        END,
        -- above_ground_biomass from k1/k2 model
        CASE
            WHEN r.tree_species IS NOT NULL THEN derived.calc_above_ground_biomass_regen(r.tree_species, xgr.bio_o_bhd, xgr.bio_o_hoe)
        END,
        -- volume_fao from k_VolBhdU7
        CASE
            WHEN r.tree_species IS NOT NULL
            AND xgr.mw_bhd < 70 THEN derived.k_vol_bhd_u7(
                derived.species_to_babwi(r.tree_species),
                xgr.mw_bhd::integer
            )
        END,
        false,
        now()
    FROM inventory_archive.regeneration r
        LEFT JOIN LATERAL derived.x_gr_lookup(r.tree_size_class) xgr ON true ON CONFLICT (regeneration_id) DO
    UPDATE
    SET intkey = EXCLUDED.intkey,
        dbh = EXCLUDED.dbh,
        trees_per_hectare = EXCLUDED.trees_per_hectare,
        basal_area = EXCLUDED.basal_area,
        below_ground_biomass = EXCLUDED.below_ground_biomass,
        above_ground_biomass = EXCLUDED.above_ground_biomass,
        volume_fao = EXCLUDED.volume_fao,
        needs_r_calculation = false,
        updated_at = now()
    RETURNING 1
)
SELECT count(*) INTO affected
FROM inserted;
RAISE NOTICE 'Backfilled % regeneration rows into derived.regeneration',
affected;
IF affected > 0 THEN PERFORM pg_notify(
    'derived_regeneration_changed',
    json_build_object('backfill', true, 'count', affected)::text
);
END IF;
RETURN affected;
END;
$$;