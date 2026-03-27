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

request_telemetry_enabled <- function() {
  identical(tolower(Sys.getenv("NETBALL_STATS_REQUEST_TELEMETRY", "true")), "true")
}

request_slow_threshold_ms <- function() {
  parse_positive_env_int("NETBALL_STATS_REQUEST_SLOW_MS", 1500L)
}

request_path_for_logs <- function(req) {
  raw_path <- req$PATH_INFO %||% req$REQUEST_URI %||% "/"
  sub("\\?.*$", "", raw_path)
}

browser_telemetry_connection_string <- function() {
  trimws(Sys.getenv("NETBALL_STATS_BROWSER_APPINSIGHTS_CONNECTION_STRING", ""))
}

browser_telemetry_enabled <- function() {
  nzchar(browser_telemetry_connection_string())
}

meta_json_scalar <- function(value, default = NULL) {
  if (is.null(value) || length(value) == 0L) {
    return(if (is.null(default)) NULL else jsonlite::unbox(default))
  }

  scalar <- value[[1]]
  if (is.null(scalar) || length(scalar) == 0L || (length(scalar) == 1L && is.na(scalar))) {
    return(if (is.null(default)) NULL else jsonlite::unbox(default))
  }

  jsonlite::unbox(unname(scalar))
}

allowed_browser_page_types <- c(
  "archive-home",
  "ask-stats",
  "compare",
  "player-directory",
  "player-profile"
)

allowed_browser_event_names <- c(
  "archive_filters_applied",
  "archive_filters_reset",
  "ask_stats_submitted",
  "ask_stats_completed",
  "ask_stats_cleared",
  "compare_submitted",
  "compare_completed",
  "compare_reset",
  "player_profile_loaded",
  "player_directory_loaded"
)

parse_connection_string_fields <- function(connection_string) {
  fields <- list()
  parts <- strsplit(connection_string %||% "", ";", fixed = TRUE)[[1]]
  for (part in parts) {
    entry <- strsplit(part, "=", fixed = TRUE)[[1]]
    if (length(entry) != 2L) {
      next
    }
    fields[[tolower(trimws(entry[[1]]))]] <- trimws(entry[[2]])
  }
  fields
}

browser_telemetry_ingestion_url <- function() {
  fields <- parse_connection_string_fields(browser_telemetry_connection_string())
  instrumentation_key <- fields[["instrumentationkey"]] %||% ""
  if (!nzchar(instrumentation_key)) {
    return(NULL)
  }

  endpoint <- fields[["ingestionendpoint"]] %||% ""
  if (!nzchar(endpoint)) {
    endpoint_suffix <- fields[["endpointsuffix"]] %||% "services.visualstudio.com"
    location <- fields[["location"]] %||% ""
    endpoint <- sprintf(
      "https://%sdc.%s",
      if (nzchar(location)) paste0(location, ".") else "",
      endpoint_suffix
    )
  }

  sprintf("%s/v2/track", sub("/+$", "", endpoint))
}

browser_telemetry_instrumentation_key <- function() {
  fields <- parse_connection_string_fields(browser_telemetry_connection_string())
  fields[["instrumentationkey"]] %||% ""
}

