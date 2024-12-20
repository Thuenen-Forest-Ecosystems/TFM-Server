SET search_path TO private_ci2027_001;
CREATE TABLE lookup_state AS TABLE lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_state ADD COLUMN id uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL;
ALTER TABLE lookup_state ADD COLUMN abbreviation enum_state UNIQUE NOT NULL;
--
-- PostgreSQL database dump
--

-- Dumped from database version 13.3 (Debian 13.3-1.pgdg110+1)
-- Dumped by pg_dump version 14.13 (Homebrew)


--
-- Data for Name: lookup_state; Type: TABLE DATA; Schema: nfi2022; Owner: postgres
--

--INSERT INTO lookup_state (abbreviation, name_de, name_en, sort, "interval") VALUES
--	('--', '(außerhalb Deutschlands)', '(outside germany area)', 1790, '{bwi2002,bwi2012}'),
--	('SH', 'Schleswig-Holstein', 'Schleswig-Holstein', 190, '{bwi2002,bwi2012}'),
--	('HH', 'Hansestadt Hamburg', 'Hansestadt Hamburg', 290, '{bwi2002,bwi2012}'),
--	('NI', 'Niedersachsen', 'Niedersachsen', 390, '{bwi2002,bwi2012}'),
--	('HB', 'Hansestadt Bremen', 'Hansestadt Bremen', 490, '{bwi2002,bwi2012}'),
--	('NW', 'Nordrhein-Westfalen', 'Nordrhein-Westfalen', 590, '{bwi2002,bwi2012}'),
--	('HE', 'Hessen', 'Hessen', 690, '{bwi2002,bwi2012}'),
--	('RP', 'Rheinland-Pfalz', 'Rheinland-Pfalz', 790, '{bwi2002,bwi2012}'),
--	('BW', 'Baden-Württemberg', 'Baden-Württemberg', 890, '{bwi2002,bwi2012}'),
--	('BY', 'Bayern', 'Bayern', 990, '{bwi2002,bwi2012}'),
--	('SL', 'Saarland', 'Saarland', 1090, '{bwi2002,bwi2012}'),
--	('BE', 'Berlin', 'Berlin', 1190, '{bwi2002,bwi2012}'),
--	('BB', 'Brandenburg', 'Brandenburg', 1290, '{bwi2002,bwi2012}'),
--	('MV', 'Mecklenburg-Vorpommern', 'Mecklenburg-Vorpommern', 1390, '{bwi2002,bwi2012}'),
--	('SN', 'Sachsen', 'Sachsen', 1490, '{bwi2002,bwi2012}'),
--	('ST', 'Sachsen-Anhalt', 'Sachsen-Anhalt', 1590, '{bwi2002,bwi2012}'),
--	('TH', 'Thüringen', 'Thüringen', 1690, '{bwi2002,bwi2012}');


--
-- PostgreSQL database dump complete
--;
