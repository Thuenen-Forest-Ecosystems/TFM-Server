SET search_path TO private_ci2027_001;
CREATE TABLE lookup_trees_less_4meter_layer AS TABLE lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_trees_less_4meter_layer ADD COLUMN abbreviation enum_trees_less_4meter_layer UNIQUE NOT NULL;

--
-- PostgreSQL database dump
--

-- Dumped from database version 13.3 (Debian 13.3-1.pgdg110+1)
-- Dumped by pg_dump version 14.13 (Homebrew)


--
-- Data for Name: lookup_trees_less_4meter_layer; Type: TABLE DATA; Schema: nfi2022; Owner: postgres
--

--INSERT INTO lookup_trees_less_4meter_layer (abbreviation, name_de, name_en, sort, "interval") VALUES
--	('1', 'Hauptbestockung', 'main stocking', 1, '{bwi2002,bwi2012}'),
--	('2', 'Verjüngung', 'regeneration', 2, '{bwi2002,bwi2012}'),
--	('3', 'Restbestockung', 'residual stocking', 3, '{bwi2002,bwi2012}'),
--	('9', 'im Kreis r=10m berücksichtigt', 'stocking layer surveyed in the sample plot 10 m radius', 9, '{bwi2002,bwi2012}');


--
-- PostgreSQL database dump complete
--