telemetry_iso_time <- function(time = Sys.time()) {
  format(as.POSIXct(time, tz = "UTC"), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")
}

telemetry_trim_string <- function(value, max_length = 120L) {
  trimmed <- gsub("\\s+", " ", trimws(as.character(value %||% "")))
  substr(trimmed, 1L, max_length)
}

telemetry_sanitise_properties <- function(properties) {
  if (is.null(properties) || !is.list(properties)) {
    return(list())
  }

  output <- list()
  property_names <- names(properties) %||% character()
  if (!length(property_names)) {
    return(output)
  }

  for (property_name in property_names) {
    if (!grepl("^[a-z0-9_]+$", property_name)) {
      next
    }

    value <- properties[[property_name]]
    if (is.null(value) || length(value) == 0L) {
      next
    }

    scalar <- value[[1]]
    if (is.na(scalar)) {
      next
    }

    output[[property_name]] <- telemetry_trim_string(scalar)
  }

  output
}

telemetry_sanitise_context <- function(context) {
  if (is.null(context) || !is.list(context)) {
    return(list())
  }

  output <- list()

  session_id <- telemetry_trim_string(context$session_id %||% "", 80L)
  user_id <- telemetry_trim_string(context$user_id %||% "", 80L)
  operation_id <- telemetry_trim_string(context$operation_id %||% "", 80L)
  viewport_bucket <- telemetry_trim_string(context$viewport_bucket %||% "", 20L)
  browser_language <- telemetry_trim_string(context$browser_language %||% "", 20L)
  referrer_host <- telemetry_trim_string(context$referrer_host %||% "", 80L)
  timezone <- telemetry_trim_string(context$timezone %||% "", 60L)
  device_type <- telemetry_trim_string(context$device_type %||% "", 20L)
  device_os <- telemetry_trim_string(context$device_os %||% "", 40L)
  device_os_version <- telemetry_trim_string(context$device_os_version %||% "", 80L)

  if (nzchar(session_id)) {
    output$session_id <- session_id
  }
  if (nzchar(user_id)) {
    output$user_id <- user_id
  }
  if (nzchar(operation_id)) {
    output$operation_id <- operation_id
  }
  if (nzchar(viewport_bucket)) {
    output$viewport_bucket <- viewport_bucket
  }
  if (nzchar(browser_language)) {
    output$browser_language <- browser_language
  }
  if (nzchar(referrer_host)) {
    output$referrer_host <- referrer_host
  }
  if (nzchar(timezone)) {
    output$timezone <- timezone
  }
  if (nzchar(device_type)) {
    output$device_type <- device_type
  }
  if (nzchar(device_os)) {
    output$device_os <- device_os
  }
  if (nzchar(device_os_version)) {
    output$device_os_version <- device_os_version
  }

  output
}

build_telemetry_envelope <- function(kind, payload, req) {
  instrumentation_key <- browser_telemetry_instrumentation_key()
  if (!nzchar(instrumentation_key)) {
    stop("Browser telemetry instrumentation key is unavailable.", call. = FALSE)
  }

  telemetry_name <- telemetry_trim_string(payload$name, 80L)
  telemetry_uri <- telemetry_trim_string(payload$uri, 200L)
  telemetry_context <- telemetry_sanitise_context(payload$context)
  telemetry_properties <- utils::modifyList(
    telemetry_sanitise_properties(payload$properties),
    Filter(
      nzchar,
      list(
        viewport_bucket = telemetry_context$viewport_bucket %||% "",
        browser_language = telemetry_context$browser_language %||% "",
        referrer_host = telemetry_context$referrer_host %||% "",
        timezone = telemetry_context$timezone %||% "",
        device_type = telemetry_context$device_type %||% "",
        device_os = telemetry_context$device_os %||% "",
        device_os_version = telemetry_context$device_os_version %||% ""
      )
    )
  )
  operation_name <- if (nzchar(telemetry_uri)) telemetry_uri else telemetry_name
  client_ip <- telemetry_trim_string(req$HTTP_X_FORWARDED_FOR %||% req$REMOTE_ADDR %||% "unknown", 80L)

  tags <- list(
    "ai.operation.name" = operation_name,
    "ai.cloud.role" = "netballstats-browser",
    "ai.location.ip" = client_ip,
    "ai.internal.sdkVersion" = "netballstats-browser-proxy:1.0.0"
  )

  if (nzchar(telemetry_context$device_type %||% "")) {
    tags[["ai.device.type"]] <- telemetry_context$device_type
  }
  if (nzchar(telemetry_context$device_os %||% "")) {
    tags[["ai.device.os"]] <- telemetry_context$device_os
  }
  if (nzchar(telemetry_context$device_os_version %||% "")) {
    tags[["ai.device.osVersion"]] <- telemetry_context$device_os_version
  }

  if (nzchar(telemetry_context$session_id %||% "")) {
    tags[["ai.session.id"]] <- telemetry_context$session_id
  }
  if (nzchar(telemetry_context$user_id %||% "")) {
    tags[["ai.user.id"]] <- telemetry_context$user_id
  }
  if (nzchar(telemetry_context$operation_id %||% "")) {
    tags[["ai.operation.id"]] <- telemetry_context$operation_id
  }

  list(
    time = telemetry_iso_time(),
    iKey = instrumentation_key,
    name = sprintf(
      "Microsoft.ApplicationInsights.%s.%s",
      gsub("-", "", instrumentation_key, fixed = TRUE),
      if (identical(kind, "pageView")) "Pageview" else "Event"
    ),
    tags = tags,
    data = list(
      baseType = if (identical(kind, "pageView")) "PageviewData" else "EventData",
      baseData = if (identical(kind, "pageView")) {
        list(
          ver = 2,
          name = telemetry_name,
          url = telemetry_uri,
          properties = telemetry_properties
        )
      } else {
        list(
          ver = 2,
          name = telemetry_name,
          properties = telemetry_properties
        )
      }
    )
  )
}

forward_browser_telemetry <- function(kind, payload, req) {
  ingestion_url <- browser_telemetry_ingestion_url()
  if (!nzchar(ingestion_url %||% "")) {
    stop("Browser telemetry ingestion endpoint is unavailable.", call. = FALSE)
  }

  envelope <- build_telemetry_envelope(kind, payload, req)
  response <- httr::POST(
    url = ingestion_url,
    body = jsonlite::toJSON(list(envelope), auto_unbox = TRUE, null = "null"),
    encode = "raw",
    httr::add_headers(.headers = c(
      "Content-Type" = "application/json",
      "User-Agent" = telemetry_trim_string(req$HTTP_USER_AGENT %||% "netballstats-browser-proxy/1.0", 240L),
      "Accept-Language" = telemetry_trim_string(req$HTTP_ACCEPT_LANGUAGE %||% "", 120L)
    )),
    httr::timeout(5)
  )

  status <- httr::status_code(response)
  if (status < 200L || status >= 300L) {
    stop(sprintf("Telemetry ingestion failed with status %s.", status), call. = FALSE)
  }

  invisible(TRUE)
}

parse_browser_telemetry_request <- function(req) {
  raw_body <- req$postBody %||% ""
  if (!nzchar(raw_body)) {
    stop("Telemetry body is required.", call. = FALSE)
  }

  parsed <- jsonlite::fromJSON(raw_body, simplifyVector = FALSE)
  if (!is.list(parsed)) {
    stop("Telemetry body must be a JSON object.", call. = FALSE)
  }

  kind <- parsed$kind %||% ""
  if (!kind %in% c("pageView", "event")) {
    stop("Telemetry kind must be pageView or event.", call. = FALSE)
  }

  payload <- parsed$payload
  if (!is.list(payload)) {
    stop("Telemetry payload is required.", call. = FALSE)
  }

  payload$name <- telemetry_trim_string(payload$name, 80L)
  if (!nzchar(payload$name)) {
    stop("Telemetry name is required.", call. = FALSE)
  }

  if (identical(kind, "pageView") && !payload$name %in% allowed_browser_page_types) {
    stop("Telemetry page type is not allowed.", call. = FALSE)
  }

  if (identical(kind, "event") && !payload$name %in% allowed_browser_event_names) {
    stop("Telemetry event name is not allowed.", call. = FALSE)
  }

  payload$uri <- telemetry_trim_string(payload$uri, 200L)
  payload$properties <- telemetry_sanitise_properties(payload$properties)
  payload$context <- telemetry_sanitise_context(payload$context)

  list(kind = kind, payload = payload)
}

request_telemetry_ignored <- function(path) {
  path %in% c("/live", "/ready", "/health", "/api/live", "/api/ready", "/api/health", "/telemetry", "/api/telemetry")
}

response_status_code <- function(res, default = 200L) {
  status <- suppressWarnings(as.integer(res$status %||% default))
  if (is.na(status)) {
    return(default)
  }
  status
}

request_log_level <- function(status, duration_ms) {
  if (!is.na(status) && status >= 500L) {
    return("ERROR")
  }
  if (!is.na(status) && status >= 400L) {
    return("WARN")
  }
  if (!is.na(duration_ms) && duration_ms >= request_slow_threshold_ms()) {
    return("WARN")
  }
  "INFO"
}

request_log_event <- function(status, duration_ms) {
  if (!is.na(status) && status >= 500L) {
    return("request_failed")
  }
  if (!is.na(status) && status >= 400L) {
    return("request_rejected")
  }
  if (!is.na(duration_ms) && duration_ms >= request_slow_threshold_ms()) {
    return("request_slow")
  }
  "request_complete"
}

#* @apiTitle Netball Stats API
#* @apiDescription Read-only Super Netball statistics API backed by a PostgreSQL database built with superNetballR.

#* @filter security_headers
function(req, res) {
  origin <- req$HTTP_ORIGIN %||% ""
  allowed <- allowed_origins()

  if (nzchar(origin) && origin %in% allowed) {
    res$setHeader("Access-Control-Allow-Origin", origin)
    res$setHeader("Vary", "Origin")
  }

  res$setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
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

#* @filter request_telemetry
function(req, res) {
  path <- request_path_for_logs(req)
  if (
    !request_telemetry_enabled() ||
    identical(req$REQUEST_METHOD, "OPTIONS") ||
    request_telemetry_ignored(path)
  ) {
    return(plumber::forward())
  }

  start_time <- Sys.time()
  result <- tryCatch(
    plumber::forward(),
    error = function(error) {
      duration_ms <- round(as.numeric(difftime(Sys.time(), start_time, units = "secs")) * 1000)
      api_log(
        "ERROR",
        "request_failed",
        method = req$REQUEST_METHOD %||% "GET",
        path = path,
        status = 500L,
        duration_ms = duration_ms,
        error_class = class(error)[[1]] %||% "unknown"
      )
      stop(error)
    }
  )

  duration_ms <- round(as.numeric(difftime(Sys.time(), start_time, units = "secs")) * 1000)
  status <- response_status_code(res)
  api_log(
    request_log_level(status, duration_ms),
    request_log_event(status, duration_ms),
    method = req$REQUEST_METHOD %||% "GET",
    path = path,
    status = status,
    duration_ms = duration_ms
  )

  result
}

#* @filter rate_limit
function(req, res) {
  request_limiter(req, res)
}

database_health_check <- function(include_metadata = FALSE) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    api_log("ERROR", "db_health_connection_failed", error_class = class(conn)[[1]] %||% "unknown")
    return(list(ok = FALSE, error = "The statistics database is currently unavailable."))
  }
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  query_check <- tryCatch(
    query_rows(conn, "SELECT 1 AS ok"),
    error = function(error) error
  )
  if (inherits(query_check, "error")) {
    api_log("ERROR", "db_health_query_failed", error_class = class(query_check)[[1]] %||% "unknown")
    return(list(ok = FALSE, error = "The statistics database is currently unavailable."))
  }

  if (!include_metadata) {
    return(list(ok = TRUE, metadata = NULL))
  }

  if (!DBI::dbExistsTable(conn, "metadata")) {
    api_log("WARN", "db_metadata_missing")
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
    api_log("ERROR", "db_health_metadata_failed", error_class = class(metadata)[[1]] %||% "unknown")
    return(list(ok = FALSE, error = "The statistics database is currently unavailable."))
  }

  list(ok = TRUE, metadata = metadata)
}

