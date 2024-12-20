SET search_path TO private_ci2027_001;
CREATE TABLE lookup_grid_density AS TABLE lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_grid_density ADD COLUMN id uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL;
ALTER TABLE lookup_grid_density ADD COLUMN abbreviation enum_grid_density UNIQUE NOT NULL;
--
-- PostgreSQL database dump
--

-- Dumped from database version 13.3 (Debian 13.3-1.pgdg110+1)
-- Dumped by pg_dump version 14.13 (Homebrew)


--
-- Data for Name: lookup_grid_density; Type: TABLE DATA; Schema: nfi2022; Owner: postgres
--

--INSERT INTO lookup_grid_density (abbreviation, name_de, name_en, sort, "interval") VALUES
--	('0', 'unsystematisch, Schulungs- oder Demonstration-Trakt', 'unsystematisch, Schulungs- oder Demonstration-Trakt', NULL, '{bwi2002,bwi2012}'),
--	('1', '1 < = 1 km x 1 km - Raster', '1 < = 1 km x 1 km - Raster', NULL, '{bwi2002,bwi2012}'),
--	('4', '4 = 2 km x 2 km - Raster,           trifft auch 8er- und 16er-Netz', '4 = 2 km x 2 km - grit', NULL, '{bwi2002,bwi2012}'),
--	('8', '8 = 2,83 kmx2,83 km - Raster,    trifft auch 16er-Netz', '8 = 2,83 kmx2,83 km - grit', NULL, '{bwi2002,bwi2012}'),
--	('16', '16 = 4 km x 4 km - Raster', '16 = 4km x 4 km - grit', NULL, '{bwi2002,bwi2012}'),
--	('90', 'Ökologische Waldzustandskontrolle ÖWK', 'Ökologische Waldzustandskontrolle ÖWK', NULL, '{bwi2002,bwi2012}');


--
-- PostgreSQL database dump complete
--;
