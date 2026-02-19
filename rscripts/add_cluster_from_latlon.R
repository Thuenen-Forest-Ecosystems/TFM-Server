# add_cluster_from_latlon.R
#
# Reads a CSV of cluster coordinates and calls
# inventory_archive.add_cluster_with_plots() for each row.
#
# Required environment variables:
#   DB_HOST      – database host
#   DB_PORT      – database port (default 54322 for local Supabase)
#   DB_NAME      – database name
#   DB_USER      – role with EXECUTE on the function (postgres)
#   DB_PASSWORD  – password for DB_USER
#
# CSV columns (required):
#   cluster_name, federal_state, longitude, latitude
# CSV columns (optional, leave blank / NA to use function defaults):
#   state_responsible, topo_map_sheet, grid_density,
#   cluster_status, cluster_situation, inspire_grid_cell,
#   is_training, interval_name, acquisition_date

library(DBI)
library(RPostgres)

# ---------------------------------------------------------------------------
# Load .env from the same directory as this script
# Works when called via Rscript or source()
# ---------------------------------------------------------------------------
local({
    script_dir <- tryCatch(
        {
            # Rscript: --file= is in commandArgs
            args <- commandArgs(trailingOnly = FALSE)
            file_arg <- grep("--file=", args, value = TRUE)
            if (length(file_arg)) {
                dirname(normalizePath(sub("--file=", "", file_arg)))
            } else {
                # source(): sys.frame ofile
                ofile <- sys.frame(1)$ofile
                if (!is.null(ofile) && nzchar(ofile)) dirname(normalizePath(ofile)) else getwd()
            }
        },
        error = function(e) getwd()
    )

    env_file <- file.path(script_dir, ".env")
    if (file.exists(env_file)) {
        readRenviron(env_file)
        message("[.env] loaded from: ", env_file)
    }
})

# ---------------------------------------------------------------------------
# connect_db
# ---------------------------------------------------------------------------
#' Open a DBI connection using environment variables
#'
#' Reads DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD.
#' Falls back to local Supabase defaults if variables are not set.
#'
#' @return A `DBIConnection` object
connect_db <- function() {
    DBI::dbConnect(
        RPostgres::Postgres(),
        host     = Sys.getenv("DB_HOST", "localhost"),
        port     = as.integer(Sys.getenv("DB_PORT", "54322")),
        dbname   = Sys.getenv("DB_NAME", "postgres"),
        user     = Sys.getenv("DB_USER", "postgres"),
        password = Sys.getenv("DB_PASSWORD", "postgres")
    )
}

