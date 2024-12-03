SET search_path TO private_ci2027_001;
CREATE TABLE lookup_edge_type AS TABLE lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_edge_type ADD COLUMN abbreviation enum_edge_type UNIQUE NOT NULL;

--
-- PostgreSQL database dump
--

-- Dumped from database version 13.3 (Debian 13.3-1.pgdg110+1)
-- Dumped by pg_dump version 14.13 (Homebrew)


--
-- Data for Name: lookup_edge_type; Type: TABLE DATA; Schema: nfi2022; Owner: postgres
--

--INSERT INTO lookup_edge_type (abbreviation, name_de, name_en, sort, "interval") VALUES
--	('1', 'Außenrand, Abstand > 50 m', 'outside forest edge, distance > 50 m', 10, '{bwi2002,bwi2012}'),
--	('2', 'Innenrand, Abstand 30 bis 50 m', 'inside forest edge, distance 30 to 50 m', 20, '{bwi2002,bwi2012}'),
--	('3', 'Bestandesgrenze (davor >=20 m niedriger)', 'stand edge (preliminary stand with 20 m lower stand high)', 30, '{bwi2002,bwi2012}'),
--	('4', 'sonstige Bestandesgrenze', 'other stand edge', 40, '{bwi2002,bwi2012}');


--
-- PostgreSQL database dump complete
--

