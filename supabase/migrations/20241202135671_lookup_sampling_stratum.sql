SET search_path TO private_ci2027_001;
CREATE TABLE lookup_sampling_stratum AS TABLE lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_sampling_stratum ADD COLUMN abbreviation enum_sampling_stratum UNIQUE NOT NULL;

--
-- PostgreSQL database dump
--

-- Dumped from database version 13.3 (Debian 13.3-1.pgdg110+1)
-- Dumped by pg_dump version 14.13 (Homebrew)


--
-- Data for Name: lookup_sampling_stratum; Type: TABLE DATA; Schema: nfi2022; Owner: postgres
--

--INSERT INTO lookup_sampling_stratum (abbreviation, name_de, name_en, sort, "interval") VALUES
--	('104', 'SH04: 1987,2002,2012,2022: 2km*2km', 'SH04: 1987,2002,2012,2022: 2km*2km', 4011, '{bwi2002,bwi2012}'),
--	('216', 'HH16: 1987,2002,2012,2022: 4km*4km', 'HH16: 1987,2002,2012,2022: 4km*4km', 16121, '{bwi2002,bwi2012}'),
--	('308', 'NI08: 1987,2002,2012,2022: 2,83km*2,83km', 'NI08: 1987,2002,2012,2022: 2,83km*2,83km', 8031, '{bwi2002,bwi2012}'),
--	('316', 'NI16: 1987 2002,2012,2022: 4km*4km', 'NI16: 1987 2002,2012,2022: 4km*4km', 16131, '{bwi2002,bwi2012}'),
--	('416', 'HB16: 1987,2002,2012,2022: 4km*4km', 'HB16: 1987,2002,2012,2022: 4km*4km', 16041, '{bwi2002,bwi2012}'),
--	('516', 'NW16: 1987,2002: 4km*4km; 2012,2022: 2km*2km', 'NW16: 1987,2002: 4km*4km; 2012,2022: 2km*2km', 16051, '{bwi2002,bwi2012}'),
--	('616', 'HE16: 1987,2002,2012,2022: 4km*4km', 'HE16: 1987,2002,2012,2022: 4km*4km', 11061, '{bwi2002,bwi2012}'),
--	('704', 'RP04: 1987: 4km*4km; 2002,2012,2022: 2km*2km', 'RP04: 1987: 4km*4km; 2002,2012,2022: 2km*2km', 4071, '{bwi2002,bwi2012}'),
--	('804', 'BW04: 1987,2002,2012,2022: 2km*2km', 'BW04: 1987,2002,2012,2022: 2km*2km', 4081, '{bwi2002,bwi2012}'),
--	('904', 'BY04: 1987: 2km*2km; 2002,2012,2022: 2,83km*2,83km', 'BY04: 1987: 2km*2km; 2002,2012,2022: 2,83km*2,83km', 8091, '{bwi2002,bwi2012}'),
--	('908', 'BY08: 1987,2002,2012,2022: 2,83km*2,83km', 'BY08: 1987,2002,2012,2022: 2,83km*2,83km', 8092, '{bwi2002,bwi2012}'),
--	('916', 'BY16: 1987,2002,2012,2022: 4km*4km', 'BY16: 1987,2002,2012,2022: 4km*4km', 16091, '{bwi2002,bwi2012}'),
--	('1016', 'SL16: 1987,2002,2012: 4km*4km; 2022: 2km*2km', 'SL16: 1987,2002,2012: 4km*4km; 2022: 2km*2km', 16101, '{bwi2002,bwi2012}'),
--	('1116', 'BE16: 1987,2002,2012: 4km*4km; 2022: 2km*2km', 'BE16: 1987,2002,2012: 4km*4km; 2022: 2km*2km', 16111, '{bwi2002,bwi2012}'),
--	('1216', 'BB16: 2002: 4km*4km; 2012,2022: 2km*2km', 'BB16: 2002: 4km*4km; 2012,2022: 2km*2km', 16121, '{bwi2002,bwi2012}'),
--	('1304', 'MV04: 2002,2012,2022: 2km*2km', 'MV04: 2002,2012,2022: 2km*2km', 4131, '{bwi2002,bwi2012}'),
--	('1408', 'SN08: 2002,2012:  2,83km*2,83km; 2022: 2km*2km', 'SN08: 2002,2012:  2,83km*2,83km; 2022: 2km*2km', 8141, '{bwi2002,bwi2012}'),
--	('1516', 'ST16: 2002: 4km*4km; 2012,2022: 2km*2km', 'ST16: 2002: 4km*4km; 2012,2022: 2km*2km', 16151, '{bwi2002,bwi2012}'),
--	('1608', 'TH08: 2002,2012,2022: 2,83km*2,83km', 'TH08: 2002,2012,2022: 2,83km*2,83km', 8161, '{bwi2002,bwi2012}'),
--	('1616', 'TH16: 2002:  4km*4km; 2012,2022: 2,83km*2,83km', 'TH16: 2002:  4km*4km; 2012,2022: 2,83km*2,83km', 16161, '{bwi2002,bwi2012}');


--
-- PostgreSQL database dump complete
--

