SET search_path TO private_ci2027_001;
CREATE TABLE lookup_tree_species_group AS TABLE lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_tree_species_group ADD COLUMN id uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL;
ALTER TABLE lookup_tree_species_group ADD COLUMN abbreviation enum_tree_species_group UNIQUE NOT NULL;
--
-- PostgreSQL database dump
--

-- Dumped from database version 13.3 (Debian 13.3-1.pgdg110+1)
-- Dumped by pg_dump version 14.13 (Homebrew)


--
-- Data for Name: lookup_tree_species_group; Type: TABLE DATA; Schema: nfi2022; Owner: postgres
--

--INSERT INTO lookup_tree_species_group (abbreviation, name_de, name_en, sort, "interval") VALUES
--	('1', 'Nadelbäume', 'coniferous trees', NULL, '{bwi2002,bwi2012}'),
--	('2', 'Laubbäume ohne Eiche', 'deciduous trees without oak', NULL, '{bwi2002,bwi2012}'),
--	('3', 'Eiche', 'oak', NULL, '{bwi2002,bwi2012}');


--
-- PostgreSQL database dump complete
--;
