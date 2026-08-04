# Dataflow: `inventory_archive` → `derived`

This document describes how raw inventory data in `inventory_archive` is transformed into computed derived variables in the `derived` schema. The pipeline uses a two-phase approach: **PostgreSQL triggers** for instant, formula-based calculations and the **R-Server** for complex BDAT-dependent computations.

## Architecture Overview

```
┌──────────────────────────┐
│  inventory_archive.tree  │
│  inventory_archive.      │
│    deadwood              │
│  inventory_archive.      │
│    regeneration          │
└──────────┬───────────────┘
           │ INSERT / UPDATE
           ▼
┌──────────────────────────┐
│  PG Triggers             │
│  (instant, per-row)      │
│  • simple formulas       │
│  • needs_r_calculation   │
│  • pg_notify(...)        │
└──────────┬───────────────┘
           │ NOTIFY
           ▼
┌──────────────────────────┐     GET /run-script/<name>
│  r-derived-listener      │ ──────────────────────────► ┌─────────────────┐
│  (pg_notify_listener.R)  │                              │  r-plumber API  │
│  • debounce 2s           │ ◄─────────────────────────── │  (start.R)      │
│  • drain until 0 rows    │      { rows_updated: N }     │  port 7005      │
└──────────────────────────┘                              └────────┬────────┘
                                                                   │
                                                                   ▼
                                                          ┌─────────────────┐
                                                          │  R Scripts      │
                                                          │  tree_derived.R │
                                                          │  deadwood.R     │
                                                          └────────┬────────┘
                                                                   │ UPSERT
                                                                   ▼
                                                          ┌─────────────────┐
                                                          │  derived.tree   │
                                                          │  derived.       │
                                                          │    deadwood     │
                                                          │  derived.       │
                                                          │    regeneration │
                                                          └─────────────────┘
```

---

## Phase 1: PostgreSQL Triggers (instant)

When a row is inserted or updated in `inventory_archive`, a trigger fires immediately and computes all formula-based values. These are written to the corresponding `derived.*` table via upsert.

### Trees (`derived.on_tree_change`)

**Trigger fires on:** `INSERT` or `UPDATE` of `dbh`, `tree_height`, `stem_height`, `tree_species`, `stem_breakage`, `stem_form`, `within_stand`

| Computed column        | Formula                                                    |
| ---------------------- | ---------------------------------------------------------- |
| `basal_area`           | π/4 × (BHD/1000)² [m²]                                     |
| `trees_per_hectare`    | 10000 / (π × (BHD/1000 × √(2500/BAF))²), BAF = 4           |
| `below_ground_biomass` | a × BHD^b, coefficients by species group (FI/KI/BU/EI/ALN) |

Sets `needs_r_calculation = true` and sends `pg_notify('derived_tree_changed', ...)`.

### Deadwood (`derived.on_deadwood_change`)

**Trigger fires on:** `INSERT` or `UPDATE` of `diameter_butt`, `diameter_top`, `length_height`, `tree_species_group`, `dead_wood_type`

| Computed column   | Formula                                                                   |
| ----------------- | ------------------------------------------------------------------------- |
| `volume`          | Truncated cone: π × l/12 × (d₁² + d₁·d₂ + d₂²), or cylinder: π/4 × d² × l |
| `volume_with_top` | Same as `volume` for types 4, 5, 13; `NULL` for BDAT types 2, 3, 11, 12   |
| `biomass`         | volume × k_biom_tot factor (by species group × decomposition stage)       |

Sets `needs_r_calculation = true` and sends `pg_notify('derived_deadwood_changed', ...)`.

### Regeneration (`derived.on_regeneration_change`)

**Trigger fires on:** `INSERT` or `UPDATE` of `tree_species`, `tree_size_class`, `tree_count`

All values are fully computable in PostgreSQL using lookup tables — **no R-Server needed**.

| Computed column        | Source                                                           |
| ---------------------- | ---------------------------------------------------------------- |
| `dbh`                  | Mean BHD from `x_gr_lookup(tree_size_class)` [mm]                |
| `trees_per_hectare`    | tree_count × 10000 / (π × 4), fixed 2m-radius circle             |
| `basal_area`           | π/4 × (mw_bhd/1000)² [m²]                                        |
| `below_ground_biomass` | a × Bio_uBhd^b, using bio_u_bhd from x_gr lookup                 |
| `above_ground_biomass` | k1 model (height-only, BHD=0) or k2 model (small tree, BHD<10cm) |
| `volume_fao`           | `k_vol_bhd_u7(babwi, mw_bhd)` lookup for BHD < 70mm              |

Sets `needs_r_calculation = false` and sends `pg_notify('derived_regeneration_changed', ...)`.

---

