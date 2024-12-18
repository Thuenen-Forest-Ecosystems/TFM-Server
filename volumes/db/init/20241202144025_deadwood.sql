SET search_path TO private_ci2027_001;

CREATE TABLE deadwood (

	intkey varchar(12) UNIQUE NULL,

    id uuid UNIQUE DEFAULT gen_random_uuid() PRIMARY KEY,
    plot_id uuid NOT NULL,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
	modified_at TIMESTAMP DEFAULT NULL,
    modified_by uuid DEFAULT auth.uid() NOT NULL,

	tree_species_group enum_tree_species_group NULL, -- Tbagr
	dead_wood_type enum_dead_wood_type NULL, -- Tart
	decomposition enum_decomposition NULL, -- Tzg
	length_height smallint NULL, -- Tl

	diameter_butt CK_BHD_DEADWOOD_BUTT NOT NULL, -- Tbd
	diameter_top CK_BHD_DEADWOOD_TOP NULL, -- Tsd

	count smallint NULL, -- Anz
	bark_pocket smallint NULL -- TRinde
);


COMMENT ON TABLE deadwood IS 'Deadwood';
COMMENT ON COLUMN deadwood.id IS 'Primary Key';
COMMENT ON COLUMN deadwood.plot_id IS 'Foreign Key to plot';

COMMENT ON COLUMN deadwood.tree_species_group IS 'Baumartengruppe für Totholz';
COMMENT ON COLUMN deadwood.dead_wood_type IS 'Todholztyp';
COMMENT ON COLUMN deadwood.decomposition IS 'Zersetzungsgrad';
COMMENT ON COLUMN deadwood.length_height IS 'Länge / Höhe Totholz [dm]';
COMMENT ON COLUMN deadwood.diameter_butt IS 'Durchmesser am dicken Ende [cm] (liegende Bruchstücke); Schnittflächen- (Stöcke), Bhd (mit Wurzel, >=130 cm Länge)';
COMMENT ON COLUMN deadwood.diameter_top IS 'Durchmesser am dünnen Ende [cm] (nur bei liegenden Totholz OHNE Wurzelanlauf)';
COMMENT ON COLUMN deadwood.count IS 'Anzahl gleichartiger Totholzstücke';
COMMENT ON COLUMN deadwood.bark_pocket IS 'Rindentaschen > 500 cm² mit einer Mindestbreite von 10 cm (nur für stehendes Totholz)';

ALTER TABLE deadwood ADD CONSTRAINT FK_Deadwood_Plot FOREIGN KEY (plot_id)
	REFERENCES plot (id)
	ON DELETE CASCADE;

--- plot_location_id
--ALTER TABLE deadwood ADD CONSTRAINT FK_Deadwood_PlotLocation FOREIGN KEY (plot_location_id)
--	REFERENCES plot_location (id);


ALTER TABLE deadwood ADD CONSTRAINT FK_Deadwood_LookupTreeSpeciesGroup FOREIGN KEY (tree_species_group)
	REFERENCES lookup_tree_species_group (abbreviation);

ALTER TABLE deadwood ADD CONSTRAINT FK_Deadwood_LookupDeadWoodType FOREIGN KEY (dead_wood_type)
	REFERENCES lookup_dead_wood_type (abbreviation);

ALTER TABLE deadwood ADD CONSTRAINT FK_Deadwood_LookupDecomposition FOREIGN KEY (decomposition)
	REFERENCES lookup_decomposition (abbreviation);