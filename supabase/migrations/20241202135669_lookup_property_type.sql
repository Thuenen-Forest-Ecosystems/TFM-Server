SET search_path TO private_ci2027_001;
CREATE TABLE lookup_property_type AS TABLE lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_property_type ADD COLUMN id uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL;

ALTER TABLE lookup_property_type ADD COLUMN abbreviation enum_property_type UNIQUE NOT NULL;

--
-- PostgreSQL database dump
--

-- Dumped from database version 13.3 (Debian 13.3-1.pgdg110+1)
-- Dumped by pg_dump version 14.13 (Homebrew)


--
-- Data for Name: lookup_property_type; Type: TABLE DATA; Schema: nfi2022; Owner: postgres
--

--INSERT INTO lookup_property_type (abbreviation, name_de, name_en, sort, "interval") VALUES
--	('1', 'Staatswald (Bund)', 'forest in federal property', 19, '{bwi2002,bwi2012}'),
--	('2', 'Staatswald (Land)', 'forest in state property', 29, '{bwi2002,bwi2012}'),
--	('3', 'Körperschaftswald', 'corporation forest', 39, '{bwi2002,bwi2012}'),
--	('4', 'Privatwald', 'private forest', 49, '{bwi2002,bwi2012}'),
--	('5', 'Treuhandwald', '???forest in management of the privatisation agency', 59, '{bwi2002,bwi2012}'),
--	('21', 'Staatswald (anderes Land)', 'forest in state property (other federal state)', 21, '{bwi2002,bwi2012}'),
--	('30', 'Körperschaftswald (Gemeindewald)', 'corporation forest (communal forest)', 30, '{bwi2002,bwi2012}'),
--	('31', 'Körperschaftswald (Kirchenwald)', 'corporation forest (parish forest)', 31, '{bwi2002,bwi2012}'),
--	('32', 'Körperschaftswald (Gemeinschaftwald)', 'corporation forest (community forest)', 32, '{bwi2002,bwi2012}'),
--	('33', 'Körperschaftswald (Genossenschaftswald)', 'corporation forest (cooperative forest)', 33, '{bwi2002,bwi2012}'),
--	('34', 'Körperschaftswald (Land)', 'corporation forest (land)', 34, '{bwi2002,bwi2012}'),
--	('35', 'Körperschaftswald (Bund)', 'corporation forest (federal)', 35, '{bwi2002,bwi2012}'),
--	('40', 'Privatwald (im engeren Sinn)', 'private forest (???)', 40, '{bwi2002,bwi2012}'),
--	('41', 'Privatwald (Kirchenwald)', 'private forest (parish forest)', 41, '{bwi2002,bwi2012}'),
--	('42', 'Privatwald (Gemeinschaftswald)', 'private forest (community forest)', 42, '{bwi2002,bwi2012}'),
--	('43', 'Privatwald (Genossenschaftswald)', 'private forest (cooperative forest)', 43, '{bwi2002,bwi2012}'),
--	('44', 'Privatwald (Land)', 'privat forest (cooperative forest)', 44, '{bwi2002,bwi2012}'),
--	('45', 'Privatwald (Bund)', 'privat forest (federal)', 45, '{bwi2002,bwi2012}');


--
-- PostgreSQL database dump complete
--

