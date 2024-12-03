SET search_path TO private_ci2027_001;
CREATE TABLE lookup_harvesting_method AS TABLE lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_harvesting_method ADD COLUMN abbreviation enum_harvesting_method UNIQUE NOT NULL;

--
-- PostgreSQL database dump
--

-- Dumped from database version 13.3 (Debian 13.3-1.pgdg110+1)
-- Dumped by pg_dump version 14.13 (Homebrew)


--
-- Data for Name: lookup_harvesting_method; Type: TABLE DATA; Schema: nfi2022; Owner: postgres
--

--INSERT INTO lookup_harvesting_method (abbreviation, name_de, name_en, sort, "interval") VALUES
--	('0', 'Für alle Holzernteverfahren geeignet', NULL, 0, '{bwi2012}'),
--	('1', 'Hochmechanisierte Verfahren nur mit Hang-Vollernter/Hang-Tragschlepper möglich', NULL, 10, '{bwi2012}'),
--	('2', 'Nicht für Harvester geeignet, jedoch kein Seilkrangelände', NULL, 20, '{bwi2012}'),
--	('3', 'Seilkran erforderlich', NULL, 30, '{bwi2012}'),
--	('4', 'Holzernte wegen erheblicher Erschwernisse unwahrscheinlich', NULL, 40, '{bwi2012}');


--
-- PostgreSQL database dump complete
--

