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

parse_optional_int_vector <- function(value, name, minimum = NULL, maximum = NULL, max_items = 20L) {
  if (is.null(value) || !nzchar(trimws(value))) {
    return(NULL)
  }

  parts <- trimws(strsplit(value, ",", fixed = TRUE)[[1]])
  parts <- parts[nzchar(parts)]
  if (!length(parts)) {
    return(NULL)
  }
  if (length(parts) > max_items) {
    stop(name, " must contain ", max_items, " values or fewer.", call. = FALSE)
  }

  parsed <- vapply(
    parts,
    parse_optional_int,
    integer(1),
    name = name,
    minimum = minimum,
    maximum = maximum
  )
  unique(parsed)
}

parse_season_filter <- function(season = "", seasons = "") {
  parsed_seasons <- parse_optional_int_vector(
    seasons,
    "seasons",
    minimum = 2017L,
    maximum = 2100L,
    max_items = 20L
  )
  if (!is.null(parsed_seasons)) {
    return(parsed_seasons)
  }

  parsed_season <- parse_optional_int(season, "season", minimum = 2017L, maximum = 2100L)
  if (is.null(parsed_season)) {
    return(NULL)
  }

  c(parsed_season)
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

append_integer_in_filter <- function(query, params, column_name, values, prefix) {
  if (is.null(values) || !length(values)) {
    return(list(query = query, params = params))
  }

  placeholders <- character(length(values))
  for (index in seq_along(values)) {
    key <- sprintf("%s_%s", prefix, index)
    placeholders[[index]] <- paste0("?", key)
    params[[key]] <- values[[index]]
  }

  list(
    query = paste0(query, " AND ", column_name, " IN (", paste(placeholders, collapse = ", "), ")"),
    params = params
  )
}

apply_match_filters <- function(query, params, seasons = NULL, team_id = NULL, round_number = NULL) {
  season_filter <- append_integer_in_filter(query, params, "season", seasons, "season")
  query <- season_filter$query
  params <- season_filter$params

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

apply_stat_filters <- function(query, params, seasons = NULL, team_id = NULL, round_number = NULL, table_alias = NULL) {
  qualify_column <- function(column_name) {
    if (is.null(table_alias) || !nzchar(table_alias)) {
      return(column_name)
    }

    paste0(table_alias, ".", column_name)
  }

  season_filter <- append_integer_in_filter(query, params, qualify_column("season"), seasons, "season")
  query <- season_filter$query
  params <- season_filter$params

  if (!is.null(team_id)) {
    query <- paste0(query, " AND ", qualify_column("squad_id"), " = ?team_id")
    params$team_id <- team_id
  }
  if (!is.null(round_number)) {
    query <- paste0(query, " AND ", qualify_column("round_number"), " = ?round_number")
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

apply_player_search_filter <- function(query, params, search, player_id_expr = "stats.player_id") {
  parsed_search <- parse_search(search, name = "search")
  if (is.null(parsed_search)) {
    return(list(query = query, params = params))
  }

  normalized_search <- normalize_player_search_name(parsed_search)
  params$search <- paste0("%", normalized_search, "%")

  list(
    query = paste0(
      query,
      " AND EXISTS (",
      "SELECT 1 FROM player_aliases",
      " WHERE player_aliases.player_id = ", player_id_expr,
      " AND player_aliases.alias_search_name LIKE ?search",
      ")"
    ),
    params = params
  )
}

allowed_origins <- function() {
  value <- Sys.getenv(
    "NETBALL_STATS_ALLOWED_ORIGINS",
    "http://127.0.0.1:4173,http://localhost:4173"
  )
  unique(trimws(strsplit(value, ",", fixed = TRUE)[[1]]))
}
