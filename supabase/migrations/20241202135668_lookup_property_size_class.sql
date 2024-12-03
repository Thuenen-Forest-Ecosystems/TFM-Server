SET search_path TO private_ci2027_001;
CREATE TABLE lookup_property_size_class AS TABLE lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_property_size_class ADD COLUMN id uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL;

ALTER TABLE lookup_property_size_class ADD COLUMN abbreviation enum_property_size_class UNIQUE NOT NULL;

--
-- PostgreSQL database dump
--

-- Dumped from database version 13.3 (Debian 13.3-1.pgdg110+1)
-- Dumped by pg_dump version 14.13 (Homebrew)


--
-- Data for Name: lookup_property_size_class; Type: TABLE DATA; Schema: nfi2022; Owner: postgres
--

--INSERT INTO lookup_property_size_class (abbreviation, name_de, name_en, sort, "interval") VALUES
--	('1', 'bis 20 ha', 'up to 20 ha', 19, '{bwi2002,bwi2012}'),
--	('2', 'über 20 bis 50 ha', 'over 20 to 50 ha', 29, '{bwi2002,bwi2012}'),
--	('3', 'über 50 bis 100 ha', 'over 50 to 100 ha', 30, '{bwi2002,bwi2012}'),
--	('4', 'über 100 bis 200 ha', 'over 100 to 200 ha', 40, '{bwi2002,bwi2012}'),
--	('5', 'über 200 bis 500 ha', 'over 200 to 500 ha', 50, '{bwi2002,bwi2012}'),
--	('6', 'über 500 bis 1000 ha', 'over 500 to 1000 ha', 60, '{bwi2002,bwi2012}'),
--	('7', 'über 1000 ha', 'over 1000 ha', 70, '{bwi2002,bwi2012}'),
--	('11', 'bis 5 ha', 'up to 5 ha', 13, '{bwi2002,bwi2012}'),
--	('12', 'über 5 bis 10 ha', 'over 5 to 10 ha', 14, '{bwi2002,bwi2012}'),
--	('13', 'über 10 bis 20 ha', 'over 10 to 20ha', 15, '{bwi2002,bwi2012}'),
--	('21', 'über 20 bis 30 ha', 'over 20 to 30 ha', 21, '{bwi2002,bwi2012}'),
--	('22', 'über 30 bis 50 ha', 'over 30 to 50 ha', 22, '{bwi2002,bwi2012}'),
--	('111', 'bis 1ha', 'up to 1 ha', 11, '{bwi2002,bwi2012}'),
--	('112', 'über 1 bis 5 ha', 'over 1 to 5 ha', 12, '{bwi2002,bwi2012}');


--
-- PostgreSQL database dump complete
--

