-- Set search path to include public schema
SET search_path TO public,
    inventory_archive;
-- Create the radians function if it doesn't exist
CREATE OR REPLACE FUNCTION radians(degrees float8) RETURNS float8 AS $$ BEGIN RETURN degrees * pi() / 180.0;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
-- Create the radians_from_gon function
CREATE OR REPLACE FUNCTION radians_from_gon(gon float8) RETURNS float8 AS $$ BEGIN RETURN gon * pi() / 200.0;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION create_linestring_from_edges(edges JSONB, start_point extensions.geometry) RETURNS extensions.geometry AS $$
DECLARE point_array extensions.geometry [];
current_point extensions.geometry;
azimuth_rad float8;
distance_cm float8;
distance_m float8;
i integer;
azimuth_gon numeric;
BEGIN current_point := start_point;
-- Start point is already in the correct SRID
--point_array := ARRAY[current_point];
FOR i IN 0..(jsonb_array_length(edges) - 1) LOOP azimuth_gon := ((edges->>i)::jsonb->>'azimuth')::numeric;
azimuth_rad := radians_from_gon(azimuth_gon::float8);
distance_cm := ((edges->>i)::jsonb->>'distance')::float8;
distance_m := distance_cm / 100.0;
-- Calculate in the correct SRID (WGS84)
current_point := ST_Project(current_point, distance_m, azimuth_rad);
--current_point := ST_Translate(current_point,
--                              distance_m * sin(azimuth_rad),
--                              distance_m * cos(azimuth_rad));
point_array := point_array || current_point;
END LOOP;
RETURN ST_Transform(ST_MakeLine(point_array), 4326);
--RETURN ST_MakeLine(point_array); -- No need for ST_SetSRID; it's already in WGS84
END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION update_geom_column() RETURNS TRIGGER AS $$
DECLARE start_point extensions.geometry;
BEGIN
SELECT position_mean INTO start_point
FROM inventory_archive.position
WHERE plot_id = NEW.plot_id;
IF start_point IS NULL THEN RAISE NOTICE 'No start point found for plot_id: %',
NEW.plot_id;
RETURN NEW;
END IF;
-- Start point is ALREADY in WGS84 (EPSG:4326)
NEW.geometry_edges := create_linestring_from_edges(NEW.edges, start_point);
RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- Deprecated: This trigger is not needed anymore as we handle geometry updates in the update_edges_coordinates function.
DROP TRIGGER IF EXISTS update_geom_trigger ON inventory_archive.edges;
--CREATE TRIGGER update_geom_trigger
--BEFORE UPDATE OR INSERT ON inventory_archive.edges
--FOR EACH ROW
--EXECUTE PROCEDURE update_geom_column();
-- EDGET_COORDINATES TRIGGER --
CREATE OR REPLACE FUNCTION inventory_archive.update_edges_coordinates() RETURNS TRIGGER AS $$
DECLARE start_point extensions.geometry;
new_geometry extensions.geometry;
BEGIN -- Get the start point from the position table
SELECT position_mean INTO start_point
FROM inventory_archive.position
WHERE plot_id = NEW.plot_id;
IF start_point IS NULL THEN RAISE NOTICE 'No start point found for plot_id: %',
NEW.plot_id;
RETURN NEW;
END IF;
-- Calculate the new geometry using the edges data
new_geometry := create_linestring_from_edges(NEW.edges, start_point);
-- Insert or update the geometry in the edges_coordinates table
INSERT INTO inventory_archive.edges_coordinates (edge_id, geometry_edges)
VALUES (NEW.id, new_geometry) ON CONFLICT (edge_id) DO
UPDATE
SET geometry_edges = EXCLUDED.geometry_edges;
RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS update_edges_coordinates_trigger ON inventory_archive.edges;
CREATE TRIGGER update_edges_coordinates_trigger
AFTER
INSERT
    OR
UPDATE ON inventory_archive.edges FOR EACH ROW EXECUTE FUNCTION inventory_archive.update_edges_coordinates();
-- UPDATE CICLE --
CREATE OR REPLACE FUNCTION update_circle_geometry() RETURNS TRIGGER AS $$
DECLARE start_point extensions.geometry;
azimuth_rad float8;
new_center_point extensions.geometry;
distance_m float8;
BEGIN
SELECT center_location::extensions.geometry INTO start_point
FROM inventory_archive.plot_coordinates
WHERE id = NEW.plot_coordinates_id;
IF start_point IS NULL THEN RAISE NOTICE 'No start point found for plot_coordinates_id: %',
NEW.plot_coordinates_id;
RETURN NEW;
END IF;
-- Calculate in WGS84
azimuth_rad := radians_from_gon(CAST(NEW.azimuth AS float8));
distance_m := NEW.distance / 100.0;
-- Convert cm to m
-- Use ST_Project which handles geodetic calculations
new_center_point := ST_Project(start_point, distance_m, azimuth_rad);
-- Remove the unnecessary line
-- NEW.radius := NEW.radius; 
-- Ensure the record exists in subplots_relative_position before inserting
IF EXISTS (
    SELECT 1
    FROM inventory_archive.subplots_relative_position
    WHERE id = NEW.id
) THEN -- Insert or update geometry in subplots_relative_position_coordinates table
INSERT INTO inventory_archive.subplots_relative_position_coordinates (
        intkey,
        subplots_relative_position_id,
        geometry_subplots_relative_position
    )
VALUES (
        NEW.intkey,
        NEW.id,
        ST_Buffer(new_center_point::geography, NEW.radius)::extensions.geometry
    ) ON CONFLICT (subplots_relative_position_id) DO
UPDATE
SET geometry_subplots_relative_position = EXCLUDED.geometry_subplots_relative_position;
ELSE RAISE NOTICE 'subplots_relative_position record with id % does not exist',
NEW.id;
END IF;
RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS update_subplot_trigger ON inventory_archive.subplots_relative_position;
CREATE TRIGGER update_subplot_trigger
AFTER
INSERT
    OR
UPDATE ON inventory_archive.subplots_relative_position FOR EACH ROW EXECUTE FUNCTION update_circle_geometry();
-- UPDATE TREE_LOCATION ON TREE UPDATE OR INSERT --
CREATE OR REPLACE FUNCTION inventory_archive.update_tree_location() RETURNS TRIGGER AS $$
DECLARE start_point extensions.geometry;
azimuth_rad float8;
new_center_point extensions.geometry;
distance_m float8;
BEGIN RAISE NOTICE 'plot_id: %',
NEW."plot_id";
SELECT center_location::extensions.geometry INTO start_point
FROM inventory_archive.plot_coordinates
WHERE plot_id = NEW."plot_id";
IF start_point IS NULL THEN RAISE NOTICE 'No start point found for plot_coordinates_id: %',
NEW."plot_id";
RETURN NEW;
END IF;
-- Calculate in WGS84
azimuth_rad := radians_from_gon(CAST(NEW.azimuth AS float8));
distance_m := NEW.distance / 100.0;
-- Convert cm to m
-- Use ST_Project which handles geodetic calculations
new_center_point := ST_Project(start_point, distance_m, azimuth_rad);
INSERT INTO inventory_archive.tree_coordinates (tree_id, tree_location)
VALUES (NEW.id, new_center_point) ON CONFLICT (tree_id) DO
UPDATE
SET tree_location = EXCLUDED.tree_location;
RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS update_tree_location_trigger ON inventory_archive.tree;
CREATE TRIGGER update_tree_location_trigger
AFTER
UPDATE
    OR
INSERT ON inventory_archive.tree FOR EACH ROW EXECUTE FUNCTION inventory_archive.update_tree_location();