handle_request_error <- function(error, res) {
  msg <- conditionMessage(error)
  timeout <- grepl("statement timeout|canceling statement|query_canceled", msg, ignore.case = TRUE)
  api_log(
    if (timeout) "WARN" else "INFO",
    if (timeout) "request_timeout" else "request_rejected",
    error_class = class(error)[[1]] %||% "unknown"
  )
  if (grepl("statement timeout|canceling statement|query_canceled", msg, ignore.case = TRUE)) {
    json_error(res, 503, "The query took too long. Try narrowing to a specific season or player.")
  } else {
    json_error(res, 400, "Invalid request parameters.")
  }
}

api_log <- function(level, event, ...) {
  details <- list(...)
  detail_parts <- unlist(lapply(names(details), function(name) {
    value <- details[[name]]
    if (is.null(value) || length(value) == 0 || all(is.na(value))) {
      return(NULL)
    }
    scalar <- gsub("[[:space:]]+", " ", as.character(value[[1]]))
    paste0(name, "=", scalar)
  }))
  message("[API] ", paste(c(paste0("level=", level), paste0("event=", event), detail_parts), collapse = " "))
}

database_unavailable <- function(res, error) {
  api_log("ERROR", "db_connection_failed", error_class = class(error)[[1]] %||% "unknown")
  json_error(res, 503, "The statistics API is currently unavailable. Please try again shortly.")
}

