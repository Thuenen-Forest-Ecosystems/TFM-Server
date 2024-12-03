SET search_path TO private_ci2027_001;
CREATE TABLE lookup_exploration_instruction AS TABLE lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_exploration_instruction ADD COLUMN id uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL;

ALTER TABLE lookup_exploration_instruction ADD COLUMN abbreviation enum_exploration_instruction UNIQUE NOT NULL;

--
-- PostgreSQL database dump
--

-- Dumped from database version 13.3 (Debian 13.3-1.pgdg110+1)
-- Dumped by pg_dump version 14.13 (Homebrew)


--
-- Data for Name: lookup_exploration_instruction; Type: TABLE DATA; Schema: nfi2022; Owner: postgres
--

--INSERT INTO lookup_exploration_instruction (abbreviation, name_de, name_en, sort, "interval") VALUES
--	('0', 'ohne Standortkarierung', NULL, 0, '{bwi2012}'),
--	('1', 'Standortserkundungsanweisung 1974 und 1981', NULL, NULL, '{bwi2012}'),
--	('2', 'Standortserkundungsanweisung 1995', NULL, NULL, '{bwi2012}'),
--	('3', 'AK Standortskartierung, 2003 (Forstliche Standortsaufnahme 6. Aufl., S. 282-284)', NULL, NULL, '{bwi2012}'),
--	('4', 'Hessische Anweisung für Forsteinrichtungsarbeiten aus dem Jahre 2002', NULL, NULL, '{bwi2012}'),
--	('5', 'Arbeitsanleitung zur Standortkartierung in Schleswig-Holstein 2001', NULL, NULL, '{bwi2012}'),
--	('6', 'Anwsg. für Standortkart. in Staats- und Körperschaftswald der Forstdirektion Koblenz – A. Sta. 61', NULL, NULL, '{bwi2012}'),
--	('7', 'Anwsg. für Standortkart. in Staats- und Körperschaftswald von Rheinland-Pfalz – A. Sta. 96', NULL, NULL, '{bwi2012}'),
--	('8', 'DA für forstl. Standorterkundung in Nordrhein-Westfalen 2003 (Forstliche Standorterkundung 2003 NW)', NULL, NULL, '{bwi2012}'),
--	('9', 'AK Standortskartierung, 2003 (Forstliche Standortsaufnahme 6. Aufl., S. 277-282)', NULL, NULL, '{bwi2012}'),
--	('10', 'Richtlinien für Bewirtschaftung des Staatswaldes im Saarland. 1. Teil Standortsökol. Grundlagen 1986', NULL, NULL, '{bwi2012}'),
--	('11', 'Forstl. Standortsaufn., Geländeökol. Schätzrahmen für Mittelgeb., Berg-/Hügelland... (Stand 01/2007)', NULL, NULL, '{bwi2012}'),
--	('12', 'Forstl. Standortsaufn., Geländeökol. Schätzrahmen für pleistozänes Tiefland (Stand 12/2006)', NULL, NULL, '{bwi2012}'),
--	('99', 'mit Standortkartierung, aber unbestimmt mit welcher', NULL, NULL, '{bwi2012}');


--
-- PostgreSQL database dump complete
--

