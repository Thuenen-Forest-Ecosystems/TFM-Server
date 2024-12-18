SET search_path TO private_ci2027_001;
CREATE TABLE lookup_edge_status AS TABLE lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_edge_status ADD COLUMN id uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL;

ALTER TABLE lookup_edge_status ADD COLUMN abbreviation enum_edge_status UNIQUE NOT NULL;

--
-- PostgreSQL database dump
--

-- Dumped from database version 13.3 (Debian 13.3-1.pgdg110+1)
-- Dumped by pg_dump version 14.13 (Homebrew)


--
-- Data for Name: lookup_edge_status; Type: TABLE DATA; Schema: nfi2022; Owner: postgres
--

--INSERT INTO lookup_edge_status (abbreviation, name_de, name_en, sort, "interval") VALUES
--	('0', 'neuer Waldrand oder neue Bestestandes-Grenze zu Nichtholzboden', 'new stand border', NULL, '{bwi1992,bwi2002,bwi2012}'),
--	('1', 'übernommener Waldrand o. Best.-Grenze zu Nichtholzboden aus früherer Inventur', 'stand border taken over from ???', NULL, '{bwi1992,bwi2002,bwi2012}'),
--	('4', '"neue" Wald- oder Best.-Grenze, gültig auch Vorgängerinventur (hier BWI3)', '"new" stand edge, valid for ??', NULL, '{bwi1992,bwi2002,bwi2012}'),
--	('5', '"neue" Waldrandgrenze oder Best.Grenze zu Nichtholzboden, gültig auch Vorgängerinventur (hier BWI3)', '"new" edge, valid for ??', NULL, '{bwi1992,bwi2002,bwi2012}'),
--	('9', 'nicht auffindbar, nicht mehr gültig', 'not detectable, no longer valid', NULL, '{bwi1992,bwi2002,bwi2012}'),
--	('10', ' Best.-Grenze der Vorgängerinventur, die temporär (2017) nicht erfasst wurde (Grenzen Rart={3,4})', 'rausBestand', NULL, '{bwi1992,bwi2002,bwi2012}'),
--	('2002', 'schon 2002 bei BWI2 (2001/2002) ausgefallen', NULL, NULL, '{bwi1992,bwi2002,bwi2012}'),
--	('2007', 'schon 2007 bei Landesinventur RP (2007) ausgefallen', NULL, NULL, '{bwi1992,bwi2002,bwi2012}'),
--	('2008', 'schon 2008 bei Treibhausgasinventur bzw. Landesinventur HE, BB, SN 2008 ausgefallen', NULL, NULL, '{bwi1992,bwi2002,bwi2012}'),
--	('2012', 'schon 2012 bei BWI3 (2011/2012), BB2013 oder NW2014 ausgefallen', NULL, NULL, '{bwi1992,bwi2002,bwi2012}'),
--	('2017', 'schon 2017 bei CI17 (2016/2017) bzw. Landesinventuren HE, RP, SN 2017 ausgefallen', NULL, NULL, '{bwi1992,bwi2002,bwi2012}');


--
-- PostgreSQL database dump complete
--