json_scalar <- function(value) {
  if (!is.list(value) && length(value) == 1L) {
    return(jsonlite::unbox(value))
  }

  value
}

record_to_scalars <- function(values) {
  lapply(values, json_scalar)
}

rows_to_records <- function(rows) {
  if (!nrow(rows)) {
    return(list())
  }

  unname(lapply(seq_len(nrow(rows)), function(index) {
    record_to_scalars(as.list(rows[index, , drop = FALSE]))
  }))
}

build_stat_summary <- function(rows, stats_order = NULL) {
  if (!nrow(rows)) {
    return(data.frame(
      stat = character(),
      total_value = numeric(),
      average_value = numeric(),
      matches_played = integer()
    ))
  }

  stats <- unique(as.character(rows$stat))
  if (is.null(stats_order)) {
    stats <- sort(stats)
  } else {
    stats <- stats_order[stats_order %in% stats]
  }

  summary_rows <- lapply(stats, function(stat_name) {
    stat_rows <- rows[rows$stat == stat_name, , drop = FALSE]
    matches_played <- length(unique(stat_rows$match_id))
    total_value <- round(sum(stat_rows$value_number, na.rm = TRUE), 2)
    average_value <- if (matches_played > 0) {
      round(total_value / matches_played, 2)
    } else {
      NA_real_
    }

    data.frame(
      stat = stat_name,
      total_value = total_value,
      average_value = average_value,
      matches_played = as.integer(matches_played),
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, summary_rows)
}

build_player_profile_payload <- function(player_row, stats_rows) {
  available_stats <- if (nrow(stats_rows)) {
    sort(unique(as.character(stats_rows$stat)))
  } else {
    character()
  }

  games_played <- if (nrow(stats_rows)) {
    length(unique(stats_rows$match_id))
  } else {
    0L
  }
  season_values <- if (nrow(stats_rows)) {
    sort(unique(stats_rows$season), decreasing = TRUE)
  } else {
    integer()
  }
  squad_names <- if (nrow(stats_rows)) {
    sort(unique(as.character(stats_rows$squad_name)))
  } else {
    character()
  }

  season_summaries <- unname(lapply(season_values, function(season_value) {
    season_rows <- stats_rows[stats_rows$season == season_value, , drop = FALSE]
    list(
      season = jsonlite::unbox(as.integer(season_value)),
      matches_played = jsonlite::unbox(as.integer(length(unique(season_rows$match_id)))),
      squad_names = sort(unique(as.character(season_rows$squad_name))),
      stats = rows_to_records(build_stat_summary(season_rows, available_stats))
    )
  }))

  list(
    player = record_to_scalars(as.list(player_row[1, , drop = FALSE])),
    overview = list(
      games_played = jsonlite::unbox(as.integer(games_played)),
      seasons_played = jsonlite::unbox(as.integer(length(season_values))),
      teams_played = jsonlite::unbox(as.integer(length(squad_names))),
      first_season = json_scalar(if (length(season_values)) min(season_values) else NA_integer_),
      last_season = json_scalar(if (length(season_values)) max(season_values) else NA_integer_),
      squad_names = squad_names
    ),
    available_stats = available_stats,
    career_stats = rows_to_records(build_stat_summary(stats_rows, available_stats)),
    season_summaries = season_summaries
  )
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
    refreshed_at = meta_json_scalar(metadata$value[metadata$key == "refreshed_at"]),
    build_mode = meta_json_scalar(metadata$value[metadata$key == "build_mode"])
  )
}

#* @get /meta
#* @get /api/meta
function(res) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
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
    team_stats = metadata_stat_catalog(metadata_map, "team_stats_json", DEFAULT_TEAM_STATS),
    player_stats = metadata_stat_catalog(metadata_map, "player_stats_json", DEFAULT_PLAYER_STATS),
    build_mode = meta_json_scalar(metadata_map[["build_mode"]], default = "production"),
    refreshed_at = meta_json_scalar(metadata_map[["refreshed_at"]]),
    telemetry = list(
      provider = meta_json_scalar(if (browser_telemetry_enabled()) "appinsights" else "none"),
      browser_enabled = meta_json_scalar(browser_telemetry_enabled()),
      connection_string = if (browser_telemetry_enabled()) meta_json_scalar(browser_telemetry_connection_string()) else NULL
    )
  )
}

