repo_root <- function() {
  getOption(
    "netballstats.repo_root",
    normalizePath(file.path(getwd()), mustWork = FALSE)
  )
}

default_db_path <- function() {
  default_sqlite_db_path(repo_root())
}

open_db <- function() {
  open_database_connection(default_db_path(), require_existing_sqlite = TRUE)
}

json_error <- function(res, status, message) {
  res$status <- status
  list(error = message)
}

parse_optional_int <- function(value, name, minimum = NULL, maximum = NULL) {
  if (is.null(value) || !nzchar(value)) {
    return(NULL)
  }

  if (!grepl("^[0-9]+$", value)) {
    stop(name, " must contain digits only.", call. = FALSE)
  }

  parsed <- as.integer(value)
  if (!is.null(minimum) && parsed < minimum) {
    stop(name, " must be at least ", minimum, ".", call. = FALSE)
  }
  if (!is.null(maximum) && parsed > maximum) {
    stop(name, " must be at most ", maximum, ".", call. = FALSE)
  }

  parsed
}

parse_limit <- function(value, default = 20L, maximum = 100L) {
  if (is.null(value) || !nzchar(value)) {
    return(default)
  }

  parsed <- parse_optional_int(value, "limit", minimum = 1L, maximum = maximum)
  parsed %||% default
}

parse_search <- function(value, name = "search", max_length = 80L) {
  if (is.null(value) || !nzchar(trimws(value))) {
    return(NULL)
  }

  trimmed <- trimws(value)
  if (nchar(trimmed) > max_length) {
    stop(name, " must be ", max_length, " characters or fewer.", call. = FALSE)
  }

  if (grepl("[^A-Za-z0-9 .'-]", trimmed)) {
    stop(name, " contains unsupported characters.", call. = FALSE)
  }
  if (!grepl("[A-Za-z0-9]", trimmed)) {
    stop(name, " must include at least one letter or digit.", call. = FALSE)
  }

  trimmed
}

normalize_player_search_name <- function(value) {
  if (is.null(value)) {
    return(NULL)
  }

  normalized <- iconv(as.character(value), to = "ASCII//TRANSLIT")
  normalized[is.na(normalized)] <- as.character(value)[is.na(normalized)]
  normalized <- tolower(normalized)
  normalized <- gsub("[^a-z0-9]+", "", normalized)
  normalized
}

sql_interpolate_safe <- function(conn, query, params = list()) {
  do.call(DBI::sqlInterpolate, c(list(conn, query), params))
}

query_rows <- function(conn, query, params = list()) {
  DBI::dbGetQuery(conn, sql_interpolate_safe(conn, query, params))
}

apply_match_filters <- function(query, params, season = NULL, team_id = NULL, round_number = NULL) {
  if (!is.null(season)) {
    query <- paste0(query, " AND season = ?season")
    params$season <- season
  }
  if (!is.null(team_id)) {
    query <- paste0(query, " AND (home_squad_id = ?team_id OR away_squad_id = ?team_id)")
    params$team_id <- team_id
  }
  if (!is.null(round_number)) {
    query <- paste0(query, " AND round_number = ?round_number")
    params$round_number <- round_number
  }

  list(query = query, params = params)
}

apply_stat_filters <- function(query, params, season = NULL, team_id = NULL, round_number = NULL) {
  if (!is.null(season)) {
    query <- paste0(query, " AND season = ?season")
    params$season <- season
  }
  if (!is.null(team_id)) {
    query <- paste0(query, " AND squad_id = ?team_id")
    params$team_id <- team_id
  }
  if (!is.null(round_number)) {
    query <- paste0(query, " AND round_number = ?round_number")
    params$round_number <- round_number
  }

  list(query = query, params = params)
}

available_stats <- function(conn, table_name) {
  query_rows(
    conn,
    sprintf(
      "SELECT DISTINCT stat FROM %s WHERE value_number IS NOT NULL ORDER BY stat",
      table_name
    )
  )$stat
}

validate_stat <- function(conn, table_name, stat, default_stat = "goals") {
  stats <- available_stats(conn, table_name)
  if (!length(stats)) {
    stop("No numeric stats are available in ", table_name, ".", call. = FALSE)
  }

  chosen <- stat %||% default_stat
  if (!chosen %in% stats) {
    stop("Unsupported stat: ", chosen, ".", call. = FALSE)
  }

  chosen
}

allowed_origins <- function() {
  value <- Sys.getenv(
    "NETBALL_STATS_ALLOWED_ORIGINS",
    "http://127.0.0.1:4173,http://localhost:4173"
  )
  unique(trimws(strsplit(value, ",", fixed = TRUE)[[1]]))
}
