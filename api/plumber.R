suppressPackageStartupMessages({
  library(plumber)
  library(DBI)
})

resolve_repo_root <- function() {
  configured_root <- Sys.getenv("NETBALL_STATS_REPO_ROOT", "")
  candidates <- unique(Filter(
    nzchar,
    c(
      configured_root,
      getwd(),
      dirname(getwd())
    )
  ))

  for (candidate in candidates) {
    candidate <- normalizePath(candidate, mustWork = FALSE)

    if (file.exists(file.path(candidate, "api", "R", "helpers.R"))) {
      return(candidate)
    }

    if (
      basename(candidate) == "api" &&
      file.exists(file.path(candidate, "R", "helpers.R"))
    ) {
      return(dirname(candidate))
    }
  }

  stop(
    "Could not locate the repository root. Set NETBALL_STATS_REPO_ROOT explicitly.",
    call. = FALSE
  )
}

repo_root_path <- resolve_repo_root()
options(netballstats.repo_root = repo_root_path)
source(file.path(repo_root_path, "R", "database.R"), local = TRUE)
source(file.path(repo_root_path, "api", "R", "helpers.R"), local = TRUE)

request_limiter <- local({
  entries <- new.env(parent = emptyenv())

  function(req, res) {
    window_seconds <- as.integer(Sys.getenv("NETBALL_STATS_RATE_LIMIT_WINDOW_SECONDS", "60"))
    max_requests <- as.integer(Sys.getenv("NETBALL_STATS_RATE_LIMIT_MAX_REQUESTS", "60"))
    client_key <- req$HTTP_X_FORWARDED_FOR %||% req$REMOTE_ADDR %||% "unknown"
    now <- as.numeric(Sys.time())

    current <- if (exists(client_key, envir = entries, inherits = FALSE)) {
      get(client_key, envir = entries, inherits = FALSE)
    } else {
      list(start = now, count = 0L)
    }

    if ((now - current$start) > window_seconds) {
      current <- list(start = now, count = 0L)
    }

    current$count <- current$count + 1L
    assign(client_key, current, envir = entries)

    res$setHeader("X-RateLimit-Limit", as.character(max_requests))
    res$setHeader(
      "X-RateLimit-Remaining",
      as.character(max(0L, max_requests - current$count))
    )

    if (current$count > max_requests) {
      res$status <- 429
      return(list(error = "Rate limit exceeded. Try again shortly."))
    }

    plumber::forward()
  }
})

#* @apiTitle Netball Stats API
#* @apiDescription Read-only Super Netball statistics API backed by a SQLite or PostgreSQL database built with superNetballR.

#* @filter security_headers
function(req, res) {
  origin <- req$HTTP_ORIGIN %||% ""
  allowed <- allowed_origins()

  if (nzchar(origin) && origin %in% allowed) {
    res$setHeader("Access-Control-Allow-Origin", origin)
    res$setHeader("Vary", "Origin")
  }

  res$setHeader("Access-Control-Allow-Methods", "GET, OPTIONS")
  res$setHeader("Access-Control-Allow-Headers", "Content-Type")
  res$setHeader("Cache-Control", "no-store")
  res$setHeader("X-Content-Type-Options", "nosniff")
  res$setHeader("X-Frame-Options", "DENY")
  res$setHeader("Referrer-Policy", "strict-origin-when-cross-origin")
  res$setHeader("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
  if (identical(tolower(Sys.getenv("NETBALL_STATS_ENABLE_HSTS", "true")), "true")) {
    res$setHeader("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
  }

  if (identical(req$REQUEST_METHOD, "OPTIONS")) {
    res$status <- 204
    return(list())
  }

  plumber::forward()
}

#* @filter rate_limit
function(req, res) {
  request_limiter(req, res)
}

database_health_check <- function(include_metadata = FALSE) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(list(ok = FALSE, error = conditionMessage(conn)))
  }
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  query_check <- tryCatch(
    query_rows(conn, "SELECT 1 AS ok"),
    error = function(error) error
  )
  if (inherits(query_check, "error")) {
    return(list(ok = FALSE, error = conditionMessage(query_check)))
  }

  if (!include_metadata) {
    return(list(ok = TRUE, metadata = NULL))
  }

  if (!DBI::dbExistsTable(conn, "metadata")) {
    return(list(
      ok = FALSE,
      error = "Database metadata table not found. Seed the database first."
    ))
  }

  metadata <- tryCatch(
    query_rows(
      conn,
      "SELECT key, value FROM metadata WHERE key IN ('refreshed_at', 'build_mode')"
    ),
    error = function(error) error
  )
  if (inherits(metadata, "error")) {
    return(list(ok = FALSE, error = conditionMessage(metadata)))
  }

  list(ok = TRUE, metadata = metadata)
}