#* @post /telemetry
#* @post /api/telemetry
function(req, res) {
  if (!browser_telemetry_enabled()) {
    res$status <- 204
    return(list())
  }

  result <- tryCatch({
    telemetry_request <- parse_browser_telemetry_request(req)
    forward_browser_telemetry(telemetry_request$kind, telemetry_request$payload, req)
    api_log(
      "INFO",
      "browser_telemetry_forwarded",
      kind = telemetry_request$kind,
      name = telemetry_request$payload$name
    )
    res$status <- 202
    list(ok = jsonlite::unbox(TRUE))
  }, error = function(error) {
    api_log(
      "WARN",
      "browser_telemetry_rejected",
      error_class = class(error)[[1]] %||% "unknown"
    )
    json_error(res, 400, conditionMessage(error))
  })

  result
}

#* @get /players
#* @get /api/players
function(search = "", limit = "500", res) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  tryCatch({
    limit <- parse_limit(limit, default = 500L, maximum = 1000L)
    parsed_search <- parse_search(search, name = "search")

    query <- paste(
      "SELECT players.player_id, players.canonical_name AS player_name, players.search_name,",
      "players.short_display_name",
      "FROM players",
      "WHERE 1 = 1"
    )
    params <- list()

    if (!is.null(parsed_search)) {
      params$search <- paste0("%", normalize_player_search_name(parsed_search), "%")
      query <- paste0(query, " AND players.search_name LIKE ?search")
    }

    query <- paste0(
      query,
      " ORDER BY players.canonical_name ASC LIMIT ?limit"
    )
    params$limit <- limit

    list(data = query_rows(conn, query, params))
  }, error = function(error) {
    handle_request_error(error, res)
  })
}

