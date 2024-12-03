SET search_path TO private_ci2027_001;
CREATE TABLE lookup_stem_breakage AS TABLE lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_stem_breakage ADD COLUMN abbreviation enum_stem_breakage UNIQUE NOT NULL;

--
-- PostgreSQL database dump
--

-- Dumped from database version 13.3 (Debian 13.3-1.pgdg110+1)
-- Dumped by pg_dump version 14.13 (Homebrew)


--
-- Data for Name: lookup_stem_breakage; Type: TABLE DATA; Schema: nfi2022; Owner: postgres
--

--INSERT INTO lookup_stem_breakage (abbreviation, name_de, name_en, sort, "interval") VALUES
--	('0', 'kein Schaftbruch', 'no broken stem', NULL, '{bwi1992,bwi2002,bwi2012}'),
--	('1', 'Wipfelbruch (abgebrochener Teil bis 3 m Länge)', 'broken top (length of broken part up to 3 m)', NULL, '{bwi1992,bwi2002,bwi2012}'),
--	('2', 'Kronenbruch (abgebrochener Teil über 3 m Länge)', 'broken crown (length of broken part more than 3 m)', NULL, '{bwi1992,bwi2002,bwi2012}');


--
-- PostgreSQL database dump complete
--