#* @get /live
#* @get /api/live
function() {
  list(status = "ok")
}

#* @get /ready
#* @get /api/ready
function(res) {
  readiness <- database_health_check(include_metadata = FALSE)
  if (!readiness$ok) {
    return(json_error(res, 503, readiness$error))
  }

  list(status = "ok", database = "ok")
}

#* @get /health
#* @get /api/health
function(res) {
  health <- database_health_check(include_metadata = TRUE)
  if (!health$ok) {
    return(json_error(res, 503, health$error))
  }

  metadata <- health$metadata

  list(
    status = "ok",
    database = "ok",
    refreshed_at = metadata$value[metadata$key == "refreshed_at"] %||% NA_character_,
    build_mode = metadata$value[metadata$key == "build_mode"] %||% NA_character_
  )
}

#* @get /meta
#* @get /api/meta
function(res) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(json_error(res, 503, conditionMessage(conn)))
  }
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  metadata <- query_rows(conn, "SELECT key, value FROM metadata")
  metadata_map <- setNames(metadata$value, metadata$key)
  seasons <- query_rows(conn, "SELECT DISTINCT season FROM matches ORDER BY season DESC")$season
  teams <- query_rows(
    conn,
    "SELECT squad_id, squad_name, squad_code, squad_colour FROM teams ORDER BY squad_name"
  )

  list(
    default_season = if (length(seasons)) seasons[[1]] else NA_integer_,
    seasons = seasons,
    teams = teams,
    team_stats = available_stats(conn, "team_period_stats"),
    player_stats = available_stats(conn, "player_period_stats"),
    build_mode = metadata_map[["build_mode"]] %||% "production",
    refreshed_at = metadata_map[["refreshed_at"]] %||% NA_character_
  )
}

#* @get /summary
#* @get /api/summary
function(season = "", seasons = "", team_id = "", round = "", res) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(json_error(res, 503, conditionMessage(conn)))
  }
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  result <- tryCatch({
    seasons <- parse_season_filter(season, seasons)
    team_id <- parse_optional_int(team_id, "team_id", minimum = 1L)
    round <- parse_optional_int(round, "round", minimum = 1L, maximum = 30L)

    match_query <- "SELECT COUNT(*) AS total_matches, COUNT(DISTINCT venue_id) AS total_venues FROM matches WHERE 1 = 1"
    match_filters <- apply_match_filters(match_query, list(), seasons, team_id, round)
    match_summary <- query_rows(conn, match_filters$query, match_filters$params)

    team_query <- "SELECT COUNT(DISTINCT squad_id) AS total_teams FROM team_period_stats WHERE 1 = 1"
    team_filters <- apply_stat_filters(team_query, list(), seasons, team_id, round)
    team_summary <- query_rows(conn, team_filters$query, team_filters$params)

    player_query <- "SELECT COUNT(DISTINCT player_id) AS total_players FROM player_period_stats WHERE 1 = 1"
    player_filters <- apply_stat_filters(player_query, list(), seasons, team_id, round)
    player_summary <- query_rows(conn, player_filters$query, player_filters$params)

    goals_query <- "SELECT COALESCE(SUM(value_number), 0) AS total_goals FROM team_period_stats WHERE stat = 'goals'"
    goals_filters <- apply_stat_filters(goals_query, list(), seasons, team_id, round)
    goals_summary <- query_rows(conn, goals_filters$query, goals_filters$params)

    metadata <- query_rows(
      conn,
      "SELECT key, value FROM metadata WHERE key IN ('refreshed_at', 'build_mode')"
    )
    metadata_map <- setNames(metadata$value, metadata$key)

    list(
      total_matches = match_summary$total_matches[[1]],
      total_venues = match_summary$total_venues[[1]],
      total_teams = team_summary$total_teams[[1]],
      total_players = player_summary$total_players[[1]],
      total_goals = round(as.numeric(goals_summary$total_goals[[1]]), 0),
      refreshed_at = metadata_map[["refreshed_at"]] %||% NA_character_,
      build_mode = metadata_map[["build_mode"]] %||% "production"
    )
  }, error = function(error) {
    json_error(res, 400, conditionMessage(error))
  })

  result
}