#* @get /player-profile
#* @get /api/player-profile
function(player_id = "", res) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  tryCatch({
    player_id <- parse_optional_int(player_id, "player_id", minimum = 1L)
    if (is.null(player_id)) {
      stop("player_id is required.", call. = FALSE)
    }

    player <- query_rows(
      conn,
      paste(
        "SELECT player_id, firstname, surname, short_display_name, player_name, canonical_name, search_name",
        "FROM players",
        "WHERE player_id = ?player_id",
        "LIMIT 1"
      ),
      list(player_id = player_id)
    )
    if (!nrow(player)) {
      return(json_error(res, 404, "Player not found."))
    }

    stats_rows <- query_rows(
      conn,
      paste(
        "SELECT match_id, season, squad_name, stat, value_number",
        "FROM player_period_stats",
        "WHERE player_id = ?player_id AND value_number IS NOT NULL"
      ),
      list(player_id = player_id)
    )

    build_player_profile_payload(player, stats_rows)
  }, error = function(error) {
    handle_request_error(error, res)
  })
}

#* @get /summary
#* @get /api/summary
function(season = "", seasons = "", team_id = "", round = "", res) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
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
    handle_request_error(error, res)
  })

  result
}

#* @get /matches
#* @get /api/matches
function(season = "", seasons = "", team_id = "", round = "", limit = "12", res) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
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
    handle_request_error(error, res)
  })
}

#* @get /team-leaders
#* @get /api/team-leaders
function(season = "", seasons = "", team_id = "", round = "", stat = "points", metric = "total", ranking = "highest", limit = "8", res) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  tryCatch({
    seasons <- parse_season_filter(season, seasons)
    team_id <- parse_optional_int(team_id, "team_id", minimum = 1L)
    round <- parse_optional_int(round, "round", minimum = 1L, maximum = 30L)
    limit <- parse_limit(limit, default = 8L, maximum = 25L)
    stat <- validate_stat(conn, "team_period_stats", stat, default_stat = "points")
    metric <- parse_metric(metric)
    ranking <- parse_ranking_mode(ranking)
    order_column <- if (identical(metric, "average")) "average_value" else "total_value"
    order_direction <- ranking_order_sql(ranking)

    query <- paste(
      "SELECT squad_id, squad_name, ?stat AS stat, ROUND(CAST(SUM(value_number) AS numeric), 2) AS total_value,",
      "COUNT(DISTINCT match_id) AS matches_played,",
      "ROUND(CAST(SUM(value_number) AS numeric) / NULLIF(COUNT(DISTINCT match_id), 0), 2) AS average_value",
      "FROM team_period_stats WHERE stat = ?stat"
    )
    filters <- apply_stat_filters(query, list(stat = stat), seasons, team_id, round)
    filters$query <- paste0(
      filters$query,
      " GROUP BY squad_id, squad_name ORDER BY ", order_column, " ", order_direction, ", squad_name ASC LIMIT ?limit"
    )
    filters$params$limit <- limit

    rows <- query_rows(conn, filters$query, filters$params)
    list(data = apply_metric_value(rows, metric))
  }, error = function(error) {
    handle_request_error(error, res)
  })
}

#* @get /player-leaders
#* @get /api/player-leaders
function(season = "", seasons = "", team_id = "", round = "", stat = "points", search = "", metric = "total", ranking = "highest", limit = "12", res) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  tryCatch({
    seasons <- parse_season_filter(season, seasons)
    team_id <- parse_optional_int(team_id, "team_id", minimum = 1L)
    round <- parse_optional_int(round, "round", minimum = 1L, maximum = 30L)
    limit <- parse_limit(limit, default = 12L, maximum = 50L)
    stat <- validate_stat(conn, "player_period_stats", stat, default_stat = "points")
    metric <- parse_metric(metric)
    ranking <- parse_ranking_mode(ranking)
    rows <- fetch_player_leader_rows(
      conn,
      seasons = seasons,
      team_id = team_id,
      round = round,
      stat = stat,
      search = search,
      metric = metric,
      ranking = ranking,
      limit = limit
    )

    list(data = apply_metric_value(rows, metric))
  }, error = function(error) {
    handle_request_error(error, res)
  })
}

