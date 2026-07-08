# Setup Records Guide

To set up the `records` table, run the following SQL commands in order. They populate
the records with plots, fill in current and previous properties, and deprecate trees
that are out of zone, dead, or harvested.

> **Tip:** Run these in pgAdmin or DBeaver rather than the Supabase SQL editor — some
> steps process in batches with `pg_sleep` pauses and can take several minutes.

## 1. Populate records with plots

```sql
SELECT public.add_plot_ids_to_records('[public.schemas.id]', 1000);
```

Inserts plots from `inventory_archive` into the `records` table. Filters plots by
`grid_density`, `federal_state`, `sampling_stratum`, and training status, and processes
them in batches (here, 1000 per batch) to avoid performance issues. Skips plots that are
already present, so it is safe to re-run. Replace `[public.schemas.id]` ( ‘Id’ field in the ‘schemas’ table in the ‘public’ schema ) with the target
schema UUID  ; the second argument is the batch size.

## 2. Fill previous properties

```sql
SELECT public.fill_previous_properties();
```

Fills `previous_properties`, `previous_position_data`, and `cluster` on records that have
not yet been processed (`previous_properties_updated_at IS NULL`). Records with an existing
timestamp are skipped. Processes in batches (default 200) with brief pauses to avoid I/O
saturation.

Optional arguments allow scoping and forcing a rewrite:

```sql
SELECT public.fill_previous_properties(1234);          -- only cluster 1234
SELECT public.fill_previous_properties(NULL, 500);     -- all records, batch size 500
SELECT public.fill_previous_properties(NULL, 200, TRUE); -- force-rewrite ALL records
```

## 3. Fill (preliminary) properties

```sql
SELECT public.fill_properties();
```

Fills `records.properties` with preliminary data from `inventory_archive` (`bwi2022`),
carrying forward trees and edges from the most recent inventory while clearing fields that
must be re-measured (e.g. `dbh`, `tree_height`). Only touches rows where
`preliminary_set_at IS NULL`; rows with a timestamp are skipped unless forced. Processes in
batches (default 200) with pauses to avoid I/O saturation.

Optional arguments mirror `fill_previous_properties`:

```sql
SELECT public.fill_properties(1234);              -- only cluster 1234
SELECT public.fill_properties(NULL, 500);         -- all records, batch size 500
SELECT public.fill_properties(NULL, 200, TRUE);   -- force-rewrite ALL records
```

## 4. Deprecate out-of-zone trees

```sql
SELECT public.deprecate_out_of_zone_trees();
```

Marks `_deprecated = true` on trees that were recorded outside their angle-count inclusion
zone in `bwi2012` (`distance > dbh * 25 / 10`) and never re-appeared in `ci2017` or `bwi2022`,
where the current record entry still has `dbh = null` and the cluster is not a test cluster
(`cluster_name < 9999900`). Defaults to federal state `12` (Brandenburg); pass another state
code as the first argument.

Preview the affected trees before running, or do a dry run that only counts:

```sql
SELECT * FROM public.deprecate_out_of_zone_trees_preview(12);
SELECT public.deprecate_out_of_zone_trees(12, TRUE);  -- dry run, returns count only
```

## 5. Deprecate dead trees

```sql
SELECT public.deprecate_dead_trees();
```

Marks `_deprecated = true` on trees with `tree_status` 4 or 5 (dead) from the `bwi2012` and
`ci2017` inventories, where the current record entry still has `dbh = null` and the cluster
is not a test cluster (`cluster_name < 9999900`).

Preview or dry-run:

```sql
SELECT * FROM public.deprecate_dead_trees_preview();
SELECT public.deprecate_dead_trees(TRUE);  -- dry run, returns count only
```

## 6. Deprecate harvested trees

```sql
SELECT public.deprecate_harvested_trees();
```

Marks `_deprecated = true` on trees with `tree_status` 2002, 2008, 2012, or 2017 (harvested),
where the current record entry still has `dbh = null` and the cluster is not a test cluster
(`cluster_name < 9999900`).

Preview or dry-run:

```sql
SELECT * FROM public.deprecate_harvested_trees_preview();
SELECT public.deprecate_harvested_trees(TRUE);  -- dry run, returns count only
```
