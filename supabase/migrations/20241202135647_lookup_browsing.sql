SET search_path TO private_ci2027_001;
CREATE TABLE lookup_browsing AS TABLE lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_browsing ADD COLUMN abbreviation enum_browsing UNIQUE NOT NULL;
ALTER TABLE lookup_browsing ADD COLUMN id uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL;
--
-- PostgreSQL database dump
--

-- Dumped from database version 13.3 (Debian 13.3-1.pgdg110+1)

-- Dumped by pg_dump version 14.13 (Homebrew)


--
-- Data for Name: lookup_browsing; Type: TABLE DATA; Schema: nfi2022; Owner: postgres
--

--INSERT INTO lookup_browsing (abbreviation, name_de, name_en, sort, "interval") VALUES
--	('0', 'kein Verbiss', 'no', NULL, '{bwi2002,bwi2012}'),
--	('1', 'einfacher (nur) Verbiss der Terminalknospe innerhalb der letzten 12 Monate', 'single', NULL, '{bwi2002,bwi2012}'),
--	('2', 'mehrfacher Verbiss über längeren Zeitraum (einschließlich der letzten 12 Monate)', 'multi', NULL, '{bwi2002,bwi2012}'),
--	('3', 'Verbiss im oberen Drittel an mindestens drei Seitentrieben bei intakter Terminalknospe', NULL, NULL, '{bwi2002,bwi2012}'),
--	('4', 'Verbiss im oberen Drittel an mindestens drei Seitentrieben UND der Terminalknospe', NULL, NULL, '{bwi2002,bwi2012}');



--
-- PostgreSQL database dump complete
--;