#* @get /competition-season-series
#* @get /api/competition-season-series
function(season = "", seasons = "", round = "", stat = "points", metric = "total", res) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  tryCatch({
    seasons <- parse_season_filter(season, seasons)
    round <- parse_optional_int(round, "round", minimum = 1L, maximum = 30L)
    stat <- validate_stat(conn, "team_period_stats", stat, default_stat = "points")
    metric <- parse_metric(metric)

    query <- paste(
      "SELECT season, ?stat AS stat, ROUND(CAST(SUM(value_number) AS numeric), 2) AS total_value,",
      "COUNT(DISTINCT match_id) AS matches_played,",
      "ROUND(CAST(SUM(value_number) AS numeric) / NULLIF(COUNT(DISTINCT match_id), 0), 2) AS average_value",
      "FROM team_period_stats WHERE stat = ?stat"
    )
    filters <- apply_stat_filters(query, list(stat = stat), seasons, NULL, round)
    filters$query <- paste0(
      filters$query,
      " GROUP BY season ORDER BY season ASC"
    )

    rows <- query_rows(conn, filters$query, filters$params)
    list(data = apply_metric_value(rows, metric))
  }, error = function(error) {
    handle_request_error(error, res)
  })
}

#* @get /team-season-series
#* @get /api/team-season-series
function(season = "", seasons = "", team_id = "", round = "", stat = "points", metric = "total", ranking = "highest", limit = "10", res) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  tryCatch({
    seasons <- parse_season_filter(season, seasons)
    team_id <- parse_optional_int(team_id, "team_id", minimum = 1L)
    round <- parse_optional_int(round, "round", minimum = 1L, maximum = 30L)
    limit <- parse_limit(limit, default = 10L, maximum = 10L)
    stat <- validate_stat(conn, "team_period_stats", stat, default_stat = "points")
    metric <- parse_metric(metric)
    ranking <- parse_ranking_mode(ranking)
    ranked_order_column <- if (identical(metric, "average")) "average_value" else "grand_total"
    series_order_column <- if (identical(metric, "average")) "average_value" else "total_value"
    ranked_order_direction <- ranking_order_sql(ranking)
    series_order_direction <- ranking_order_sql(ranking)

    ranked_query <- paste(
      "SELECT squad_id, ROUND(CAST(SUM(value_number) AS numeric), 2) AS grand_total,",
      "COUNT(DISTINCT match_id) AS matches_played,",
      "ROUND(CAST(SUM(value_number) AS numeric) / NULLIF(COUNT(DISTINCT match_id), 0), 2) AS average_value",
      "FROM team_period_stats WHERE stat = ?stat"
    )
    ranked_filters <- apply_stat_filters(ranked_query, list(stat = stat), seasons, team_id, round)
    ranked_filters$query <- paste0(
      ranked_filters$query,
      " GROUP BY squad_id ORDER BY ", ranked_order_column, " ", ranked_order_direction, ", squad_id ASC"
    )
    if (is.null(team_id)) {
      ranked_filters$query <- paste0(ranked_filters$query, " LIMIT ?limit")
      ranked_filters$params$limit <- limit
    }
    ranked_ids <- query_rows(conn, ranked_filters$query, ranked_filters$params)$squad_id

    query <- paste(
      "SELECT stats.squad_id, stats.squad_name, teams.squad_colour, stats.season, ?stat AS stat,",
      "ROUND(CAST(SUM(stats.value_number) AS numeric), 2) AS total_value,",
      "COUNT(DISTINCT stats.match_id) AS matches_played,",
      "ROUND(CAST(SUM(stats.value_number) AS numeric) / NULLIF(COUNT(DISTINCT stats.match_id), 0), 2) AS average_value",
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
      " ORDER BY stats.season ASC, ", series_order_column, " ", series_order_direction, ", stats.squad_name ASC"
    )

    rows <- query_rows(conn, filters$query, filters$params)
    list(data = apply_metric_value(rows, metric))
  }, error = function(error) {
    handle_request_error(error, res)
  })
}