#* @get /matches
#* @get /api/matches
function(season = "", seasons = "", team_id = "", round = "", limit = "12", res) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(json_error(res, 503, conditionMessage(conn)))
  }
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  tryCatch({
    seasons <- parse_season_filter(season, seasons)
    team_id <- parse_optional_int(team_id, "team_id", minimum = 1L)
    round <- parse_optional_int(round, "round", minimum = 1L, maximum = 30L)
    limit <- parse_limit(limit, default = 12L, maximum = 50L)

    base_query <- paste(
      "SELECT season, competition_phase, round_number, game_number, home_squad_name, away_squad_name,",
      "home_score, away_score, venue_name, local_start_time",
      "FROM matches WHERE 1 = 1"
    )
    filters <- apply_match_filters(base_query, list(), seasons, team_id, round)
    filters$query <- paste0(
      filters$query,
      " ORDER BY season DESC, local_start_time DESC, round_number DESC, game_number DESC LIMIT ?limit"
    )
    filters$params$limit <- limit

    list(data = query_rows(conn, filters$query, filters$params))
  }, error = function(error) {
    json_error(res, 400, conditionMessage(error))
  })
}

#* @get /team-leaders
#* @get /api/team-leaders
function(season = "", seasons = "", team_id = "", round = "", stat = "goals", limit = "8", res) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(json_error(res, 503, conditionMessage(conn)))
  }
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  tryCatch({
    seasons <- parse_season_filter(season, seasons)
    team_id <- parse_optional_int(team_id, "team_id", minimum = 1L)
    round <- parse_optional_int(round, "round", minimum = 1L, maximum = 30L)
    limit <- parse_limit(limit, default = 8L, maximum = 25L)
    stat <- validate_stat(conn, "team_period_stats", stat, default_stat = "goals")

    query <- paste(
      "SELECT squad_id, squad_name, ?stat AS stat, ROUND(CAST(SUM(value_number) AS numeric), 2) AS total_value,",
      "COUNT(DISTINCT match_id) AS matches_played",
      "FROM team_period_stats WHERE stat = ?stat"
    )
    filters <- apply_stat_filters(query, list(stat = stat), seasons, team_id, round)
    filters$query <- paste0(
      filters$query,
      " GROUP BY squad_id, squad_name ORDER BY total_value DESC, squad_name ASC LIMIT ?limit"
    )
    filters$params$limit <- limit

    list(data = query_rows(conn, filters$query, filters$params))
  }, error = function(error) {
    json_error(res, 400, conditionMessage(error))
  })
}

#* @get /player-leaders
#* @get /api/player-leaders
function(season = "", seasons = "", team_id = "", round = "", stat = "goals", search = "", limit = "12", res) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(json_error(res, 503, conditionMessage(conn)))
  }
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  tryCatch({
    seasons <- parse_season_filter(season, seasons)
    team_id <- parse_optional_int(team_id, "team_id", minimum = 1L)
    round <- parse_optional_int(round, "round", minimum = 1L, maximum = 30L)
    limit <- parse_limit(limit, default = 12L, maximum = 50L)
    stat <- validate_stat(conn, "player_period_stats", stat, default_stat = "goals")

    query <- paste(
      "SELECT stats.player_id, players.canonical_name AS player_name, stats.squad_name,",
      "?stat AS stat, ROUND(CAST(SUM(stats.value_number) AS numeric), 2) AS total_value",
      "FROM player_period_stats AS stats",
      "INNER JOIN players ON players.player_id = stats.player_id",
      "WHERE stats.stat = ?stat"
    )
    filters <- apply_stat_filters(query, list(stat = stat), seasons, team_id, round, table_alias = "stats")
    search_filters <- apply_player_search_filter(filters$query, filters$params, search, "stats.player_id")
    filters$query <- search_filters$query
    filters$params <- search_filters$params
    filters$query <- paste0(
      filters$query,
      " GROUP BY stats.player_id, players.canonical_name, stats.squad_name",
      " ORDER BY total_value DESC, players.canonical_name ASC LIMIT ?limit"
    )
    filters$params$limit <- limit

    list(data = query_rows(conn, filters$query, filters$params))
  }, error = function(error) {
    json_error(res, 400, conditionMessage(error))
  })
}

