SET search_path TO private_ci2027_001;
CREATE TABLE lookup_forest_status AS TABLE lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_forest_status ADD COLUMN abbreviation enum_forest_status UNIQUE NOT NULL;

--
-- PostgreSQL database dump
--

-- Dumped from database version 13.3 (Debian 13.3-1.pgdg110+1)
-- Dumped by pg_dump version 14.13 (Homebrew)


--
-- Data for Name: lookup_forest_status; Type: TABLE DATA; Schema: nfi2022; Owner: postgres
--

--INSERT INTO lookup_forest_status (abbreviation, name_de, name_en, sort, "interval") VALUES
--	('0', 'Nichtwald       (Stand Referenztabellen 17.09.2020 14:09)', 'non forest', 10001, '{bwi1992,bwi2002,bwi2012}'),
--	('1', 'produktiver Wald, Holzboden', 'productive forest, forest land', 2002, '{bwi1992,bwi2002,bwi2012}'),
--	('2', 'unproduktiver Wald, Holzboden', 'non productive forest, forest land', 2002, '{bwi1992,bwi2002,bwi2012}'),
--	('3', 'Wald, Blöße', 'forest, temporary unstocked area', 2001, '{bwi1992,bwi2002,bwi2012}'),
--	('4', 'Wald, Nichtholzboden', 'forest, unstocked forest land', 4001, '{bwi1992,bwi2002,bwi2012}'),
--	('5', 'Wald, bestockter Holzboden', '', 1001, '{bwi1992,bwi2002,bwi2012}'),
--	('8', 'nicht relevant, weil außerhalb des Inventurgebietes', NULL, 8001, '{bwi2002,bwi2012}'),
--	('9', 'nicht relevant, weil nicht zum Verdichtungsgebiet / Raster gehörig', NULL, 9001, '{bwi2002,bwi2012}'),
--	('23', 'Wald, Blöße, nicht im terrestrischen Inventurnetz', 'forest,temporary unstocked area, not assessed', 11001, '{bwi1992,bwi2002,bwi2012}'),
--	('24', 'Nichtholzboden, nicht im terrestrischen Inventurnetz', 'forest,unstocked forest land, not assessed', 11001, '{bwi1992,bwi2002,bwi2012}'),
--	('25', 'bestockter Holzboden, nicht im terrestrischen Inventurnetz', 'forest, stocked area, not assessed', 11001, '{bwi1992,bwi2002,bwi2012}');


--
-- PostgreSQL database dump complete
--

