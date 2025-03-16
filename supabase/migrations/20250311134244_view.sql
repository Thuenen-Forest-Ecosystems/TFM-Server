
DROP VIEW IF EXISTS public.plot_nested_json;

CREATE VIEW public.plot_nested_json AS
SELECT
    plot.*,
    
    -- Use COALESCE to return an empty array ('[]'::json) if no rows are found
    COALESCE(
        (
            SELECT json_agg(row_to_json(tree.*))
            FROM inventory_archive.tree
            WHERE tree.plot_id = plot.id
        ),
        '[]'::json
    ) AS trees,
    
    COALESCE(
        (
            SELECT json_agg(row_to_json(deadwood.*))
            FROM inventory_archive.deadwood
            WHERE deadwood.plot_id = plot.id
        ),
        '[]'::json
    ) AS deadwoods,
    
    COALESCE(
        (
            SELECT json_agg(row_to_json(regeneration.*))
            FROM inventory_archive.regeneration
            WHERE regeneration.plot_id = plot.id
        ),
        '[]'::json
    ) AS regenerations,
    
    COALESCE(
        (
            SELECT json_agg(row_to_json(structure_lt4m.*))
            FROM inventory_archive.structure_lt4m
            WHERE structure_lt4m.plot_id = plot.id
        ),
        '[]'::json
    ) AS structures_lt4m,
    
    COALESCE(
        (
            SELECT json_agg(row_to_json(edges.*))
            FROM inventory_archive.edges
            WHERE edges.plot_id = plot.id
        ),
        '[]'::json
    ) AS edges
        
FROM inventory_archive.plot
WHERE EXISTS (
    SELECT 1
    FROM public.troop tp
    WHERE tp.id = (auth.jwt() ->> 'troop_id'::text)::uuid
    AND tp.plot_ids @> ARRAY[plot.id]
);