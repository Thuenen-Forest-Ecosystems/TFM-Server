SET search_path TO private_ci2027_001;
CREATE TABLE lookup_stem_form AS TABLE lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_stem_form ADD COLUMN id uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL;
ALTER TABLE lookup_stem_form ADD COLUMN abbreviation enum_stem_form UNIQUE NOT NULL;
--
-- PostgreSQL database dump
--

-- Dumped from database version 13.3 (Debian 13.3-1.pgdg110+1)
-- Dumped by pg_dump version 14.13 (Homebrew)


--
-- Data for Name: lookup_stem_form; Type: TABLE DATA; Schema: nfi2022; Owner: postgres
--

--INSERT INTO lookup_stem_form (abbreviation, name_de, name_en, sort, "interval") VALUES
--	('0', 'nicht wipfelschäftig (Auflösung des Schaftes im Kronenbereich, unter 70% der Baumhöhe)', 'stem not up into the crown (fragmentation of the stem in crown area)', NULL, '{bwi1992,bwi2002,bwi2012}'),
--	('1', 'Wipfelschäftigkeit bei Laub- und Nadelbäumen', 'stem up into the crown by deciduous and coniferous trees', NULL, '{bwi1992,bwi2002,bwi2012}'),
--	('2', 'Zwieselung zwischen Brusthöhe und 7 m Baumhöhe', 'bifurcation between 1,3 m and 7 m high', NULL, '{bwi1992,bwi2002,bwi2012}'),
--	('3', 'kein ausgeprägter einzelner Stamm vorh., Fußpunkt bis Krone < 3m', 'no clear single stem, stem base to begin of crown less than 3 m', NULL, '{bwi1992,bwi2002,bwi2012}'),
--	('4', 'nur BWI1: tot, verwertbar', 'only NFI I: dead, wood still utilizable', NULL, '{bwi1992,bwi2002,bwi2012}'),
--	('5', 'nur BWI1: tot, nicht verwertbar', 'only NFI I: dead, wood not utilizable', NULL, '{bwi1992,bwi2002,bwi2012}'),
--	('6', 'nur BWI1: tot, gebrochen, verwertbar', 'only NFI I: dead or broken stem, wood still utilizable', NULL, '{bwi1992,bwi2002,bwi2012}');


--
-- PostgreSQL database dump complete
--;