# ---------------------------------------------------------------------------
# add_clusters_from_csv
# ---------------------------------------------------------------------------
#' Add clusters from a CSV file by calling a configurable SQL function
#'
#' Each row in the CSV becomes one cluster with 4 auto-generated plot corners
#' (150 m × 150 m square, SW corner given by longitude/latitude).
#'
#' @param csv_path     Path to the CSV file.
#' @param con          Optional existing `DBIConnection`. If NULL a new
#'                     connection is opened from environment variables and
#'                     closed on exit.
#' @param sql_function Fully-qualified SQL function to call, e.g.
#'                     `"inventory_archive.add_cluster_with_plots"`.
#' @param side_m       Side length of the cluster square in metres (default 150).
#' @param dry_run      If TRUE, print the SQL calls without executing them.
#'
#' @return A `data.frame` with all returned rows (4 per cluster), invisibly.
#' @export
add_clusters_from_csv <- function(csv_path,
                                  con = NULL,
                                  sql_function = "inventory_archive.add_cluster_with_plots",
                                  side_m = 150.0,
                                  dry_run = FALSE) {
    stopifnot(file.exists(csv_path))

    data <- read.csv(csv_path, stringsAsFactors = FALSE, na.strings = c("", "NA"))

    required_cols <- c("cluster_name", "federal_state", "longitude", "latitude")
    missing <- setdiff(required_cols, names(data))
    if (length(missing) > 0) {
        stop("CSV is missing required columns: ", paste(missing, collapse = ", "))
    }

    # Open connection if none supplied
    close_con <- FALSE
    if (is.null(con)) {
        con <- connect_db()
        close_con <- TRUE
    }
    on.exit(if (close_con) DBI::dbDisconnect(con), add = TRUE)

    results <- vector("list", nrow(data))

    for (i in seq_len(nrow(data))) {
        row <- data[i, ]

        # Build named parameter list; NULLify NA optionals
        coalesce_int <- function(x) if (is.na(x)) NA_integer_ else as.integer(x)
        coalesce_chr <- function(x) if (is.na(x)) NA_character_ else as.character(x)
        coalesce_bool <- function(x) if (is.na(x)) TRUE else as.logical(x)
        coalesce_date <- function(x) if (is.na(x)) NA_character_ else as.character(x)

        params <- list(
            p_cluster_name      = as.integer(row$cluster_name),
            p_federal_state     = as.integer(row$federal_state),
            p_longitude         = as.numeric(row$longitude),
            p_latitude          = as.numeric(row$latitude),
            p_state_responsible = coalesce_int(row[["state_responsible"]]),
            p_topo_map_sheet    = coalesce_int(row[["topo_map_sheet"]]),
            p_grid_density      = coalesce_int(row[["grid_density"]]),
            p_cluster_status    = coalesce_int(row[["cluster_status"]]),
            p_cluster_situation = coalesce_int(row[["cluster_situation"]]),
            p_inspire_grid_cell = coalesce_chr(row[["inspire_grid_cell"]]),
            p_is_training       = coalesce_bool(row[["is_training"]]),
            p_interval_name     = coalesce_chr(row[["interval_name"]]),
            p_acquisition_date  = coalesce_date(row[["acquisition_date"]]),
            p_side_m            = side_m
        )

        sql <- paste0(
            "SELECT * FROM ", sql_function, "(",
            "p_cluster_name      := $1,  ",
            "p_federal_state     := $2,  ",
            "p_longitude         := $3,  ",
            "p_latitude          := $4,  ",
            "p_state_responsible := $5,  ",
            "p_topo_map_sheet    := $6,  ",
            "p_grid_density      := $7,  ",
            "p_cluster_status    := $8,  ",
            "p_cluster_situation := $9,  ",
            "p_inspire_grid_cell := $10, ",
            "p_is_training       := $11, ",
            "p_interval_name     := $12, ",
            "p_acquisition_date  := $13::date, ",
            "p_side_m            := $14",
            ")"
        )

        if (dry_run) {
            cat(sprintf(
                "[dry_run] cluster_name=%d  lon=%.6f  lat=%.6f\n",
                params$p_cluster_name, params$p_longitude, params$p_latitude
            ))
            cat("  SQL:", sql, "\n")
            results[[i]] <- data.frame()
            next
        }

        tryCatch(
            {
                res <- DBI::dbGetQuery(con, sql, params = unname(params))
                results[[i]] <- res
                message(sprintf(
                    "[OK] cluster_name=%d  → %d plots inserted (cluster_id=%s)",
                    params$p_cluster_name, nrow(res),
                    if (nrow(res) > 0) as.character(res$out_cluster_id[[1]]) else "?"
                ))
            },
            error = function(e) {
                message(sprintf(
                    "[ERROR] cluster_name=%d : %s",
                    params$p_cluster_name, conditionMessage(e)
                ))
                results[[i]] <<- data.frame()
            }
        )
    }

    out <- do.call(rbind, results)
    invisible(out)
}

# ---------------------------------------------------------------------------
# Entry point — runs when sourced interactively or via Rscript
# ---------------------------------------------------------------------------
local({
    args <- commandArgs(trailingOnly = FALSE)
    file_arg <- grep("--file=", args, value = TRUE)
    script_dir <- if (length(file_arg)) {
        dirname(normalizePath(sub("--file=", "", file_arg)))
    } else {
        # source(): resolve from the call stack
        ofile <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
        if (!is.null(ofile) && nzchar(ofile)) dirname(normalizePath(ofile)) else getwd()
    }
    csv <- file.path(script_dir, ".data", "cluster_coordinates.csv")
    result <- add_clusters_from_csv(csv_path = csv)
    print(result)
})
