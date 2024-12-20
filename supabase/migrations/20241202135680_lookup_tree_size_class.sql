SET search_path TO private_ci2027_001;
CREATE TABLE lookup_tree_size_class AS TABLE lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_tree_size_class ADD COLUMN id uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL;
ALTER TABLE lookup_tree_size_class ADD COLUMN abbreviation enum_tree_size_class UNIQUE NOT NULL;
--
-- PostgreSQL database dump
--

-- Dumped from database version 13.3 (Debian 13.3-1.pgdg110+1)
-- Dumped by pg_dump version 14.13 (Homebrew)


--
-- Data for Name: lookup_tree_size_class; Type: TABLE DATA; Schema: nfi2022; Owner: postgres
--

--INSERT INTO lookup_tree_size_class (abbreviation, name_de, name_en, sort, "interval") VALUES
--	('0', '20 bis < 50 cm Höhe', '20 to < 50 cm high', 1010, '{bwi2002,bwi2012}'),
--	('1', '>=50 bis 130 cm Höhe', '>=50 to 130 cm high', 1011, '{bwi2002,bwi2012}'),
--	('2', '> 130 cm Höhe und bis 4,9 cm BHD', '> 130 cm high and dbh up to 4,9 cm', 2000, '{bwi2002,bwi2012}'),
--	('5', '>=5,0 bis 5,9 cm BHD', '>=5,0 to 5,9 cm dbh', 2001, '{bwi2002,bwi2012}'),
--	('6', '>=6,0 bis 6,9 cm BHD', '>=6,0 to 6,9 cm dbh', 2002, '{bwi2002,bwi2012}'),
--	('9', '> 130 cm Höhe und BHD kleiner 7 cm (im Nebenbestand)', '> 130 cm high and with less than 7 cm dbh (in the secondary stand)', 2003, '{bwi2002,bwi2012}');


--
-- PostgreSQL database dump complete
--;
