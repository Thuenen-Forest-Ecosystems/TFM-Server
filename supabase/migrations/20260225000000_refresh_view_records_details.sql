-- ============================================================================
-- FIX: Recreate view_records_details so SELECT r.* picks up columns added
-- after the original view creation (e.g. preliminary_set_at from
-- 20250312143829_fill_properties.sql).
--
-- In PostgreSQL, SELECT * in a view is expanded to an explicit column list
-- at CREATE time. Columns added to the underlying table afterwards are NOT
-- included until the view is recreated.
-- ============================================================================
DROP VIEW IF EXISTS public.view_records_details;
CREATE OR REPLACE VIEW public.view_records_details AS
SELECT r.*,
    -- plot_coordinates
    p_coordinates.center_location,
    -- bwi2022 plot attributes
    p_bwi.federal_state,
    p_bwi.growth_district,
    p_bwi.forest_status AS forest_status_bwi2022,
    p_bwi.accessibility,
    p_bwi.forest_office,
    p_bwi.ffh_forest_type_field,
    p_bwi.property_type,
    -- historical forest_status
    p_ci2017.forest_status AS forest_status_ci2017,
    p_ci2012.forest_status AS forest_status_ci2012,
    -- cluster attributes
    c.cluster_status,
    c.cluster_situation,
    c.state_responsible,
    c.states_affected,
    c.is_training AS cluster_is_training,
    c.grid_density
FROM public.records r
    LEFT JOIN inventory_archive.plot p_bwi ON r.plot_name = p_bwi.plot_name
    AND r.cluster_name = p_bwi.cluster_name
    AND p_bwi.interval_name = 'bwi2022'
    LEFT JOIN inventory_archive.plot_coordinates p_coordinates ON p_bwi.id = p_coordinates.plot_id
    LEFT JOIN inventory_archive.plot p_ci2017 ON p_bwi.plot_name = p_ci2017.plot_name
    AND p_bwi.cluster_name = p_ci2017.cluster_name
    AND p_ci2017.interval_name = 'ci2017'
    LEFT JOIN inventory_archive.plot p_ci2012 ON p_bwi.plot_name = p_ci2012.plot_name
    AND p_bwi.cluster_name = p_ci2012.cluster_name
    AND p_ci2012.interval_name = 'bwi2012'
    LEFT JOIN inventory_archive.cluster c ON r.cluster_name = c.cluster_name;
-- ============================================================================
-- PERMISSIONS (same as original)
-- ============================================================================
REVOKE ALL ON public.view_records_details
FROM PUBLIC;
REVOKE ALL ON public.view_records_details
FROM anon;
GRANT SELECT ON public.view_records_details TO authenticated;