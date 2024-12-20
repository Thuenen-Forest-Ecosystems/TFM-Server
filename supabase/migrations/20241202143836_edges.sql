SET search_path TO private_ci2027_001, public;
CREATE TABLE IF NOT EXISTS edges (

    intkey varchar(12) UNIQUE NULL,

    id uuid UNIQUE DEFAULT gen_random_uuid() PRIMARY KEY,
	plot_id uuid NOT NULL,

	edge_number INTEGER NULL, -- NEU: Kanten-ID || ToDo: Welchen Mehrwert hat diese ID gegenüber der ID?

	created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
	modified_at TIMESTAMP DEFAULT NULL,
    modified_by uuid DEFAULT auth.uid() NOT NULL,

	edge_status enum_edge_status NULL, --Rk
	edge_type enum_edge_type NULL, --Rart
	terrain enum_terrain NULL, --Rterrain


	edges JSONB NOT NULL, -- NEU: GeoJSON
	geometry_edges extensions.Geometry(LineString, 4326) NULL -- NEU: Geometrie
);
COMMENT ON TABLE edges IS 'Tabelle für die Kanten';
COMMENT ON COLUMN edges.id IS 'Primärschlüssel';
COMMENT ON COLUMN edges.plot_id IS 'Fremdschlüssel auf Plot';
COMMENT ON COLUMN edges.created_at IS 'Erstellungszeitpunkt';
COMMENT ON COLUMN edges.edge_status IS 'Kennziffer des Wald-/Bestandesrandes';
COMMENT ON COLUMN edges.edge_type IS 'Art des Wald- /Bestandesrandes';
COMMENT ON COLUMN edges.terrain IS 'Vorgelagertes Terrain';
COMMENT ON COLUMN edges.geometry_edges IS 'Geometrie der Kante';
ALTER TABLE edges ADD CONSTRAINT FK_Edges_Plot_Unique UNIQUE (plot_id, edge_number);
ALTER TABLE edges ADD CONSTRAINT FK_Edges_Plot FOREIGN KEY (plot_id) REFERENCES plot(id)
	ON DELETE CASCADE;
--ALTER TABLE edges ADD CONSTRAINT CK_Edges_Geometry CHECK (ST_IsValid(geometry_edges));

ALTER TABLE edges ADD CONSTRAINT FK_Edge_LookupEdgeStatus FOREIGN KEY (edge_status)
	REFERENCES lookup_edge_status (abbreviation);
ALTER TABLE edges ADD CONSTRAINT FK_Edge_LookupEdgeType FOREIGN KEY (edge_type)
	REFERENCES lookup_edge_type (abbreviation);
ALTER TABLE edges ADD CONSTRAINT FK_Edge_LookupTerrain FOREIGN KEY (terrain)
	REFERENCES lookup_terrain (abbreviation);
-- Create the function to update geometry_edges;