## Phase 2: R-Server (asynchronous, BDAT-dependent)

The R-Server runs as two Docker containers sharing the `supabase-net` network:

| Service              | Role                                                     |
| -------------------- | -------------------------------------------------------- |
| `r-plumber`          | Plumber API on port 7005, executes R calculation scripts |
| `r-derived-listener` | Listens for `pg_notify` events, calls the API to process |

### Listener Flow (`pg_notify_listener.R`)

1. Subscribes to three PostgreSQL channels: `derived_tree_changed`, `derived_deadwood_changed`, `derived_regeneration_changed`
2. Polls for notifications every 1 second
3. Accumulates notifications with a **2-second debounce** (waits 2s after the last notification before triggering)
4. Calls the R API and **drains** — repeats the call until `rows_updated = 0` to handle batches > 10 000 rows

| Channel                        | API call                       |
| ------------------------------ | ------------------------------ |
| `derived_tree_changed`         | `GET /run-script/tree_derived` |
| `derived_deadwood_changed`     | `GET /run-script/deadwood`     |
| `derived_regeneration_changed` | `GET /run-script/tree_derived` |

On connection error, the listener waits 5 seconds, reconnects, and re-subscribes.

### API Authentication

All `/run-script/<name>` calls require a Bearer token in the `Authorization` header. The token is validated against `SUPABASE_SERVICE_ROLE_TOKEN` (service role bypass) or via the Supabase Auth API.

---

### `tree_derived.R` — Tree Calculations

**Input query:** Fetches up to 10 000 trees where `derived.tree.needs_r_calculation = true`.

| Computed column        | Method                                                   | Source      |
| ---------------------- | -------------------------------------------------------- | ----------- |
| `diameter_30perc`      | Shaft curve at 30% of tree height                        | rBDAT       |
| `diameter_7m`          | Shaft curve at 7m height (NULL if tree < 7m)             | rBDAT       |
| `volume_fao`           | Coarse wood volume with bark (Derbholz, stump → 7cm tip) | rBDAT       |
| `volume_harvest`       | Sum of assortment volumes without bark                   | rBDAT       |
| `above_ground_biomass` | Biomass model using species group, BHD, height, and D30  | bwi.derived |
| `growing_space`        | Raw Stf from model, then normalized per plot             | bwi.derived |

**Growing space normalization:**

1. Fetch ALL trees on the affected plots (not just pending ones)
2. Compute per-plot correction: `korr = 10000 / Σ(N_ha × Stf)`
3. Apply: `StfM = korr × Stf`
4. Trees with `within_stand = false` get `trees_per_hectare = 0`

**Species mapping:** BWI codes (10–299, 900-series) → rBDAT codes (1–36). Unmappable codes are skipped.

**Batch upsert:** 500 rows per INSERT, `ON CONFLICT (tree_id) DO UPDATE`, sets `needs_r_calculation = false`.

---

### `deadwood.R` — Deadwood Calculations

**Input query:** Fetches up to 10 000 deadwood rows where `derived.deadwood.needs_r_calculation = true`.

| Computed column   | Method                                                    |
| ----------------- | --------------------------------------------------------- |
| `volume_with_top` | Full tree volume including theoretical top for BDAT types |

**rBDAT applied to:** Types 2 (standing dead), 3 (snag), 11 (lying whole), 12 (butt section) — only when diameter ≥ 10cm and length ≥ 30cm.

**Species mapping for BDAT:**

- TBagr 1 (conifers) → Fichte (rBDAT code 1)
- TBagr 2 (broadleaves excl. oak) → Buche (rBDAT code 15)
- TBagr 3 (oak) → Eiche (rBDAT code 17)

**Upsert:** `ON CONFLICT (deadwood_id) DO UPDATE`, sets `needs_r_calculation = false`.

---

## Backfill Functions

For bulk (re-)computation of all derived rows, three SQL functions are available. They use `ON CONFLICT DO UPDATE` so they can be safely re-run to fix stale or incomplete data.

| Function                          | Computes in PG                  | R-Server needed | `needs_r_calculation` |
| --------------------------------- | ------------------------------- | --------------- | --------------------- |
| `derived.backfill_trees()`        | basal_area, N_ha, biom_u        | Yes             | `true`                |
| `derived.backfill_deadwood()`     | volume, vol_with_top\*, biomass | Yes             | `true`                |
| `derived.backfill_regeneration()` | All columns                     | No              | `false`               |

\* `volume_with_top` is set only for non-BDAT types; BDAT types remain NULL until R processes them.

**Run all at once:**

```sql
SELECT * FROM derived.backfill_all();
-- Returns: trees | deadwood | regeneration (row counts)
```

Each backfill function sends a `pg_notify` after completion, which triggers the R-Server listener to process the `needs_r_calculation = true` rows.

