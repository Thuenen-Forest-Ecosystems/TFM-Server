SET search_path TO private_ci2027_001;
CREATE TABLE lookup_cluster_status AS TABLE lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_cluster_status ADD COLUMN id uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL;

ALTER TABLE lookup_cluster_status ADD COLUMN abbreviation enum_cluster_status UNIQUE NOT NULL;

--
-- PostgreSQL database dump
--

-- Dumped from database version 13.3 (Debian 13.3-1.pgdg110+1)
-- Dumped by pg_dump version 14.13 (Homebrew)


--
-- Data for Name: lookup_cluster_status; Type: TABLE DATA; Schema: nfi2022; Owner: postgres
--

--INSERT INTO lookup_cluster_status (abbreviation, name_de, name_en, sort, "interval") VALUES
--	('1', 'Trakt völlig außerhalb des Inventurgebietes, nicht zu erfassen (Anzahl Ecken = 0)', 'tract outside the federal territory, not to collect', 1, '{bwi2002,bwi2012}'),
--	('2', 'Trakt an der Grenze zwischen 2 BL, wird wegen unterschiedl. Verdichtung nur teilweise erfasst', 'tract at the frontier between two federal states, only partial collected', 2, '{bwi2002,bwi2012}'),
--	('3', 'Trakt an der Grenze zwischen 2 BL, wird vollständig erfasst (Anzahl Ecken = 4)', 'tract at the frontier between two federal states, complete collected', 3, '{bwi2002,bwi2012}'),
--	('4', 'Normaltrakt, der vollständig erfasst wird (Anzahl Ecken = 4)', 'normal tract, complete collected', 4, '{bwi2002,bwi2012}'),
--	('5', 'Trakt nicht im Raster der BWI, nicht zu erfassen (Anzahl Ecken = 0)', 'tract not in the sample grit, not to collect', 5, '{bwi2002,bwi2012}'),
--	('6', 'Trakt an der Staatsgrenze, der nur teilweise erfasst wird (0 < Anzahl Ecken < 4)', 'tract at the national border, only partial collected', 6, '{bwi2002,bwi2012}'),
--	('7', 'Trakt an der Grenze zw. 2 Vbl in 1 BL ,wird wegen unterschiedl. Verdichtung nur teilweise erfasst', 'tract at the frontier between 2 sampling density areas in one federal state, only partial collected', 7, '{bwi2002,bwi2012}'),
--	('8', 'Trakt an der Grenze zw. 2 Vbl in 1 BL ,wird vollständig erfasst (Anzahl Ecken = 4)', 'tract at the frontier between 2 sampling density areas in one federal state, complete collected', 8, '{bwi2002,bwi2012}'),
--	('9', 'Trakt übersehen / nicht berücksichtigt / nicht betrachtet (vermutlich Fehler)', 'tract not see', 9, '{bwi2002,bwi2012}'),
--	('10', 'Trakt liegt sehr dicht an einem anderem Trakt (Meridiansprung) und wird deshalb nicht erfasst', '???', 10, '{bwi2002,bwi2012}'),
--	('11', 'ÖWK-Trakt, Trakt nicht im Raster der BWI, ÖWK-Trakt hat nur eine Ecke', '''ÖWK-Trakt'', tract not in the NFI sample grit', 11, '{bwi2002,bwi2012}'),
--	('12', 'Schulungs-Trakt für AT/KT, Trakt nicht im Raster der BWI (BY-Kehlheim,RP-Hachenburg,BB-Eberswalde)', '''Scool-tract'', tract not in the NFI sample grit', 12, '{bwi2002,bwi2012}'),
--	('13', 'Demonstrations-Trakt, Trakt nicht im Raster der BWI (Eberswalde, Nähe Thünen-Institut)', '''Demo-tract'', tract not in the NFI sample grit', 13, '{bwi2002,bwi2012}');


--
-- PostgreSQL database dump complete
--

