-- -----------------------------------------------------------------------
-- add_cluster_with_plots
--
-- Creates a cluster (upserting on cluster_name conflict) and
-- automatically generates all 4 plot corners as a 150 m × 150 m square.
--
-- Corner layout (BWI convention, Enr / plot_name):
--   1 = SW (given lon/lat input)
--   2 = NW  (+150 m North)
--   3 = NE  (+150 m North, +150 m East)
--   4 = SE  (+150 m East)
--
-- Coordinates are computed in DHDN (EPSG:31466-69) — the same
-- projection originally used by the BWI (X_ETRS_IAEA / Y_ETRS_IAEA) — then
-- projected back to WGS84 (EPSG:4326) for center_location.
-- cartesian_x = Easting (EPSG:31466-69), cartesian_y = Northing (EPSG:34166-69).
--
-- Returns one row per plot (4 rows total).
-- Restricted to the postgres role only.
-- -----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION inventory_archive.add_cluster_with_plots(
        -- required: bottom-left (SW) corner of the cluster square in WGS84
        p_cluster_name INTEGER,
        p_federal_state INTEGER,
        p_longitude FLOAT,
        -- SW corner longitude  (EPSG:4326)
        p_latitude FLOAT,
        -- SW corner latitude   (EPSG:4326)
        -- optional cluster params
        p_state_responsible INTEGER DEFAULT NULL,
        p_topo_map_sheet INTEGER DEFAULT NULL,
        p_states_affected INTEGER [] DEFAULT NULL,
        p_grid_density INTEGER DEFAULT NULL,
        p_cluster_status INTEGER DEFAULT NULL,
        p_cluster_situation INTEGER DEFAULT NULL,
        p_inspire_grid_cell TEXT DEFAULT NULL,
        p_is_training BOOLEAN DEFAULT TRUE,
        -- optional plot params
        p_interval_name TEXT DEFAULT 'ci2027',
        p_acquisition_date DATE DEFAULT NULL,
        -- side length of the square in metres (default 150 m)
        p_side_m FLOAT DEFAULT 150.0
    ) RETURNS TABLE (
        out_cluster_id UUID,
        out_plot_id UUID,
        out_plot_name INTEGER,
        out_plot_coordinates_id UUID,
        out_cartesian_x FLOAT,
        out_cartesian_y FLOAT,
        out_longitude FLOAT,
        out_latitude FLOAT
    ) LANGUAGE plpgsql SECURITY INVOKER
SET search_path = inventory_archive,
    extensions,
    public AS $$
DECLARE v_cluster_id UUID;
v_plot_id UUID;
v_coord_id UUID;
-- DHDN (EPSG:31466, 31467, 31468, 31469, depending on longitude) representation of the SW corner
v_sw_dhdn extensions.GEOMETRY;
v_sw_x FLOAT;
-- Easting  DHDN
v_sw_y FLOAT;
-- Northing DHDN
-- per-corner variables
v_corner RECORD;
v_pt_dhdn extensions.GEOMETRY;
v_pt_4326 extensions.GEOMETRY;
v_cx FLOAT;
v_cy FLOAT;
BEGIN -- ----------------------------------------------------------------
-- 1. Upsert cluster
-- ----------------------------------------------------------------
INSERT INTO inventory_archive.cluster (
        cluster_name,
        state_responsible,
        topo_map_sheet,
        states_affected,
        grid_density,
        cluster_status,
        cluster_situation,
        inspire_grid_cell,
        is_training
    )
VALUES (
        p_cluster_name,
        p_state_responsible,
        p_topo_map_sheet,
        p_states_affected,
        p_grid_density,
        p_cluster_status,
        p_cluster_situation,
        p_inspire_grid_cell,
        p_is_training
    ) ON CONFLICT (cluster_name) DO
UPDATE
SET state_responsible = COALESCE(
        EXCLUDED.state_responsible,
        inventory_archive.cluster.state_responsible
    ),
    topo_map_sheet = COALESCE(
        EXCLUDED.topo_map_sheet,
        inventory_archive.cluster.topo_map_sheet
    ),
    states_affected = COALESCE(
        EXCLUDED.states_affected,
        inventory_archive.cluster.states_affected
    ),
    grid_density = COALESCE(
        EXCLUDED.grid_density,
        inventory_archive.cluster.grid_density
    ),
    cluster_status = COALESCE(
        EXCLUDED.cluster_status,
        inventory_archive.cluster.cluster_status
    ),
    cluster_situation = COALESCE(
        EXCLUDED.cluster_situation,
        inventory_archive.cluster.cluster_situation
    ),
    inspire_grid_cell = COALESCE(
        EXCLUDED.inspire_grid_cell,
        inventory_archive.cluster.inspire_grid_cell
    ),
    is_training = EXCLUDED.is_training
