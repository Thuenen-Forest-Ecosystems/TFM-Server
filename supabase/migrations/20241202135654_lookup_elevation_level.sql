SET search_path TO private_ci2027_001;
CREATE TABLE lookup_elevation_level AS TABLE lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_elevation_level ADD COLUMN id uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL;
ALTER TABLE lookup_elevation_level ADD COLUMN abbreviation enum_elevation_level UNIQUE NOT NULL;
--
-- PostgreSQL database dump
--

-- Dumped from database version 13.3 (Debian 13.3-1.pgdg110+1)
-- Dumped by pg_dump version 14.13 (Homebrew)


--
-- Data for Name: lookup_elevation_level; Type: TABLE DATA; Schema: nfi2022; Owner: postgres
--

--INSERT INTO lookup_elevation_level (abbreviation, name_de, name_en, sort, "interval") VALUES
--	('1', 'planar', 'planar', NULL, '{bwi2002,bwi2012}'),
--	('2', 'kollin', 'colline', NULL, '{bwi2002,bwi2012}'),
--	('3', 'submontan', 'submontane', NULL, '{bwi2002,bwi2012}'),
--	('4', 'montan', 'montane', NULL, '{bwi2002,bwi2012}'),
--	('5', 'hochmontan/subalpin', 'high-montane/sub-alpine', NULL, '{bwi2002,bwi2012}');


--
-- PostgreSQL database dump complete
--;
