-- Set search path to include public schema
SET search_path TO public, inventory_archive;

-- Create the radians function if it doesn't exist
CREATE OR REPLACE FUNCTION radians(degrees float8)
RETURNS float8 AS $$
BEGIN
  RETURN degrees * pi() / 180.0;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

-- Create the radians_from_gon function
CREATE OR REPLACE FUNCTION radians_from_gon(gon float8)
RETURNS float8 AS $$
BEGIN
  RETURN gon * pi() / 200.0;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION create_linestring_from_edges(edges JSONB, start_point public.geometry)
RETURNS public.geometry AS $$
DECLARE
    point_array public.geometry[];
    current_point public.geometry;
    azimuth_rad float8;
    distance_cm float8;
    distance_m float8;
    i integer;
    azimuth_gon numeric;
BEGIN
    current_point := start_point; -- Start point is already in the correct SRID

    --point_array := ARRAY[current_point];

    FOR i IN 0..(jsonb_array_length(edges) - 1) LOOP
        azimuth_gon := ((edges->>i)::jsonb->>'azimuth')::numeric;
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

CREATE OR REPLACE FUNCTION update_geom_column()
RETURNS TRIGGER AS $$
DECLARE
  start_point public.geometry;
BEGIN
    SELECT position_mean INTO start_point
    FROM inventory_archive.position
    WHERE plot_id = NEW.plot_id;

    IF start_point IS NULL THEN
        RAISE NOTICE 'No start point found for plot_id: %', NEW.plot_id;
        RETURN NEW;
    END IF;

    -- Start point is ALREADY in WGS84 (EPSG:4326)
    NEW.geometry_edges := create_linestring_from_edges(NEW.edges, start_point);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_geom_trigger ON inventory_archive.edges;

CREATE TRIGGER update_geom_trigger
BEFORE UPDATE OR INSERT ON inventory_archive.edges
FOR EACH ROW
EXECUTE PROCEDURE update_geom_column();




-- UPDATE CICLE --

CREATE OR REPLACE FUNCTION update_circle_geometry()
RETURNS TRIGGER AS $$
DECLARE
    start_point public.geometry;
    azimuth_rad float8;
    new_center_point public.geometry;
    distance_m float8;
BEGIN
    SELECT center_location::public.geometry INTO start_point
    FROM inventory_archive.plot_coordinates
    WHERE id = NEW.plot_coordinates_id;

    IF start_point IS NULL THEN
        RAISE NOTICE 'No start point found for plot_coordinates_id: %', NEW.plot_coordinates_id;
        RETURN NEW;
    END IF;

    -- Calculate in WGS84
    azimuth_rad := radians_from_gon(CAST(NEW.azimuth AS float8));
    distance_m := NEW.distance / 100.0;  -- Convert cm to m
    
    -- Use ST_Project which handles geodetic calculations
    new_center_point := ST_Project(start_point, distance_m, azimuth_rad);
    
    -- Create buffer using geography type for true circular shape
    NEW.center_location := ST_Buffer(new_center_point::geography, NEW.radius)::public.geometry;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_subplot_trigger ON inventory_archive.subplots_relative_position;

CREATE TRIGGER update_subplot_trigger
BEFORE UPDATE OR INSERT ON inventory_archive.subplots_relative_position
FOR EACH ROW
EXECUTE FUNCTION update_circle_geometry();