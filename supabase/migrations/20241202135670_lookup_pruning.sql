SET search_path TO private_ci2027_001;
CREATE TABLE lookup_pruning AS TABLE lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_pruning ADD COLUMN id uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL;
ALTER TABLE lookup_pruning ADD COLUMN abbreviation enum_pruning UNIQUE NOT NULL;
--
-- PostgreSQL database dump
--

-- Dumped from database version 13.3 (Debian 13.3-1.pgdg110+1)
-- Dumped by pg_dump version 14.13 (Homebrew)


--
-- Data for Name: lookup_pruning; Type: TABLE DATA; Schema: nfi2022; Owner: postgres
--

--INSERT INTO lookup_pruning (abbreviation, name_de, name_en, sort, "interval") VALUES
--	('0', 'keine Astung', 'no pruning', 10, '{bwi2002,bwi2012}'),
--	('1', 'Astung bis 2,5 m (Astungshöhe 2 m)', 'hight of pruning up to 2,5 m', 11, '{bwi2002,bwi2012}'),
--	('2', 'Astung von 2,5 bis 5 m (Astungshöhe 4 m)', 'hight of pruning from 2,5 m to 5 m', 12, '{bwi2002,bwi2012}'),
--	('3', 'Astung von 5 bis 7,5 m (Astungshöhe 6,5 m)', 'hight of pruning from 5 m to 7,5 m', 14, '{bwi2002,bwi2012}'),
--	('4', 'Astung von 5,5 bis 10 m (Astungshöhe 8,75 m)', 'hight of pruning from 7,5 m to 10 m', 15, '{bwi2002,bwi2012}'),
--	('5', 'Astung von 10 m bis 15m (Astungshöhe 12,5 m)', 'hight of pruning above 10 m', 16, '{bwi2002,bwi2012}'),
--	('6', 'Astung höher als 15 m', 'hight of pruning above 10 m', 16, '{bwi2002,bwi2012}'),
--	('9', 'Astung höher als 5 m', 'hight of pruning above 5 m', 19, '{bwi2002,bwi2012}');


--
-- PostgreSQL database dump complete
--;
