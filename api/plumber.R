suppressPackageStartupMessages({
  library(plumber)
  library(DBI)
  library(RSQLite)
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
#* @apiDescription Read-only Super Netball statistics API backed by a local SQLite database built with superNetballR.

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

#* @get /health
function(res) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(json_error(res, 503, conditionMessage(conn)))
  }
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  metadata <- query_rows(
    conn,
    "SELECT key, value FROM metadata WHERE key IN ('refreshed_at', 'build_mode')"
  )

  list(
    status = "ok",
    refreshed_at = metadata$value[metadata$key == "refreshed_at"] %||% NA_character_,
    build_mode = metadata$value[metadata$key == "build_mode"] %||% NA_character_
  )
}

#* @get /meta
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
function(season = "", team_id = "", round = "", res) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(json_error(res, 503, conditionMessage(conn)))
  }
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  result <- tryCatch({
    season <- parse_optional_int(season, "season", minimum = 2017L)
    team_id <- parse_optional_int(team_id, "team_id", minimum = 1L)
    round <- parse_optional_int(round, "round", minimum = 1L, maximum = 30L)

    match_query <- "SELECT COUNT(*) AS total_matches, COUNT(DISTINCT venue_id) AS total_venues FROM matches WHERE 1 = 1"
    match_filters <- apply_match_filters(match_query, list(), season, team_id, round)
    match_summary <- query_rows(conn, match_filters$query, match_filters$params)

    team_query <- "SELECT COUNT(DISTINCT squad_id) AS total_teams FROM team_period_stats WHERE 1 = 1"
    team_filters <- apply_stat_filters(team_query, list(), season, team_id, round)
    team_summary <- query_rows(conn, team_filters$query, team_filters$params)

    player_query <- "SELECT COUNT(DISTINCT player_id) AS total_players FROM player_period_stats WHERE 1 = 1"
    player_filters <- apply_stat_filters(player_query, list(), season, team_id, round)
    player_summary <- query_rows(conn, player_filters$query, player_filters$params)

    goals_query <- "SELECT COALESCE(SUM(value_number), 0) AS total_goals FROM team_period_stats WHERE stat = 'goals'"
    goals_filters <- apply_stat_filters(goals_query, list(), season, team_id, round)
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
function(season = "", team_id = "", round = "", limit = "12", res) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(json_error(res, 503, conditionMessage(conn)))
  }
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  tryCatch({
    season <- parse_optional_int(season, "season", minimum = 2017L)
    team_id <- parse_optional_int(team_id, "team_id", minimum = 1L)
    round <- parse_optional_int(round, "round", minimum = 1L, maximum = 30L)
    limit <- parse_limit(limit, default = 12L, maximum = 50L)

    base_query <- paste(
      "SELECT season, competition_phase, round_number, game_number, home_squad_name, away_squad_name,",
      "home_score, away_score, venue_name, local_start_time",
      "FROM matches WHERE 1 = 1"
    )
    filters <- apply_match_filters(base_query, list(), season, team_id, round)
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
function(season = "", team_id = "", round = "", stat = "goals", limit = "8", res) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(json_error(res, 503, conditionMessage(conn)))
  }
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  tryCatch({
    season <- parse_optional_int(season, "season", minimum = 2017L)
    team_id <- parse_optional_int(team_id, "team_id", minimum = 1L)
    round <- parse_optional_int(round, "round", minimum = 1L, maximum = 30L)
    limit <- parse_limit(limit, default = 8L, maximum = 25L)
    stat <- validate_stat(conn, "team_period_stats", stat, default_stat = "goals")

    query <- paste(
      "SELECT squad_id, squad_name, ?stat AS stat, ROUND(SUM(value_number), 2) AS total_value,",
      "COUNT(DISTINCT match_id) AS matches_played",
      "FROM team_period_stats WHERE stat = ?stat"
    )
    filters <- apply_stat_filters(query, list(stat = stat), season, team_id, round)
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
function(season = "", team_id = "", round = "", stat = "goals", search = "", limit = "12", res) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(json_error(res, 503, conditionMessage(conn)))
  }
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  tryCatch({
    season <- parse_optional_int(season, "season", minimum = 2017L)
    team_id <- parse_optional_int(team_id, "team_id", minimum = 1L)
    round <- parse_optional_int(round, "round", minimum = 1L, maximum = 30L)
    limit <- parse_limit(limit, default = 12L, maximum = 50L)
    stat <- validate_stat(conn, "player_period_stats", stat, default_stat = "goals")
    search <- parse_search(search, name = "search")

    query <- paste(
      "SELECT player_id, player_name, squad_name, ?stat AS stat, ROUND(SUM(value_number), 2) AS total_value",
      "FROM player_period_stats WHERE stat = ?stat"
    )
    filters <- apply_stat_filters(query, list(stat = stat), season, team_id, round)
    if (!is.null(search)) {
      filters$query <- paste0(filters$query, " AND player_name LIKE ?search")
      filters$params$search <- paste0("%", search, "%")
    }
    filters$query <- paste0(
      filters$query,
      " GROUP BY player_id, player_name, squad_name ORDER BY total_value DESC, player_name ASC LIMIT ?limit"
    )
    filters$params$limit <- limit

    list(data = query_rows(conn, filters$query, filters$params))
  }, error = function(error) {
    json_error(res, 400, conditionMessage(error))
  })
}
