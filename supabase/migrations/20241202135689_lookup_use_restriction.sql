SET search_path TO private_ci2027_001;
CREATE TABLE lookup_use_restriction AS TABLE lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_use_restriction ADD COLUMN abbreviation enum_use_restriction UNIQUE NOT NULL;

--
-- PostgreSQL database dump
--

-- Dumped from database version 13.3 (Debian 13.3-1.pgdg110+1)
-- Dumped by pg_dump version 14.13 (Homebrew)


--
-- Data for Name: lookup_use_restriction; Type: TABLE DATA; Schema: nfi2022; Owner: postgres
--

--INSERT INTO lookup_use_restriction (abbreviation, name_de, name_en, sort, "interval") VALUES
--	('0', 'keine Einschränkung der Holznutzung', 'no restrictions for forest harvesting', 20, '{bwi2002,bwi2012}'),
--	('1', 'eingeschränkte  Holznutzung', 'restrictions for forest harvesting', 21, '{bwi1992,bwi2002,bwi2012}'),
--	('2', 'Holznutzung nicht zulässig oder zu erwarten (komplett 3/3)', 'forest harvesting not allowed', 22, '{bwi2002,bwi2012}'),
--	('3', '1/3 des üblichen Aufkommens erwartbar', '1/3 of normal harvesting expectable', 21, '{bwi2002,bwi2012}'),
--	('4', '2/3 des üblichen Aufkommens erwartbar', '2/3 of normal harvesting expectable', 21, '{bwi2002,bwi2012}'),
--	('5', 'keine Holznutzung aus gesetzl. oder vertragl. Gründen nicht gestattet', 'no forest harvesting  not allowed because legal or contractual reasons', 25, '{bwi1992,bwi2002,bwi2012}'),
--	('6', 'keine Holznutzung aufgrund örtlicher Gegebenheiten nicht erwartbar', 'no forest harvesting  not expected because local conditions', 26, '{bwi1992,bwi2002,bwi2012}');


--
-- PostgreSQL database dump complete
--

