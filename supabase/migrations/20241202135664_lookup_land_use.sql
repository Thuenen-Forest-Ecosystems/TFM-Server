SET search_path TO private_ci2027_001;
CREATE TABLE lookup_land_use AS TABLE lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_land_use ADD COLUMN id uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL;
ALTER TABLE lookup_land_use ADD COLUMN abbreviation enum_land_use UNIQUE NOT NULL;
--
-- PostgreSQL database dump
--

-- Dumped from database version 13.3 (Debian 13.3-1.pgdg110+1)
-- Dumped by pg_dump version 14.13 (Homebrew)


--
-- Data for Name: lookup_land_use; Type: TABLE DATA; Schema: nfi2022; Owner: postgres
--

--INSERT INTO lookup_land_use (abbreviation, name_de, name_en, sort, "interval") VALUES
--	('3', 'Feuchtflächen', 'moisture areas', 30, '{bwi2002,bwi2012}'),
--	('4', 'Wasserflächen', 'surface waters', 40, '{bwi2002,bwi2012}'),
--	('11', 'Industrie-, Gewerbe-, Verkehrsflächen', 'industrial areas, traffic areas', 11, '{bwi2002,bwi2012}'),
--	('12', 'keiner anderen Kategorie zugehörige bebaute oder versiegelte Flächen (z.B. Wohngebiete)', 'residential areas, other areas covered with buildings and other sealed surfaces', 12, '{bwi2002,bwi2012}'),
--	('13', 'Abbauflächen, Deponien, Halden, offene Flächen ohne oder mit geringer Vegetation', 'excavation areas, landfills, dumps', 13, '{bwi2002,bwi2012}'),
--	('14', 'Städtische Grünflächen, sonstige nicht versiegelte Flächen, Sport- u. Freizeitanlagen', 'urban green areas, sports facilities, recreational facilities and other non seales surfaces', 14, '{bwi2002,bwi2012}'),
--	('21', 'Ackerland', 'agricultural land', 21, '{bwi2002,bwi2012}'),
--	('22', 'Dauerkulturen (Rebflächen, Obstbestände, Hopfen, nicht zum Wald gehörige Baumschulen)', 'continuous crops (viticulture, orchards, hop fields, tree nurseries outside forests)', 22, '{bwi2002,bwi2012}'),
--	('23', 'Dauergrünland (Weiden, Wiesen, natürliches Grünland, Heiden, Wald-Strauch-Übergangstadien)', 'permanent grassland (pastures and meadows, natural green areas, heathland, succession areas )', 23, '{bwi2002,bwi2012}'),
--	('90', 'Traktecke war schon früher eindeutig Nichtwald (Falschansprache Waldentscheid bei Vorgängerinventur)', NULL, 90, '{bwi2002,bwi2012}'),
--	('92', 'Traktecke war schon früher eindeutig Nichtholzboden (fehlende/falsche Ansprache Vorgängerinventur)', NULL, 92, '{bwi2002,bwi2012}'),
--	('93', 'Traktecke war schon früher eindeutig Holzboden (fehlende/falsche Ansprache Vorgängerinventur)', NULL, 93, '{bwi2002,bwi2012}'),
--	('99', 'Traktecke war schon früher eindeutig Wald (fehlende Ansprache Vorgängerinventur)', NULL, 99, '{bwi2002,bwi2012}');


--
-- PostgreSQL database dump complete
--;
