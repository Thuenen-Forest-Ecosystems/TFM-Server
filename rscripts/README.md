# rscripts

R utilities for importing cluster and plot data into the `inventory_archive` schema.

---

## Prerequisites

| Requirement | Version |
| ----------- | ------- |
| R           | ≥ 4.1   |
| `DBI`       | CRAN    |
| `RPostgres` | CRAN    |

Install once:

```r
install.packages(c("DBI", "RPostgres"))
```

---

## Configuration

Create a `.env` file in this directory (see `.env.example`):

```dotenv
DB_HOST=localhost
DB_PORT=54322
DB_NAME=postgres
DB_USER=postgres
DB_PASSWORD=postgres
```

The file is loaded automatically when the script starts. Environment variables already set in the shell take precedence.

---

## `add_cluster_from_latlon.R`

Reads a CSV of cluster SW-corner coordinates and calls
`inventory_archive.add_cluster_with_plots()` for each row.  
Each cluster generates **4 plot corners** arranged as a 150 m × 150 m square.

### CSV format

Place the file at `.data/cluster_coordinates.csv` (default path) or pass any path explicitly.

| Column              | Type    | Required | Description                               |
| ------------------- | ------- | -------- | ----------------------------------------- |
| `cluster_name`      | integer | ✓        | Unique cluster identifier                 |
| `federal_state`     | integer | ✓        | Federal state code                        |
| `longitude`         | numeric | ✓        | SW-corner longitude (WGS 84)              |
| `latitude`          | numeric | ✓        | SW-corner latitude (WGS 84)               |
| `state_responsible` | integer |          | State responsible code                    |
| `topo_map_sheet`    | integer |          | Topographic map sheet number              |
| `grid_density`      | integer |          | Grid density code                         |
| `cluster_status`    | integer |          | Cluster status code                       |
| `cluster_situation` | integer |          | Cluster situation code                    |
| `inspire_grid_cell` | string  |          | INSPIRE grid cell identifier              |
| `is_training`       | boolean |          | Mark as training cluster (default `TRUE`) |
| `interval_name`     | string  |          | Inventory interval name                   |
| `acquisition_date`  | date    |          | Acquisition date (`YYYY-MM-DD`)           |

Example:

```csv
cluster_name,federal_state,longitude,latitude,state_responsible,grid_density,cluster_status,cluster_situation,is_training
1000000000,3,9.389,51.174,3,0,2,4,TRUE
1000000001,3,9.593,51.577,3,0,2,4,TRUE
```

Optional columns may be omitted entirely or left blank — they fall back to the SQL function defaults.

### Usage

#### Via `Rscript` (command line)

```bash
Rscript add_cluster_from_latlon.R
```

This reads `.data/cluster_coordinates.csv` relative to the script location.

#### As a library function

```r
source("add_cluster_from_latlon.R")

result <- add_clusters_from_csv(
  csv_path    = "path/to/my_clusters.csv",
  side_m      = 150.0,   # cluster square size in metres (default 150)
  dry_run     = FALSE    # set TRUE to preview SQL without executing
)

# result is a data.frame with one row per inserted plot (4 per cluster)
print(result)
```

#### Dry-run (preview only)

```r
add_clusters_from_csv("path/to/clusters.csv", dry_run = TRUE)
```

Prints the resolved SQL for every row without touching the database.

#### Re-use an existing connection

```r
library(DBI)
library(RPostgres)

con <- DBI::dbConnect(
  RPostgres::Postgres(),
  host = "localhost", port = 54322,
  dbname = "postgres", user = "postgres", password = "postgres"
)

result <- add_clusters_from_csv("clusters.csv", con = con)

DBI::dbDisconnect(con)
```

### Return value

A `data.frame` with all rows returned by the SQL function (typically 4 rows per cluster):

| Column              | Description                        |
| ------------------- | ---------------------------------- |
| `out_cluster_id`    | Generated UUID of the cluster      |
| `out_plot_id`       | Generated UUID of each plot        |
| `out_plot_position` | Plot corner label (SW, NW, NE, SE) |

---

## `add_clusters.R`

Lower-level helpers for direct table inserts.

### `get_column_names(con, table_name)`

Returns the column names of a database table as a `data.frame`.

```r
cols <- get_column_names(con, "cluster")
```

### `insert_training_cluster(con, data)`

Bulk-inserts training clusters directly into `inventory_archive.cluster`.

- `data` must be a `data.frame` whose column names exactly match `inventory_archive.cluster`.
- Required columns: `intkey`, `cluster_name`, `is_training`.
- `cluster_name` must be a 10-digit integer (≥ 1 000 000 000).
- `is_training` must be `TRUE` for all rows.
- Uses `ON CONFLICT (intkey) DO NOTHING` — safe to re-run.

```r
source("add_clusters.R")

library(DBI)
library(RPostgres)

con <- DBI::dbConnect(RPostgres::Postgres(),
  host = "localhost", port = 54322,
  dbname = "postgres", user = "postgres", password = "postgres"
)

rows_affected <- insert_training_cluster(con, my_data_frame)
DBI::dbDisconnect(con)
```

---

## Error handling

Both scripts emit `[OK]` / `[ERROR]` messages per row to the console.  
A failed row does not abort processing — subsequent rows are still attempted.  
Check the console output and the return value for any `data.frame()` (empty) entries that signal failures.
