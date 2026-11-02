--------------------------------------------------------------------------------
-- FUNCTION: add_diameter_to_previous
--------------------------------------------------------------------------------
-- Finds every tree object inside records.previous_properties where
--   • dbh is JSON null
--   • tree_status is 4,5,9 or 12
--   • the plot belongs to a real cluster (cluster_name < 9999900)
-- Then it fetches the most recent dbh for that tree from the historic
-- inventory_archive tables and writes the value back into the JSON document.
--
-- p_dry_run = true   → only count / report, no UPDATE
-- p_dry_run = false  → perform the UPDATE
--
-- Returns the number of *tree objects* that received a new dbh.
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.add_diameter_to_previous(p_dry_run boolean DEFAULT false) RETURNS integer LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public,
    pg_catalog AS $$
DECLARE v_updated_cnt integer;
-- number of tree objects that will / were updated
rec RECORD;
-- loop variable
BEGIN -------------------------------------------------------------------------
-- 1️⃣  Build the set of trees that need a DBH and the value that should be
--     written.  The result is materialised in a temporary table so we can
--     reuse it for the dry‑run count and for the real update.
-------------------------------------------------------------------------
CREATE TEMP TABLE tmp_to_fix ON COMMIT DROP AS WITH -----------------------------------------------------------------
-- a)  Trees whose DBH is JSON null and have an eligible status
-----------------------------------------------------------------
missing_dbh AS (
    SELECT r.id AS record_id,
        -- PK of public.records
        r.cluster_name,
        r.plot_name,
        (t_elem->>'tree_number')::int AS tree_number,
        t_elem->>'id' AS tree_id,
        (t_elem->>'tree_status')::int AS tree_status,
        t_ord - 1 AS elem_idx -- 0‑based array index
    FROM public.records r
        CROSS JOIN LATERAL jsonb_array_elements(r.previous_properties->'tree') WITH ORDINALITY AS ta(t_elem, t_ord)
    WHERE t_elem->'dbh' = 'null' -- JSON null
        AND (t_elem->>'tree_status')::int IN (4, 5, 9, 12)
        AND r.cluster_name < 9999900 -- exclude test clusters
),
-----------------------------------------------------------------
-- b)  The most recent non‑null DBH for every (cluster,plot,tree_number)
-----------------------------------------------------------------
latest_dbh AS (
    SELECT p.cluster_name,
        p.plot_name,
        t.tree_number,
        t.dbh,
        p.acquisition_date,
        ROW_NUMBER() OVER (
            PARTITION BY p.cluster_name,
            p.plot_name,
            t.tree_number
            ORDER BY p.acquisition_date DESC
        ) AS rn
    FROM inventory_archive.plot p
        JOIN inventory_archive.tree t ON p.id = t.plot_id
    WHERE t.dbh IS NOT NULL
),
-----------------------------------------------------------------
-- c)  Join the two, keep only the newest measurement (rn = 1)
-----------------------------------------------------------------
to_fix AS (
    SELECT m.record_id,
        m.elem_idx,
        l.dbh AS new_dbh
    FROM missing_dbh m
        JOIN latest_dbh l ON m.cluster_name = l.cluster_name
        AND m.plot_name = l.plot_name
        AND m.tree_number = l.tree_number
    WHERE l.rn = 1 -- most recent measurement only
)
SELECT *
FROM to_fix;
-- materialise the rows in the temp table
-------------------------------------------------------------------------
-- 2️⃣  How many tree objects would be fixed?
-------------------------------------------------------------------------
SELECT COUNT(*) INTO v_updated_cnt
FROM tmp_to_fix;
IF v_updated_cnt = 0 THEN -- nothing to do
RETURN 0;
END IF;
-------------------------------------------------------------------------
-- 3️⃣  Dry‑run?  Just return the count, no UPDATE executed.
-------------------------------------------------------------------------
IF p_dry_run THEN RETURN v_updated_cnt;
END IF;
-------------------------------------------------------------------------
-- 4️⃣  Real update – **loop** over every row in tmp_to_fix.
--      One UPDATE per tree guarantees that all elements are written,
--      even when a record contains many trees that need fixing.
-------------------------------------------------------------------------
FOR rec IN
SELECT record_id,
    elem_idx,
    new_dbh
FROM tmp_to_fix LOOP
UPDATE public.records r
SET previous_properties = jsonb_set(
        r.previous_properties,
        ARRAY ['tree', rec.elem_idx::text, 'dbh'],
        to_jsonb(rec.new_dbh),
        true -- createMissing = true (safety)
    )
WHERE r.id = rec.record_id;
END LOOP;
-------------------------------------------------------------------------
-- 5️⃣  Return the number of tree objects that were actually updated.
-------------------------------------------------------------------------
RETURN v_updated_cnt;
-- we already counted the rows we processed
END;
$$;
--------------------------------------------------------------------------------
-- Re‑grant the function (adjust to your security model if needed)
--------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.add_diameter_to_previous(boolean)
FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.add_diameter_to_previous(boolean) TO PUBLIC;
--------------------------------------------------------------------------------