#* @get /player-season-series
#* @get /api/player-season-series
function(season = "", seasons = "", team_id = "", round = "", stat = "points", search = "", metric = "total", ranking = "highest", limit = "10", res) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  tryCatch({
    seasons <- parse_season_filter(season, seasons)
    team_id <- parse_optional_int(team_id, "team_id", minimum = 1L)
    round <- parse_optional_int(round, "round", minimum = 1L, maximum = 30L)
    limit <- parse_limit(limit, default = 10L, maximum = 10L)
    stat <- validate_stat(conn, "player_period_stats", stat, default_stat = "points")
    metric <- parse_metric(metric)
    ranking <- parse_ranking_mode(ranking)
    rows <- fetch_player_season_metric_rows(
      conn,
      seasons = seasons,
      team_id = team_id,
      round = round,
      stat = stat,
      search = search
    )
    ranked_ids <- top_player_ids_from_series_rows(rows, metric, ranking = ranking, limit = limit)
    if (length(ranked_ids)) {
      rows <- rows[rows$player_id %in% ranked_ids, , drop = FALSE]
    } else {
      rows <- rows[0, , drop = FALSE]
    }
    rows <- sort_player_series_rows(rows, metric, ranking = ranking)

    list(data = apply_metric_value(rows, metric))
  }, error = function(error) {
    handle_request_error(error, res)
  })
}

#* @get /team-game-highs
#* @get /api/team-game-highs
function(season = "", seasons = "", team_id = "", round = "", stat = "points", limit = "10", res) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  tryCatch({
    seasons <- parse_season_filter(season, seasons)
    team_id <- parse_optional_int(team_id, "team_id", minimum = 1L)
    round <- parse_optional_int(round, "round", minimum = 1L, maximum = 30L)
    limit <- parse_limit(limit, default = 10L, maximum = 50L)
    stat <- validate_stat(conn, "team_period_stats", stat, default_stat = "points")

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
    handle_request_error(error, res)
  })
}

#* @get /player-game-highs
#* @get /api/player-game-highs
function(season = "", seasons = "", team_id = "", round = "", stat = "points", search = "", limit = "10", res) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  tryCatch({
    seasons <- parse_season_filter(season, seasons)
    team_id <- parse_optional_int(team_id, "team_id", minimum = 1L)
    round <- parse_optional_int(round, "round", minimum = 1L, maximum = 30L)
    limit <- parse_limit(limit, default = 10L, maximum = 50L)
    stat <- validate_stat(conn, "player_period_stats", stat, default_stat = "points")
    list(data = fetch_player_game_high_rows(
      conn,
      seasons = seasons,
      team_id = team_id,
      round = round,
      stat = stat,
      search = search,
      limit = limit
    ))
  }, error = function(error) {
    handle_request_error(error, res)
  })
}

#* @get /query
#* @get /api/query
function(question = "", limit = "12", res) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  tryCatch({
    limit <- parse_limit(limit, default = 12L, maximum = 25L)
    intent <- parse_query_intent(conn, question, limit = limit)
    if (!identical(intent$status, "supported")) {
      return(intent)
    }

    all_rows <- fetch_query_result_rows(conn, intent)
    total_matches <- nrow(all_rows)
    order_direction <- if (identical(intent$intent_type, "lowest")) "ASC" else "DESC"
    row_limit <- if (identical(intent$intent_type, "count")) {
      min(intent$limit, 12L)
    } else if (identical(intent$intent_type, "list")) {
      intent$limit
    } else {
      1L
    }
    rows <- if (nrow(all_rows)) {
      all_rows[seq_len(min(nrow(all_rows), row_limit)), , drop = FALSE]
    } else {
      all_rows
    }

    list(
      status = jsonlite::unbox("supported"),
      question = jsonlite::unbox(intent$question),
      answer = jsonlite::unbox(build_query_answer(intent, rows, total_matches)),
      parsed = record_to_scalars(list(
        intent_type = intent$intent_type,
        subject_type = intent$subject_type,
        player_name = intent$player_name,
        team_name = intent$team_name,
        stat = intent$stat,
        stat_label = intent$stat_label,
        comparison = intent$comparison,
        comparison_label = intent$comparison_label,
        threshold = intent$threshold,
        opponent_name = intent$opponent_name,
        seasons = intent$seasons,
        season = intent$season,
        limit = intent$limit
      )),
      summary = record_to_scalars(list(
        question_type = intent$intent_type,
        match_count = total_matches,
        row_count = nrow(rows),
        stat_label = intent$stat_label
      )),
      rows = rows_to_records(rows)
    )
  }, error = function(error) {
    handle_request_error(error, res)
  })
}