#* @get /team-season-series
#* @get /api/team-season-series
function(season = "", seasons = "", team_id = "", round = "", stat = "goals", limit = "5", res) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(json_error(res, 503, conditionMessage(conn)))
  }
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  tryCatch({
    seasons <- parse_season_filter(season, seasons)
    team_id <- parse_optional_int(team_id, "team_id", minimum = 1L)
    round <- parse_optional_int(round, "round", minimum = 1L, maximum = 30L)
    limit <- parse_limit(limit, default = 5L, maximum = 8L)
    stat <- validate_stat(conn, "team_period_stats", stat, default_stat = "goals")

    ranked_query <- paste(
      "SELECT squad_id, ROUND(CAST(SUM(value_number) AS numeric), 2) AS grand_total",
      "FROM team_period_stats WHERE stat = ?stat"
    )
    ranked_filters <- apply_stat_filters(ranked_query, list(stat = stat), seasons, team_id, round)
    ranked_filters$query <- paste0(
      ranked_filters$query,
      " GROUP BY squad_id ORDER BY grand_total DESC, squad_id ASC"
    )
    if (is.null(team_id)) {
      ranked_filters$query <- paste0(ranked_filters$query, " LIMIT ?limit")
      ranked_filters$params$limit <- limit
    }
    ranked_ids <- query_rows(conn, ranked_filters$query, ranked_filters$params)$squad_id

    query <- paste(
      "SELECT stats.squad_id, stats.squad_name, teams.squad_colour, stats.season, ?stat AS stat,",
      "ROUND(CAST(SUM(stats.value_number) AS numeric), 2) AS total_value,",
      "COUNT(DISTINCT stats.match_id) AS matches_played",
      "FROM team_period_stats AS stats",
      "LEFT JOIN teams ON teams.squad_id = stats.squad_id",
      "WHERE stats.stat = ?stat"
    )
    filters <- apply_stat_filters(query, list(stat = stat), seasons, team_id, round, table_alias = "stats")
    if (is.null(team_id)) {
      ranked_series_filters <- append_integer_in_filter(
        filters$query,
        filters$params,
        "stats.squad_id",
        ranked_ids,
        "series_team"
      )
      filters$query <- ranked_series_filters$query
      filters$params <- ranked_series_filters$params
    }
    filters$query <- paste0(
      filters$query,
      " GROUP BY stats.squad_id, stats.squad_name, teams.squad_colour, stats.season",
      " ORDER BY stats.season ASC, total_value DESC, stats.squad_name ASC"
    )

    list(data = query_rows(conn, filters$query, filters$params))
  }, error = function(error) {
    json_error(res, 400, conditionMessage(error))
  })
}

#* @get /player-season-series
#* @get /api/player-season-series
function(season = "", seasons = "", team_id = "", round = "", stat = "goals", search = "", limit = "5", res) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(json_error(res, 503, conditionMessage(conn)))
  }
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  tryCatch({
    seasons <- parse_season_filter(season, seasons)
    team_id <- parse_optional_int(team_id, "team_id", minimum = 1L)
    round <- parse_optional_int(round, "round", minimum = 1L, maximum = 30L)
    limit <- parse_limit(limit, default = 5L, maximum = 8L)
    stat <- validate_stat(conn, "player_period_stats", stat, default_stat = "goals")

    ranked_query <- paste(
      "SELECT stats.player_id, ROUND(CAST(SUM(stats.value_number) AS numeric), 2) AS grand_total",
      "FROM player_period_stats AS stats",
      "WHERE stats.stat = ?stat"
    )
    ranked_filters <- apply_stat_filters(ranked_query, list(stat = stat), seasons, team_id, round, table_alias = "stats")
    ranked_search_filters <- apply_player_search_filter(ranked_filters$query, ranked_filters$params, search, "stats.player_id")
    ranked_filters$query <- ranked_search_filters$query
    ranked_filters$params <- ranked_search_filters$params
    ranked_filters$query <- paste0(
      ranked_filters$query,
      " GROUP BY stats.player_id ORDER BY grand_total DESC, stats.player_id ASC LIMIT ?limit"
    )
    ranked_filters$params$limit <- limit
    ranked_ids <- query_rows(conn, ranked_filters$query, ranked_filters$params)$player_id

    query <- paste(
      "SELECT stats.player_id, players.canonical_name AS player_name, MAX(stats.squad_name) AS squad_name,",
      "stats.season, ?stat AS stat, ROUND(CAST(SUM(stats.value_number) AS numeric), 2) AS total_value,",
      "COUNT(DISTINCT stats.match_id) AS matches_played",
      "FROM player_period_stats AS stats",
      "INNER JOIN players ON players.player_id = stats.player_id",
      "WHERE stats.stat = ?stat"
    )
    filters <- apply_stat_filters(query, list(stat = stat), seasons, team_id, round, table_alias = "stats")
    search_filters <- apply_player_search_filter(filters$query, filters$params, search, "stats.player_id")
    filters$query <- search_filters$query
    filters$params <- search_filters$params
    series_filters <- append_integer_in_filter(
      filters$query,
      filters$params,
      "stats.player_id",
      ranked_ids,
      "series_player"
    )
    filters$query <- series_filters$query
    filters$params <- series_filters$params
    filters$query <- paste0(
      filters$query,
      " GROUP BY stats.player_id, players.canonical_name, stats.season",
      " ORDER BY stats.season ASC, total_value DESC, players.canonical_name ASC"
    )

    list(data = query_rows(conn, filters$query, filters$params))
  }, error = function(error) {
    json_error(res, 400, conditionMessage(error))
  })
}

