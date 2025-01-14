SET search_path TO private_ci2027_001;
CREATE TABLE IF NOT EXISTS cluster (

	intkey varchar(12) UNIQUE NULL,

	id uuid UNIQUE DEFAULT gen_random_uuid() PRIMARY KEY,
	cluster_name INTEGER UNIQUE NOT NULL,
	created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
	modified_at TIMESTAMP DEFAULT NULL,
	modified_by uuid DEFAULT auth.uid() NOT NULL,

	select_access_by TEXT[] NOT NULL DEFAULT array[]::text[],
	update_access_by TEXT[] NOT NULL DEFAULT array[]::text[],
	selectable_by uuid[] NOT NULL DEFAULT array[]::uuid[],
	updatable_by uuid[] NOT NULL DEFAULT array[]::uuid[],
	supervisor uuid NULL, -- Supervisor of the cluster

	topo_map_sheet CK_TopographicMapSheet NULL,
	
	state_responsible enum_state NOT NULL,
	-- state enum_state NULL, -- StandardBl || ToDo: Raus??
	states_affected enum_state[],

	grid_density enum_grid_density NOT NULL,
	cluster_status enum_cluster_status NULL,
	cluster_situation enum_cluster_situation NULL
);
COMMENT ON TABLE private_ci2027_001.cluster IS 'Eindeutige Bezeichung des Traktes';
COMMENT ON COLUMN private_ci2027_001.cluster.id IS 'Unique ID des Traktes';
COMMENT ON COLUMN private_ci2027_001.cluster.created_at IS 'Erstellungsdatum';
--COMMENT ON COLUMN private_ci2027_001.cluster.cluster_name IS 'Eindeutige Bezeichung des Traktes';

COMMENT ON COLUMN private_ci2027_001.cluster.topo_map_sheet IS 'Nummer der topgraphischen Karte 1:25.000';
COMMENT ON COLUMN private_ci2027_001.cluster.state_responsible IS 'Aufnahme-Bundesland für Feldaufnahmen und ggf. Vorklärungsmerkmale';
COMMENT ON COLUMN private_ci2027_001.cluster.states_affected IS 'zugehörige Ländernummer(n), auch mehrere';
COMMENT ON COLUMN private_ci2027_001.cluster.grid_density IS 'Zugehörigkeit zum Stichprobennetz, Netzdichte';
COMMENT ON COLUMN private_ci2027_001.cluster.cluster_status IS 'Traktkennung / Traktkennzeichen lt. Vorklärung durch vTI';
COMMENT ON COLUMN private_ci2027_001.cluster.cluster_situation IS 'Lage des Traktes im Vergleich zu Bundesland- und Landesgrenzen';
ALTER TABLE private_ci2027_001.cluster OWNER TO postgres;
--ALTER TABLE cluster
--	ADD CONSTRAINT FK_Tract_LookupStates
--	FOREIGN KEY (states[])
--	REFERENCES lookup_state (abbreviation);
--
ALTER TABLE cluster
	ADD CONSTRAINT FK_Tract_LookupStateResponsible
	FOREIGN KEY (state_responsible)
	REFERENCES lookup_state (abbreviation);
--ALTER TABLE cluster
--	ADD CONSTRAINT FK_Tract_LookupGridDensity
--	FOREIGN KEY (grid_density)
--	REFERENCES lookup_grid_density (abbreviation);
--
--ALTER TABLE cluster
--	ADD CONSTRAINT FK_Tract_LookupTractIdentifier
--	FOREIGN KEY (cluster_status)
--	REFERENCES lookup_cluster_status (abbreviation);




-- MOVE TO SOMEWHERE ELSE ???

-- Enable Row-Level Security
ALTER TABLE cluster ENABLE ROW LEVEL SECURITY;

