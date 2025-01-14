SET search_path TO private_ci2027_001;
CREATE TABLE lookup_trees_less_4meter_count_factor AS TABLE lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_trees_less_4meter_count_factor ADD COLUMN id uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL;
ALTER TABLE lookup_trees_less_4meter_count_factor ADD COLUMN abbreviation enum_trees_less_4meter_count_factor UNIQUE NOT NULL;
--
-- PostgreSQL database dump
--

-- Dumped from database version 13.3 (Debian 13.3-1.pgdg110+1)
-- Dumped by pg_dump version 14.13 (Homebrew)


--
-- Data for Name: lookup_trees_less_4meter_count_factor; Type: TABLE DATA; Schema: nfi2022; Owner: postgres
--

--INSERT INTO lookup_trees_less_4meter_count_factor (abbreviation, name_de, name_en, sort, "interval") VALUES
--	('1', 'Zählfaktor 1 ( wenn Anz. Bäume in WZP/ZF4 <=10)', 'basal area factor 1 ( when number of trees in the angle count sample / basal area factor 4 <= 10)', NULL, '{bwi2002,bwi2012}'),
--	('2', 'Zählfaktor 2 ( wenn Anz. Bäume in WZP/ZF4 >10)', 'basal area factor 2 ( when number of trees in the angle count sample / basal area factor 4 > 10)', NULL, '{bwi2002,bwi2012}');


--
-- PostgreSQL database dump complete
--;