---

## Derived Schema Tables

### `derived.tree`

| Column                 | Type     | Source          | Description                                 |
| ---------------------- | -------- | --------------- | ------------------------------------------- |
| `tree_id`              | uuid     | FK → tree       | References `inventory_archive.tree(id)`     |
| `intkey`               | varchar  | PG trigger      | Composite key from source                   |
| `dbh`                  | smallint | PG trigger      | Diameter at breast height [mm]              |
| `tree_height`          | smallint | PG trigger      | Total tree height [dm]                      |
| `stem_height`          | smallint | PG trigger      | Height to first branch [dm]                 |
| `basal_area`           | real     | PG trigger      | Cross-sectional area [m²]                   |
| `trees_per_hectare`    | real     | PG trigger      | Stems per hectare (angle-count, BAF=4)      |
| `below_ground_biomass` | real     | PG trigger      | Root biomass [kg]                           |
| `diameter_30perc`      | smallint | R (rBDAT)       | Diameter at 30% height [mm]                 |
| `diameter_7m`          | smallint | R (rBDAT)       | Diameter at 7m [mm]                         |
| `volume_fao`           | real     | R (rBDAT)       | Coarse wood volume with bark [m³]           |
| `volume_harvest`       | real     | R (rBDAT)       | Assortment volume without bark [m³]         |
| `above_ground_biomass` | real     | R (bwi.derived) | Aboveground dry biomass [kg]                |
| `growing_space`        | real     | R (bwi.derived) | Normalized growing space [m²]               |
| `needs_r_calculation`  | boolean  | PG / R          | `true` until R-Server has processed the row |

### `derived.deadwood`

| Column                | Type    | Source        | Description                                 |
| --------------------- | ------- | ------------- | ------------------------------------------- |
| `deadwood_id`         | uuid    | FK → deadwood | References `inventory_archive.deadwood(id)` |
| `intkey`              | varchar | PG trigger    | Composite key from source                   |
| `volume`              | real    | PG trigger    | Cylinder or truncated cone volume [m³]      |
| `volume_with_top`     | real    | PG / R        | Full volume incl. theoretical top [m³]      |
| `biomass`             | real    | PG trigger    | volume × decomposition factor [kg]          |
| `needs_r_calculation` | boolean | PG / R        | `true` until R-Server has processed         |

### `derived.regeneration`

| Column                 | Type     | Source     | Description                                     |
| ---------------------- | -------- | ---------- | ----------------------------------------------- |
| `regeneration_id`      | uuid     | FK → regen | References `inventory_archive.regeneration(id)` |
| `intkey`               | varchar  | PG trigger | Composite key from source                       |
| `dbh`                  | smallint | PG trigger | Mean BHD from x_gr lookup [mm]                  |
| `trees_per_hectare`    | real     | PG trigger | count × 10000 / (π × 4)                         |
| `basal_area`           | real     | PG trigger | π/4 × (mw_bhd/1000)² [m²]                       |
| `volume_fao`           | real     | PG trigger | From k_VolBhdU7 lookup [m³]                     |
| `above_ground_biomass` | real     | PG trigger | k1/k2 biomass model [kg]                        |
| `below_ground_biomass` | real     | PG trigger | a × BHD^b [kg]                                  |
| `needs_r_calculation`  | boolean  | PG trigger | Always `false` (fully computed in PG)           |

---

## Helper Functions

| Function                                                           | Returns | Description                                   |
| ------------------------------------------------------------------ | ------- | --------------------------------------------- |
| `derived.calc_basal_area(dbh_mm)`                                  | real    | π/4 × (BHD/1000)² [m²]                        |
| `derived.calc_trees_per_hectare(dbh_mm, baf)`                      | real    | Angle-count N/ha, default BAF = 4             |
| `derived.calc_below_ground_biomass(species, dbh_mm)`               | real    | a × BHD^b, coefficients by species group      |
| `derived.calc_deadwood_biomass(species_grp, decomp, vol)`          | real    | vol × k_biom_tot factor [kg]                  |
| `derived.calc_above_ground_biomass_regen(species, bhd_mm, hoe_dm)` | real    | k1 or k2 model for BHD < 100mm                |
| `derived.x_gr_lookup(size_class)`                                  | record  | Mean BHD/height per regeneration size class   |
| `derived.species_to_babwi(species)`                                | integer | BWI species → BaBWI group (1–9)               |
| `derived.species_to_biomass_group(species)`                        | text    | BWI species → biomass group (FI/KI/BU/EI/ALN) |
| `derived.k_vol_bhd_u7(babwi, bhd_mm)`                              | real    | Volume for BHD < 70mm from lookup table [m³]  |
