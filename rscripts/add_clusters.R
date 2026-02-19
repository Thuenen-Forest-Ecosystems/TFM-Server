#' Get column names of database table
#'
#' @param con A `DBIConncetion` object
#' @param table_name  A `string` with the table name
#'
#' @returns A `data.frame` with the column names
#' @export
#'
#' @examples
get_column_names <- function(con, table_name) {
  stopifnot(is.character(table_name))
  query <- paste0("select column_name from information_schema.columns where table_name = '",
                 table_name, "'")
  return(dbGetQuery(con, query))
}

#' Insert inventory clusters for training purposes
#' Intended only for database of Germany's national forest inventory
#'
#' @param con A `DBIConncetion` object
#' @param data A `data.frame` object with the data to be inserted
#'
#' @details
#' Column names in data need to match inventory_archive.cluster. Required are
#' `intkey`, `cluster_name` and `is_training`.
#' 
#' @returns Rows affected
#' @export
#'
#' @examples
insert_training_cluster <- function(con, data) {
  names_db <- get_column_names(con, "cluster")
  stopifnot("data has columns that do not exist in the target table (inventory_archive.cluster)" = length(setdiff(names(data), names_db[, 1])) == 0)
  stopifnot("either of colums intkey, cluster_name, is_training missing" = length(setdiff(c('intkey', 'cluster_name', 'is_training'), names(data)) == 0))
  setdiff(names_db[, 1], names_data)
  
  stopifnot(is.integer(data$cluster_name), 
            all(is.finite(data$cluster_name)), 
            all(data$cluster_name >= 1e+09))
  stopifnot(is.logical(data$is_training), 
            all(data$is_training == TRUE))
  stopifnot('intkey' %in% names(data))
  stopifnot('cluster_name' %in% names(data))
  stopifnot('is_training' %in% names(data))
  
  query = paste0('INSERT INTO inventory_archive.cluster (', 
                 paste0(colnames(data),
                        collapse = ','),
                 ') VALUES')
  conflict = "on conflict (intkey) do nothing;"
  vals = NULL
  for (i in 1:nrow(data)) {
    vals[i] = paste0('(', paste0(data[i, ], collapse = ','), ')')
  }
  query = paste0(query, paste0(vals, collapse=','), 
                 ' ',
                 conflict)
  DBI::dbExecute(con, query)
}
