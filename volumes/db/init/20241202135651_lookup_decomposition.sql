SET search_path TO private_ci2027_001;
CREATE TABLE lookup_decomposition AS TABLE lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_decomposition ADD COLUMN id uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL;

ALTER TABLE lookup_decomposition ADD COLUMN abbreviation enum_decomposition UNIQUE NOT NULL;

--
-- PostgreSQL database dump
--

-- Dumped from database version 13.3 (Debian 13.3-1.pgdg110+1)
-- Dumped by pg_dump version 14.13 (Homebrew)


--
-- Data for Name: lookup_decomposition; Type: TABLE DATA; Schema: nfi2022; Owner: postgres
--

--INSERT INTO lookup_decomposition (abbreviation, name_de, name_en, sort, "interval") VALUES
--	('1', 'unzersetzt', 'undecomposed', NULL, '{bwi2002,bwi2012}'),
--	('2', 'beginnende Zersetzung', 'starting decomposition', NULL, '{bwi2002,bwi2012}'),
--	('3', 'fortgeschrittene Zersetzung', 'proceeded decomposition', NULL, '{bwi2002,bwi2012}'),
--	('4', 'stark vermodert', 'heavily decomposed', NULL, '{bwi2002,bwi2012}');


--
-- PostgreSQL database dump complete
--