RETURNING id INTO v_cluster_id;
-- ----------------------------------------------------------------
-- 2. Project SW corner from WGS84 → DHDN (EPSG:31466-69)
-- ----------------------------------------------------------------
v_sw_dhdn := CASE WHEN p_longitude < 7.51 THEN ST_Transform(ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326), 31466)
    		      WHEN p_longitude >= 7.51 AND p_longitude < 10.51 THEN ST_Transform(ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326), 31467)
				  WHEN p_longitude >= 10.51 AND p_longitude < 13.51 THEN ST_Transform(ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326), 31468)
				  WHEN p_longitude >= 13.51 THEN ST_Transform(ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326), 31469)            
	       END;
v_sw_x := ST_X(v_sw_dhdn);
v_sw_y := ST_Y(v_sw_dhdn);
-- ----------------------------------------------------------------
-- 3. Insert each of the 4 corners
--
    --   plot_name 1 = SW  (origin)
--   plot_name 2 = NW  (+ N)
--   plot_name 3 = NE  (+ N + E)
--   plot_name 4 = SE  (+ E)
-- ----------------------------------------------------------------
FOR v_corner IN
SELECT *
FROM (
        VALUES (1, 0.0, 0.0),
            -- SW
            (2, 0.0, p_side_m),
            -- NW
            (3, p_side_m, p_side_m),
            -- NE
            (4, p_side_m, 0.0) -- SE
    ) AS t(plot_num, dx, dy) LOOP -- Offset in EPSG:31466-69 (metric CRS — 1 unit = 1 m)
    v_cx := v_sw_x + v_corner.dx;
v_cy := v_sw_y + v_corner.dy;
v_pt_dhdn := CASE WHEN p_longitude < 7.51 THEN ST_SetSRID(ST_MakePoint(v_cx, v_cy), 31466)
    		      WHEN p_longitude >= 7.51 AND p_longitude < 10.51 THEN ST_SetSRID(ST_MakePoint(v_cx, v_cy), 31467)
				  WHEN p_longitude >= 10.51 AND p_longitude < 13.51 THEN ST_SetSRID(ST_MakePoint(v_cx, v_cy), 31468)
				  WHEN p_longitude >= 13.51 THEN ST_SetSRID(ST_MakePoint(v_cx, v_cy), 31469)
				END;
-- Project back to WGS84 for center_location
v_pt_4326 := ST_Transform(v_pt_dhdn, 4326);
-- Insert plot
INSERT INTO inventory_archive.plot (
        cluster_id,
        cluster_name,
        plot_name,
        federal_state,
        interval_name,
        acquisition_date
    )
VALUES (
        v_cluster_id,
        p_cluster_name,
        v_corner.plot_num,
        p_federal_state,
        p_interval_name,
        p_acquisition_date
    )
RETURNING id INTO v_plot_id;
-- Insert plot_coordinates
INSERT INTO inventory_archive.plot_coordinates (
        plot_id,
        center_location,
        cartesian_x,
        cartesian_y
    )
VALUES (
        v_plot_id,
        v_pt_4326,
        v_cx,
        v_cy
    )
RETURNING id INTO v_coord_id;
-- Emit result row
out_cluster_id := v_cluster_id;
out_plot_id := v_plot_id;
out_plot_name := v_corner.plot_num;
out_plot_coordinates_id := v_coord_id;
out_cartesian_x := v_cx;
out_cartesian_y := v_cy;
out_longitude := ST_X(v_pt_4326);
out_latitude := ST_Y(v_pt_4326);
RETURN NEXT;
END LOOP;
END;
$$;
COMMENT ON FUNCTION inventory_archive.add_cluster_with_plots IS 'Upserts a cluster and inserts all 4 plot corners as a square of p_side_m metres (default 150 m). p_longitude/p_latitude define the SW (bottom-left) corner in WGS84. cartesian_x/y are stored in DHDN (EPSG:31466-69). Returns one row per plot with coordinates. Callable by postgres only.';
-- Restrict to postgres only
REVOKE ALL ON FUNCTION inventory_archive.add_cluster_with_plots
FROM PUBLIC;
GRANT EXECUTE ON FUNCTION inventory_archive.add_cluster_with_plots TO postgres;
-- -----------------------------------------------------------------------
-- delete_cluster
-- Deletes a cluster by cluster_name. All dependent plots, plot_coordinates,
-- and other cascade-linked rows are removed automatically via FK ON DELETE CASCADE.
-- Restricted to the postgres role only.
-- -----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION inventory_archive.delete_cluster(p_cluster_name INTEGER) RETURNS VOID LANGUAGE plpgsql SECURITY INVOKER
SET search_path = inventory_archive AS $$ BEGIN
DELETE FROM inventory_archive.cluster
WHERE cluster_name = p_cluster_name;
IF NOT FOUND THEN RAISE EXCEPTION 'Cluster with cluster_name % does not exist.',
p_cluster_name;
END IF;
END;
$$;
COMMENT ON FUNCTION inventory_archive.delete_cluster IS 'Deletes a cluster by cluster_name. Cascades to all dependent plots, plot_coordinates, trees, etc. Raises an exception if the cluster does not exist. Callable by postgres only.';
-- Restrict to postgres only
REVOKE ALL ON FUNCTION inventory_archive.delete_cluster
FROM PUBLIC;
GRANT EXECUTE ON FUNCTION inventory_archive.delete_cluster TO postgres;
