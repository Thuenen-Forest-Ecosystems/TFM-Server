SET search_path TO private_ci2027_001;
CREATE TABLE lookup_management_type AS TABLE lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_management_type ADD COLUMN id uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL;
ALTER TABLE lookup_management_type ADD COLUMN abbreviation enum_management_type UNIQUE NOT NULL;
--
-- PostgreSQL database dump
--

-- Dumped from database version 13.3 (Debian 13.3-1.pgdg110+1)
-- Dumped by pg_dump version 14.13 (Homebrew)


--
-- Data for Name: lookup_management_type; Type: TABLE DATA; Schema: nfi2022; Owner: postgres
--

--INSERT INTO lookup_management_type (abbreviation, name_de, name_en, sort, "interval") VALUES
--	('1', 'schlagweiser Hochwald', 'age class high forest', 11, '{bwi1992,bwi2002,bwi2012}'),
--	('2', 'Plenterwald', 'plenter forest', 21, '{bwi1992,bwi2002,bwi2012}'),
--	('3', 'Mittelwald', 'composite forest', 31, '{bwi1992,bwi2002,bwi2012}'),
--	('4', 'Niederwald', 'coppice forest', 41, '{bwi1992,bwi2002,bwi2012}'),
--	('5', 'Kurzumtriebsplantage', 'short rotation forest', 51, '{bwi1992,bwi2002,bwi2012}'),
--	('6', 'Latschen- oder Grünerlenfeld', '???', 61, '{bwi1992,bwi2002,bwi2012}');


--
-- PostgreSQL database dump complete
--;
