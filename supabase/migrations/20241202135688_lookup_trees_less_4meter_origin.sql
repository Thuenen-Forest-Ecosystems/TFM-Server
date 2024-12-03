SET search_path TO private_ci2027_001;
CREATE TABLE lookup_trees_less_4meter_origin AS TABLE lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_trees_less_4meter_origin ADD COLUMN abbreviation enum_trees_less_4meter_origin UNIQUE NOT NULL;

--
-- PostgreSQL database dump
--

-- Dumped from database version 13.3 (Debian 13.3-1.pgdg110+1)
-- Dumped by pg_dump version 14.13 (Homebrew)


--
-- Data for Name: lookup_trees_less_4meter_origin; Type: TABLE DATA; Schema: nfi2022; Owner: postgres
--

--INSERT INTO lookup_trees_less_4meter_origin (abbreviation, name_de, name_en, sort, "interval") VALUES
--	('1', 'Naturverjüngung', 'natural regeneration', 10, '{bwi2002,bwi2012}'),
--	('2', 'Saat', 'sowing', 20, '{bwi2002,bwi2012}'),
--	('3', 'Pflanzung', 'planting', 30, '{bwi2002,bwi2012}'),
--	('4', 'Stockausschlag', 'coppice shoot', 40, '{bwi2002,bwi2012}'),
--	('5', 'nicht zuzuordnen', 'classification not possible', 50, '{bwi2002,bwi2012}');


--
-- PostgreSQL database dump complete
--

