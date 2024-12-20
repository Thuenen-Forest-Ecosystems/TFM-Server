SET search_path TO private_ci2027_001;
CREATE TABLE structure_lt4m (

    intkey varchar(12) UNIQUE NULL,

    id uuid UNIQUE DEFAULT gen_random_uuid() PRIMARY KEY,
    plot_id uuid NOT NULL,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
	modified_at TIMESTAMP DEFAULT NULL,
    modified_by uuid DEFAULT auth.uid() NOT NULL,

	tree_species INTEGER NULL, --Ba
	coverage INTEGER NOT NULL, --Anteil TODO: enum_coverage NEU
	regeneration_type INTEGER NULL --Vart TODO: enum_reg_type NEU
);
COMMENT ON TABLE structure_lt4m IS 'Probekreis mit 10 m Radius für die Erfassung der Jungbestockung - Bäume bis 4 m Höhe';
COMMENT ON COLUMN structure_lt4m.id IS 'Primary Key';
COMMENT ON COLUMN structure_lt4m.plot_id IS 'Foreign Key to Plot.id';
COMMENT ON COLUMN structure_lt4m.tree_species IS 'Baumart';
COMMENT ON COLUMN structure_lt4m.coverage IS 'Anteil der Baumart in Zehntel (Deckungsgrad entspricht 10 Zehntel = 100 %)';
COMMENT ON COLUMN structure_lt4m.regeneration_type IS 'Verjüngungsart der Baumart';
ALTER TABLE structure_lt4m ADD CONSTRAINT FK_StructureLt4m_Plot FOREIGN KEY (plot_id) REFERENCES plot(id)
	ON DELETE CASCADE;
--- plot_location_id
--ALTER TABLE structure_lt4m ADD CONSTRAINT FK_StructureLt4m_PlotLocation FOREIGN KEY (plot_location_id)
--	REFERENCES plot_location (id)
--	ON DELETE CASCADE;

ALTER TABLE structure_lt4m ADD CONSTRAINT FK_StructureLt4m_LookupTreeSpecies FOREIGN KEY (tree_species)
    REFERENCES lookup_tree_species (abbreviation);
--ALTER TABLE structure_lt4m ADD CONSTRAINT FK_StructureLt4m_LookupCoverage FOREIGN KEY (coverage)
--    REFERENCES lookup_coverage (abbreviation);
--
--ALTER TABLE structure_lt4m ADD CONSTRAINT FK_StructureLt4m_LookupRegType FOREIGN KEY (regeneration_type)
--    REFERENCES lookup_regeneration_type (abbreviation);

-- Create example data
--INSERT INTO structure_lt4m (plot_id, tree_species, coverage, regeneration_type) VALUES (1, 1, 10, 1);
