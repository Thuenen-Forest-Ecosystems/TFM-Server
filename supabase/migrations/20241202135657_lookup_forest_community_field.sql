SET search_path TO private_ci2027_001;
CREATE TABLE lookup_forest_community_field AS TABLE lookup_TEMPLATE WITH NO DATA;
ALTER TABLE lookup_forest_community_field ADD COLUMN abbreviation enum_forest_community_field UNIQUE NOT NULL;

--
-- PostgreSQL database dump
--

-- Dumped from database version 13.3 (Debian 13.3-1.pgdg110+1)
-- Dumped by pg_dump version 14.13 (Homebrew)


--
-- Data for Name: lookup_forest_community_field; Type: TABLE DATA; Schema: nfi2022; Owner: postgres
--

--INSERT INTO lookup_forest_community_field (abbreviation, name_de, name_en, sort, "interval") VALUES
--	('1', 'Hainsimsen-Buchenwald, z.T. mit Tanne', 'Luzulo-Fagetum', NULL, '{bwi2002,bwi2012}'),
--	('2', 'Drahtschmielen-Buchenwald', 'Deschampsio-Fagetum', NULL, '{bwi2002,bwi2012}'),
--	('3', 'Waldmeister-Buchenwald, z.T. mit Tanne', 'Galio odorati-Fagetum', NULL, '{bwi2002,bwi2012}'),
--	('4', 'Waldgersten-Buchenwald, z.T. mit Tanne', 'Hordelymo-Fagetum', NULL, '{bwi2002,bwi2012}'),
--	('5', 'Buchen-Traubeneichenwald', 'Fago-Quercetum', NULL, '{bwi2002,bwi2012}'),
--	('6', 'Alpenheckenkirschen-Tannen-Buchenwald', 'Lonicero alpigenae-Fagetum', NULL, '{bwi2002,bwi2012}'),
--	('7', 'Seggen-Buchenwald', 'Carici-Fagetum', NULL, '{bwi2002,bwi2012}'),
--	('8', 'Fichten-Buchenwald', 'Fago-Piceetum', NULL, '{bwi2002,bwi2012}'),
--	('9', 'Bergahorn-Buchenwald', 'Aceri-Fagetum', NULL, '{bwi2002,bwi2012}'),
--	('10', 'Hainsimsen-Fichten-Tannenwald', 'Luzulo-Abietetum', NULL, '{bwi2002,bwi2012}'),
--	('11', 'Labkraut-Fichten-Tannenwald', 'Galio rotundifolii-Abietetum', NULL, '{bwi2002,bwi2012}'),
--	('12', 'Preiselbeer-Fichten-Tannenwald', 'Vaccinio-Abietetum', NULL, '{bwi2002,bwi2012}'),
--	('13', 'Wintergrün-Fichten-Tannenwald', 'Pyrolo-Abietetum', NULL, '{bwi2002,bwi2012}'),
--	('14', 'Birken-Stieleichenwald', 'Betulo-Quercetum roboris', NULL, '{bwi2002,bwi2012}'),
--	('15', 'Birken-Traubeneichenwald', 'Luzulo-Quercetum', NULL, '{bwi2002,bwi2012}'),
--	('16', 'Preiselbeer-Eichenwald und Weißmoos-Kiefernwald', 'Vaccino vitis idae-Quercetum und Leucobryo-Pinetum', NULL, '{bwi2002,bwi2012}'),
--	('17', 'Sternmieren-Hainbuchen-Stieleichenwald', 'Stellario holosteae-Carpinetum', NULL, '{bwi2002,bwi2012}'),
--	('18', 'Waldlabkraut-Hainbuchen-Traubeneichenwald', 'Galio sylvatici-Carpinetum', NULL, '{bwi2002,bwi2012}'),
--	('19', 'Traubeneichen-Linden-Wälder', 'Querco-Tilietum', NULL, '{bwi2002,bwi2012}'),
--	('20', 'Xerotherme Eichen-Mischwälder', 'Quercion pubescenti-petreae, Carpinion p.p.', NULL, '{bwi2002,bwi2012}'),
--	('21', 'Schneeheide-Kiefernwälder', 'Erico-Pinetum', NULL, '{bwi2002,bwi2012}'),
--	('22', 'Kiefern-Steppenwald', 'Pyrolo-Pinetum', NULL, '{bwi2002,bwi2012}'),
--	('23', 'Ahorn-Eschenwald', 'Adoxo-Aceretum', NULL, '{bwi2002,bwi2012}'),
--	('24', 'Edellaubbaum-Steinschutt- und Blockhangwälder', 'Lunario-Acerenion p.p., Tilienion platyphylli', NULL, '{bwi2002,bwi2012}'),
--	('25', 'Grünerlengebüsch', 'Alnetum viridis', NULL, '{bwi2002,bwi2012}'),
--	('26', 'Karpatenbirken-Ebereschen-Blockwald', 'Betula carpaticae-Sorbetum', NULL, '{bwi2002,bwi2012}'),
--	('27', 'Block-Fichtenwald', 'Asplenio-Piceetum', NULL, '{bwi2002,bwi2012}'),
--	('28', 'Peitschenmoos-Fichtenwald', 'Bazzanio-Piceetum', NULL, '{bwi2002,bwi2012}'),
--	('29', 'Bergreitgras-Fichtenwald', 'Calamagrostio villosae-Piceetum', NULL, '{bwi2002,bwi2012}'),
--	('30', 'Alpenlattich-Fichtenwald', 'Homogyno-Piceetum', NULL, '{bwi2002,bwi2012}'),
--	('31', 'Alpenrosen-Latschengebüsche', 'Erico-Mugetum, Rhododendro-Vaccinienion p.p.', NULL, '{bwi2002,bwi2012}'),
--	('32', 'Lärchen-Zirbenwald', 'Vaccinio-Pinetum cembrae', NULL, '{bwi2002,bwi2012}'),
--	('33', 'Rauschbeeren-Moorwälder', 'Piceo-Vaccinienion', NULL, '{bwi2002,bwi2012}'),
--	('34', 'Schwarzerlen-Bruch- und Sumpfwälder', 'Alnion glutinosae', NULL, '{bwi2002,bwi2012}'),
--	('35', 'Traubenkirschen-Erlen-Eschenwälder', 'Pruno-Fraxinetum', NULL, '{bwi2002,bwi2012}'),
--	('36', 'Bach-Eschenwälder', 'Carici remotae-Fraxinetum', NULL, '{bwi2002,bwi2012}'),
--	('37', 'Hainmieren-Schwarzerlen-Auewald', 'Stellario-Alnetum', NULL, '{bwi2002,bwi2012}'),
--	('38', 'Grauerlenauewald', 'Alnetum incanae', NULL, '{bwi2002,bwi2012}'),
--	('39', 'Stieleichen-Ulmen-Hartholzauewald', 'Querco-Ulmetum', NULL, '{bwi2002,bwi2012}'),
--	('40', 'Silberweiden-Weichholzauewald', 'Salicetum albae', NULL, '{bwi2002,bwi2012}'),
--	('161', 'Preiselbeer-Eichenwald', 'Vaccinio vitis-idaeae-Quercetum', NULL, '{bwi2002,bwi2012}'),
--	('162', 'Weißmoos-Kiefernwald', 'Leucobryo-Pinetum', NULL, '{bwi2002,bwi2012}');


--
-- PostgreSQL database dump complete
--

