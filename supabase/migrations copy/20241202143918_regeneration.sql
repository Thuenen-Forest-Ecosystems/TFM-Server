SET search_path TO private_ci2027_001;

CREATE TABLE regeneration (

	intkey varchar(12) UNIQUE NULL,

    id uuid UNIQUE DEFAULT gen_random_uuid() PRIMARY KEY,
    plot_id uuid NOT NULL,

	created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
	modified_at TIMESTAMP DEFAULT NULL,
    modified_by uuid DEFAULT auth.uid() NOT NULL,

	tree_species smallint NULL, --Ba
	browsing enum_browsing NULL, --Biss
	tree_size_class enum_tree_size_class NULL, --Gr
	damage_peel smallint NULL, --Schael
	protection_individual boolean NULL, --Schu
	tree_count smallint NOT NULL --Anz
);

COMMENT ON TABLE regeneration IS 'Sub Plot Saplings';

COMMENT ON COLUMN regeneration.id IS 'Primary Key';
COMMENT ON COLUMN regeneration.plot_id IS 'Foreign Key to Plot.id';
COMMENT ON COLUMN regeneration.tree_species IS 'Baumart';
COMMENT ON COLUMN regeneration.browsing IS 'Einfacher oder mehrfacher Verbiss der Terminalknospe';
COMMENT ON COLUMN regeneration.tree_size_class IS 'Größenklasse';
COMMENT ON COLUMN regeneration.damage_peel IS 'Schälschaden';
COMMENT ON COLUMN regeneration.protection_individual IS 'Einzelschutz der Bäume';
COMMENT ON COLUMN regeneration.tree_count IS 'Anzahl gleichartiger Bäume';


ALTER TABLE regeneration ADD CONSTRAINT FK_Saplings2m_Plot FOREIGN KEY (plot_id) REFERENCES plot(id) MATCH SIMPLE
	ON DELETE CASCADE;

ALTER TABLE regeneration ADD CONSTRAINT FK_Saplings2m_LookupTreeSpecies FOREIGN KEY (tree_species)
    REFERENCES lookup_tree_species (abbreviation);

--- plot_location_id
--ALTER TABLE regeneration ADD CONSTRAINT FK_Saplings2m_PlotLocation FOREIGN KEY (plot_location_id)
--	REFERENCES plot_location (id)
--	ON DELETE CASCADE;

ALTER TABLE regeneration ADD CONSTRAINT FK_Saplings2m_LookupBrowsing FOREIGN KEY (browsing)
    REFERENCES lookup_browsing (abbreviation);

ALTER TABLE regeneration ADD CONSTRAINT FK_Saplings2m_LookupTreeSizeClass FOREIGN KEY (tree_size_class)
    REFERENCES lookup_tree_size_class (abbreviation);
