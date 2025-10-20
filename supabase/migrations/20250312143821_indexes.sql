DROP INDEX IF EXISTS idx_plot_id;
CREATE INDEX IF NOT EXISTS idx_plot_id ON inventory_archive.plot (id);

DROP INDEX IF EXISTS idx_plot_coordinates_plot_id;
CREATE INDEX IF NOT EXISTS idx_plot_coordinates_plot_id ON inventory_archive.plot_coordinates (plot_id);

DROP INDEX IF EXISTS idx_plot_interval_name;
CREATE INDEX IF NOT EXISTS idx_plot_interval_name ON inventory_archive.plot (interval_name);

DROP INDEX IF EXISTS idx_tree_plot_id;
CREATE INDEX IF NOT EXISTS idx_tree_plot_id ON inventory_archive.tree (plot_id);

DROP INDEX IF EXISTS idx_deadwood_plot_id;
CREATE INDEX IF NOT EXISTS idx_deadwood_plot_id ON inventory_archive.deadwood (plot_id);

DROP INDEX IF EXISTS idx_regeneration_plot_id;
CREATE INDEX IF NOT EXISTS idx_regeneration_plot_id ON inventory_archive.regeneration (plot_id);

DROP INDEX IF EXISTS idx_structure_lt4m_plot_id;
CREATE INDEX IF NOT EXISTS idx_structure_lt4m_plot_id ON inventory_archive.structure_lt4m (plot_id);

DROP INDEX IF EXISTS idx_edges_plot_id;
CREATE INDEX IF NOT EXISTS idx_edges_plot_id ON inventory_archive.edges (plot_id);

DROP INDEX IF EXISTS idx_structure_gt4m_plot_id;
CREATE INDEX IF NOT EXISTS idx_structure_gt4m_plot_id ON inventory_archive.structure_gt4m (plot_id);

DROP INDEX IF EXISTS idx_plot_landmark_plot_id;
CREATE INDEX IF NOT EXISTS idx_plot_landmark_plot_id ON inventory_archive.plot_landmark (plot_id);

DROP INDEX IF EXISTS idx_position_plot_id;
CREATE INDEX IF NOT EXISTS idx_position_plot_id ON inventory_archive.position (plot_id);