#* @get /team-game-highs
#* @get /api/team-game-highs
function(season = "", seasons = "", team_id = "", round = "", stat = "goals", limit = "10", res) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(json_error(res, 503, conditionMessage(conn)))
  }
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  tryCatch({
    seasons <- parse_season_filter(season, seasons)
    team_id <- parse_optional_int(team_id, "team_id", minimum = 1L)
    round <- parse_optional_int(round, "round", minimum = 1L, maximum = 30L)
    limit <- parse_limit(limit, default = 10L, maximum = 50L)
    stat <- validate_stat(conn, "team_period_stats", stat, default_stat = "goals")

    query <- paste(
      "SELECT stats.squad_id, stats.squad_name,",
      "MAX(CASE WHEN matches.home_squad_id = stats.squad_id THEN matches.away_squad_name ELSE matches.home_squad_name END) AS opponent,",
      "stats.season, stats.round_number, stats.match_id, matches.local_start_time,",
      "?stat AS stat, ROUND(CAST(SUM(stats.value_number) AS numeric), 2) AS total_value",
      "FROM team_period_stats AS stats",
      "INNER JOIN matches ON matches.match_id = stats.match_id",
      "WHERE stats.stat = ?stat"
    )
    filters <- apply_stat_filters(query, list(stat = stat), seasons, team_id, round, table_alias = "stats")
    filters$query <- paste0(
      filters$query,
      " GROUP BY stats.squad_id, stats.squad_name, stats.season, stats.round_number, stats.match_id, matches.local_start_time",
      " ORDER BY total_value DESC, stats.season DESC, stats.round_number DESC, stats.squad_name ASC LIMIT ?limit"
    )
    filters$params$limit <- limit

    list(data = query_rows(conn, filters$query, filters$params))
  }, error = function(error) {
    json_error(res, 400, conditionMessage(error))
  })
}

#* @get /player-game-highs
#* @get /api/player-game-highs
function(season = "", seasons = "", team_id = "", round = "", stat = "goals", search = "", limit = "10", res) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(json_error(res, 503, conditionMessage(conn)))
  }
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  tryCatch({
    seasons <- parse_season_filter(season, seasons)
    team_id <- parse_optional_int(team_id, "team_id", minimum = 1L)
    round <- parse_optional_int(round, "round", minimum = 1L, maximum = 30L)
    limit <- parse_limit(limit, default = 10L, maximum = 50L)
    stat <- validate_stat(conn, "player_period_stats", stat, default_stat = "goals")

    query <- paste(
      "SELECT stats.player_id, players.canonical_name AS player_name, stats.squad_name,",
      "MAX(CASE WHEN matches.home_squad_id = stats.squad_id THEN matches.away_squad_name ELSE matches.home_squad_name END) AS opponent,",
      "stats.season, stats.round_number, stats.match_id, matches.local_start_time,",
      "?stat AS stat, ROUND(CAST(SUM(stats.value_number) AS numeric), 2) AS total_value",
      "FROM player_period_stats AS stats",
      "INNER JOIN players ON players.player_id = stats.player_id",
      "INNER JOIN matches ON matches.match_id = stats.match_id",
      "WHERE stats.stat = ?stat"
    )
    filters <- apply_stat_filters(query, list(stat = stat), seasons, team_id, round, table_alias = "stats")
    search_filters <- apply_player_search_filter(filters$query, filters$params, search, "stats.player_id")
    filters$query <- search_filters$query
    filters$params <- search_filters$params
    filters$query <- paste0(
      filters$query,
      " GROUP BY stats.player_id, players.canonical_name, stats.squad_name, stats.season, stats.round_number, stats.match_id, matches.local_start_time",
      " ORDER BY total_value DESC, stats.season DESC, stats.round_number DESC, players.canonical_name ASC LIMIT ?limit"
    )
    filters$params$limit <- limit

    list(data = query_rows(conn, filters$query, filters$params))
  }, error = function(error) {
    json_error(res, 400, conditionMessage(error))
  })
}
