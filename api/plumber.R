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
source(file.path(repo_root_path, "R", "player_reference.R"), local = TRUE)
source(file.path(repo_root_path, "api", "R", "helpers.R"), local = TRUE)

# Shared in-process cache for /meta responses (30-minute TTL).
.meta_cache <- new.env(parent = emptyenv())

request_limiter <- local({
  entries <- new.env(parent = emptyenv())
  # Cache rate-limit config at build time — Sys.getenv is called once, not
  # on every request, since these values don't change while the process is live.
  window_seconds <- as.integer(Sys.getenv("NETBALL_STATS_RATE_LIMIT_WINDOW_SECONDS", "60"))
  max_requests   <- as.integer(Sys.getenv("NETBALL_STATS_RATE_LIMIT_MAX_REQUESTS", "60"))
  prune_interval <- 600L   # prune stale entries every 10 minutes
  last_prune     <- as.numeric(Sys.time())

  function(req, res) {
    # Use only the leftmost (originating-client) IP from X-Forwarded-For to
    # prevent spoofing via attacker-appended values.
    client_key <- resolve_request_client_key(req$HTTP_X_FORWARDED_FOR, req$REMOTE_ADDR)
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

    # Periodically prune stale entries so the env doesn't grow indefinitely.
    if ((now - last_prune) > prune_interval) {
      stale <- Filter(
        function(k) (now - get(k, envir = entries)$start) > window_seconds,
        ls(envir = entries)
      )
      if (length(stale)) rm(list = stale, envir = entries)
      last_prune <<- now
    }

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
  "player-profile",
  "round-recap"
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
  raw_ip  <- req$HTTP_X_FORWARDED_FOR %||% req$REMOTE_ADDR %||% "unknown"
  # Anonymise before forwarding: zero last octet (IPv4) or last 80 bits (IPv6)
  client_ip <- if (grepl("^\\d+\\.\\d+\\.\\d+\\.\\d+$", raw_ip)) {
    sub("(\\d+\\.\\d+\\.\\d+\\.)\\d+", "\\10", raw_ip)
  } else if (grepl(":", raw_ip)) {
    parts <- strsplit(raw_ip, ":")[[1]]
    if (length(parts) >= 5) {
      paste0(c(head(parts, max(length(parts) - 5, 3)), rep("0", min(5, length(parts) - 3))), collapse = ":")
    } else raw_ip
  } else {
    raw_ip
  }
  client_ip <- telemetry_trim_string(client_ip, 80L)

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

handle_request_error <- function(error, res, timeout_message = "The query took too long. Try narrowing to a specific season or player.") {
  msg <- conditionMessage(error)
  timeout <- grepl("statement timeout|canceling statement|query_canceled", msg, ignore.case = TRUE)
  api_log(
    if (timeout) "WARN" else "INFO",
    if (timeout) "request_timeout" else "request_rejected",
    error_class = class(error)[[1]] %||% "unknown",
    error_message = substr(msg, 1L, 200L)
  )
  if (timeout) {
    json_error(res, 503, timeout_message)
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

scoreflow_table_unavailable <- function(res) {
  api_log("WARN", "scoreflow_table_missing",
          error_message = "match_scoreflow_summary not found; database may need rebuilding.")
  json_error(res, 503, "Scoreflow analytics are not yet available. The database requires a current build.")
}

build_meta_payload <- function(conn) {
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
      browser_enabled = meta_json_scalar(browser_telemetry_enabled())
    )
  )
}

meta_statement_timeout_ms <- function() {
  parse_nonnegative_env_int("NETBALL_STATS_DB_META_STATEMENT_TIMEOUT_MS", 25000L)
}

home_venue_statement_timeout_ms <- function() {
  parse_nonnegative_env_int("NETBALL_STATS_DB_HOME_VENUE_STATEMENT_TIMEOUT_MS", 25000L)
}

home_venue_breakdown_statement_timeout_ms <- function() {
  parse_nonnegative_env_int("NETBALL_STATS_DB_HOME_VENUE_BREAKDOWN_STATEMENT_TIMEOUT_MS", 45000L)
}

json_scalar <- function(value) {
  if (is.null(value) || length(value) == 0L) {
    return(NULL)
  }

  if (!is.list(value) && length(value) == 1L) {
    return(jsonlite::unbox(unname(value[[1L]])))
  }

  value
}

serializer_unboxed_json_null_na <- function(...) {
  plumber::serializer_unboxed_json(na = "null", ...)
}

plumber::register_serializer("unboxedJSONNullNA", serializer_unboxed_json_null_na)

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

build_player_profile_payload <- function(player_row, stats_rows, identity_row = NULL) {
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

  # Build the identity block from the optional player_reference/demographics row.
  # Helpers to safely extract a typed field value from the identity row.
  ir <- if (!is.null(identity_row) && nrow(identity_row) > 0L) {
    identity_row[1L, , drop = FALSE]
  } else {
    NULL
  }
  ir_str <- function(col) {
    if (is.null(ir)) return(json_scalar(NA_character_))
    val <- ir[[col]]
    if (is.null(val) || length(val) == 0L || all(is.na(val))) return(json_scalar(NA_character_))
    json_scalar(as.character(val[[1L]]))
  }
  ir_int <- function(col) {
    if (is.null(ir)) return(json_scalar(NA_integer_))
    val <- ir[[col]]
    if (is.null(val) || length(val) == 0L || all(is.na(val))) return(json_scalar(NA_integer_))
    json_scalar(as.integer(val[[1L]]))
  }
  ir_date <- function(col) {
    if (is.null(ir)) return(json_scalar(NA_character_))
    val <- ir[[col]]
    if (is.null(val) || length(val) == 0L || all(is.na(val))) return(json_scalar(NA_character_))
    json_scalar(format(as.Date(val[[1L]]), "%Y-%m-%d"))
  }
  # reference_status: "maintained" when the player_reference row exists and has
  # import_status populated; "missing" otherwise.
  has_maintained_reference <- !is.null(ir) && {
    s <- ir[["import_status"]]
    !is.null(s) && length(s) > 0L && !all(is.na(s))
  }

  identity <- list(
    date_of_birth      = ir_date("date_of_birth"),
    nationality        = ir_str("nationality"),
    import_status      = ir_str("import_status"),
    source_label       = ir_str("source_label"),
    source_url         = ir_str("source_url"),
    verified_at        = ir_date("verified_at"),
    debut_season       = ir_int("debut_season"),
    experience_seasons = ir_int("experience_seasons"),
    reference_status   = jsonlite::unbox(if (has_maintained_reference) "maintained" else "missing")
  )

  list(
    player = record_to_scalars(as.list(player_row[1, , drop = FALSE])),
    identity = identity,
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
  conn <- tryCatch(get_db_conn(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }

  # Serve from in-process cache — /meta is called on every page load and the
  # data changes only after a DB rebuild (roughly weekly).
  cached <- .meta_cache[["meta"]]
  if (!is.null(cached) &&
      as.numeric(difftime(Sys.time(), cached$ts, units = "secs")) < 1800L) {
    return(cached$payload)
  }

  tryCatch({
    payload <- with_statement_timeout(conn, meta_statement_timeout_ms(), build_meta_payload(conn))
    .meta_cache[["meta"]] <- list(payload = payload, ts = Sys.time())
    payload
  }, error = function(error) {
    api_log(
      "WARN",
      "meta_fetch_failed",
      error_class = class(error)[[1]] %||% "unknown",
      error_message = substr(conditionMessage(error), 1L, 200L),
      served_stale_cache = !is.null(cached)
    )
    if (!is.null(cached)) {
      return(cached$payload)
    }
    json_error(res, 503, "Metadata is temporarily unavailable. Try again shortly.")
  })
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
function(search = "", limit = "2000", res) {
  conn <- tryCatch(get_db_conn(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }

  tryCatch({
    limit <- parse_limit(limit, default = 2000L, maximum = 2000L)
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
  conn <- tryCatch(get_db_conn(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }

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

    has_participation <- has_player_match_stats(conn) && has_player_match_participation(conn)
    stats_rows <- if (has_player_match_stats(conn)) {
      participation_join <- if (has_participation) {
        "INNER JOIN player_match_participation pmpart ON pmpart.player_id = stats.player_id AND pmpart.match_id = stats.match_id"
      } else {
        ""
      }
      query_rows(
        conn,
        paste(
          "SELECT stats.match_id, stats.season, stats.squad_name, stats.stat, stats.match_value AS value_number",
          "FROM player_match_stats stats",
          participation_join,
          "WHERE stats.player_id = ?player_id AND stats.match_value IS NOT NULL"
        ),
        list(player_id = player_id)
      )
    } else {
      query_rows(
        conn,
        paste(
          "SELECT match_id, season, squad_name, stat, value_number",
          "FROM player_period_stats",
          "WHERE player_id = ?player_id AND value_number IS NOT NULL"
        ),
        list(player_id = player_id)
      )
    }

    # Fetch identity row via LEFT JOIN over player_reference (and optionally
    # player_season_demographics for experience_seasons). Both tables are optional;
    # when absent the identity block is returned with all-NA fields.
    identity_row <- if (has_player_reference(conn)) {
      experience_col <- if (has_player_season_demographics(conn)) {
        paste(
          "       (SELECT MAX(psd.experience_seasons)",
          "        FROM player_season_demographics psd",
          "        WHERE psd.player_id = p.player_id) AS experience_seasons"
        )
      } else {
        "       NULL AS experience_seasons"
      }
      query_rows(
        conn,
        paste(
          "SELECT pr.date_of_birth, pr.nationality, pr.import_status,",
          "       pr.source_label, pr.source_url, pr.verified_at, pr.debut_season,",
          experience_col,
          "FROM players p",
          "LEFT JOIN player_reference pr ON pr.player_id = p.player_id",
          "WHERE p.player_id = ?player_id",
          "LIMIT 1"
        ),
        list(player_id = player_id)
      )
    } else {
      NULL
    }

    build_player_profile_payload(player, stats_rows, identity_row)
  }, error = function(error) {
    handle_request_error(error, res)
  })
}

#* @get /summary
#* @get /api/summary
function(season = "", seasons = "", team_id = "", round = "", res) {
  conn <- tryCatch(get_db_conn(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }

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
  conn <- tryCatch(get_db_conn(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }

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

#* @get /round-summary
#* @get /api/round-summary
function(season = "", round = "", res) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  DBI::dbExecute(
    conn,
    sprintf(
      "SET statement_timeout TO %d",
      parse_nonnegative_env_int("NETBALL_STATS_ROUND_SUMMARY_TIMEOUT_MS", 15000L)
    )
  )

  tryCatch({
    season <- parse_optional_int(season, "season", minimum = 2017L, maximum = 2100L)
    round <- parse_optional_int(round, "round", minimum = 1L, maximum = 30L)

    if (!is.null(round) && is.null(season)) {
      stop("season is required when round is provided.", call. = FALSE)
    }

    payload <- build_round_summary_payload(conn, season = season, round = round)
    if (is.null(payload)) {
      return(json_error(res, 404, "No completed round is available for that selection."))
    }

    payload
  }, error = function(error) {
    handle_request_error(error, res)
  })
}

#* @get /round-preview-summary
#* @get /api/round-preview-summary
function(season = "", res) {
  conn <- tryCatch(open_db(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  tryCatch({
    season <- parse_optional_int(season, "season", minimum = 2017L, maximum = 2100L)

    payload <- build_round_preview_payload(conn, season = season)
    if (is.null(payload)) {
      return(json_error(res, 404, "No upcoming round is available for that selection."))
    }

    payload
  }, error = function(error) {
    handle_request_error(error, res, timeout_message = "Round preview took too long to load. Try again shortly.")
  })
}

#* @get /team-leaders
#* @get /api/team-leaders
function(season = "", seasons = "", team_id = "", round = "", stat = "points", metric = "total", ranking = "highest", limit = "8", res) {
  conn <- tryCatch(get_db_conn(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }

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
  conn <- tryCatch(get_db_conn(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }

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
  conn <- tryCatch(get_db_conn(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }

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
  conn <- tryCatch(get_db_conn(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }

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
  conn <- tryCatch(get_db_conn(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }

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
function(season = "", seasons = "", team_id = "", round = "", stat = "points", ranking = "highest", limit = "10", res) {
  conn <- tryCatch(get_db_conn(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }

  tryCatch({
    seasons <- parse_season_filter(season, seasons)
    team_id <- parse_optional_int(team_id, "team_id", minimum = 1L)
    round <- parse_optional_int(round, "round", minimum = 1L, maximum = 30L)
    limit <- parse_limit(limit, default = 10L, maximum = 50L)
    stat <- validate_stat(conn, "team_period_stats", stat, default_stat = "points")
    ranking <- parse_ranking_mode(ranking)
    list(data = fetch_team_game_high_rows(
      conn,
      seasons = seasons,
      team_id = team_id,
      round = round,
      stat = stat,
      ranking = ranking,
      limit = limit
    ))
  }, error = function(error) {
    handle_request_error(error, res)
  })
}

#* @get /player-game-highs
#* @get /api/player-game-highs
function(season = "", seasons = "", team_id = "", round = "", stat = "points", search = "", ranking = "highest", limit = "10", res) {
  conn <- tryCatch(get_db_conn(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }

  tryCatch({
    seasons <- parse_season_filter(season, seasons)
    team_id <- parse_optional_int(team_id, "team_id", minimum = 1L)
    round <- parse_optional_int(round, "round", minimum = 1L, maximum = 30L)
    limit <- parse_limit(limit, default = 10L, maximum = 50L)
    stat <- validate_stat(conn, "player_period_stats", stat, default_stat = "points")
    ranking <- parse_ranking_mode(ranking)
    list(data = fetch_player_game_high_rows(
      conn,
      seasons = seasons,
      team_id = team_id,
      round = round,
      stat = stat,
      search = search,
      ranking = ranking,
      limit = limit
    ))
  }, error = function(error) {
    handle_request_error(error, res)
  })
}

#* @get /query
#* @get /api/query
function(question = "", limit = "12", res) {
  conn <- tryCatch(get_db_conn(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }

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

#* @get /home-venue-impact
#* @get /api/home-venue-impact
#* @summary Home venue impact summary
#* @param season Optional single season year (e.g. 2023). Overridden by seasons.
#* @param seasons Optional comma-separated season years (e.g. 2022,2023).
#* @param team_id Optional integer squad/team ID to filter team-perspective rows.
#* @param venue_name Optional exact venue name filter.
#* @param min_matches Minimum grouped matches required for inclusion (default 5, max 100).
#* @param limit Maximum grouped rows to return per table section (default 50, max 50).
function(season = "", seasons = "", team_id = "", venue_name = "", min_matches = "5", limit = "50", res) {
  conn <- tryCatch(get_db_conn(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }

  tryCatch({
    effective_seasons <- parse_season_filter(season, seasons)
    team_id <- parse_optional_int(team_id, "team_id", minimum = 1L)
    venue_name <- parse_optional_text(venue_name, "venue_name", max_length = 120L)
    min_matches <- parse_optional_int(min_matches, "min_matches", minimum = 1L, maximum = 100L) %||% 5L
    limit <- parse_limit(limit, default = 50L, maximum = 50L)

    summary <- with_statement_timeout(
      conn,
      home_venue_statement_timeout_ms(),
      fetch_home_venue_impact_summary(
        conn,
        seasons = effective_seasons,
        team_id = team_id,
        venue_name = venue_name,
        min_matches = min_matches,
        limit = limit
      )
    )

    list(
      filters = list(
        seasons = if (is.null(effective_seasons)) list() else as.list(as.integer(effective_seasons)),
        team_id = team_id,
        venue_name = venue_name %||% "",
        min_matches = min_matches,
        limit = limit
      ),
      league_summary = summary$league_summary,
      team_summary = rows_to_records(summary$team_summary),
      venue_summary = rows_to_records(summary$venue_summary),
      team_venue_summary = rows_to_records(summary$team_venue_summary)
    )
  }, error = function(error) {
    handle_request_error(error, res)
  })
}

#* @get /home-venue-breakdown
#* @get /api/home-venue-breakdown
#* @serializer unboxedJSONNullNA
#* @summary Home venue stat breakdown
#* @param season Optional single season year (e.g. 2023). Overridden by seasons.
#* @param seasons Optional comma-separated season years (e.g. 2022,2023).
#* @param team_id Optional integer squad/team ID to filter team-perspective rows.
#* @param venue_name Optional exact venue name filter.
#* @param stat_groups Optional comma-separated stat groups. Supported groups: generalPlayTurnovers, contactPenalties, obstructionPenalties, penalties, heldBalls.
#* @param min_matches Minimum grouped matches required for inclusion (default 5, max 100).
#* @param limit Maximum grouped rows to return per table section (default 50, max 50).
function(season = "", seasons = "", team_id = "", venue_name = "", stat_groups = "", min_matches = "5", limit = "50", res) {
  conn <- tryCatch(get_db_conn(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }

  tryCatch({
    effective_seasons <- parse_season_filter(season, seasons)
    team_id <- parse_optional_int(team_id, "team_id", minimum = 1L)
    venue_name <- parse_optional_text(venue_name, "venue_name", max_length = 120L)
    stat_groups <- parse_optional_text(stat_groups, "stat_groups", max_length = 180L)
    min_matches <- parse_optional_int(min_matches, "min_matches", minimum = 1L, maximum = 100L) %||% 5L
    limit <- parse_limit(limit, default = 50L, maximum = 50L)

    summary <- with_statement_timeout(
      conn,
      home_venue_breakdown_statement_timeout_ms(),
      fetch_home_venue_breakdown(
        conn,
        seasons = effective_seasons,
        team_id = team_id,
        venue_name = venue_name,
        stat_groups = stat_groups,
        min_matches = min_matches,
        limit = limit
      )
    )

    list(
      filters = summary$filters,
      stat_summary = rows_to_records(summary$stat_summary),
      opposition_summary_overall = rows_to_records(summary$opposition_summary_overall),
      opposition_summary_by_stat = rows_to_records(summary$opposition_summary_by_stat),
      team_venue_stat_summary = rows_to_records(summary$team_venue_stat_summary)
    )
  }, error = function(error) {
    handle_request_error(error, res)
  })
}

#* @get /nwar
#* @get /api/nwar
#* @summary Netball Wins Above Replacement leaderboard
#* @param season Optional single season year (e.g. 2023). Overridden by seasons.
#* @param seasons Optional comma-separated season years (e.g. 2022,2023).
#* @param team_id Optional integer squad/team ID to filter players.
#* @param era Optional era bucket: anzc (2008-2016) or ssn (2017+).
#* @param position_group Optional dominant position group: shooter, midcourt, or defender.
#* @param min_games Minimum qualifying matches for inclusion (default 5, max 100).
#* @param limit Maximum rows to return (default 50, max 100).
function(season = "", seasons = "", team_id = "", era = "", position_group = "", min_games = "5", limit = "50", res) {
  conn <- tryCatch(get_db_conn(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }

  tryCatch({
    explicit_seasons <- parse_season_filter(season, seasons)
    era <- parse_nwar_era(era)
    position_group <- parse_nwar_position_group(position_group)
    effective_seasons <- explicit_seasons %||% seasons_from_nwar_era(era)
    team_id <- parse_optional_int(team_id, "team_id", minimum = 1L)
    min_games <- parse_limit(min_games, default = 5L, maximum = 100L)
    limit <- parse_limit(limit, default = 50L, maximum = 100L)

    rows <- fetch_nwar_rows(
      conn,
      seasons = effective_seasons,
      team_id = team_id,
      min_games = min_games,
      limit = limit,
      position_group = position_group
    )
    list(data = rows_to_records(rows))
  }, error = function(error) {
    handle_request_error(error, res)
  })
}

#* @get /scoreflow-game-records
#* @get /api/scoreflow-game-records
#* @serializer unboxedJSONNullNA
#* @summary Scoreflow game records — team-match level scoreflow analytics
#* @param season Optional single season year (e.g. 2023). Overridden by seasons.
#* @param seasons Optional comma-separated season years (e.g. 2022,2023).
#* @param team_id Optional integer squad ID to filter to that team's perspective rows.
#* @param opponent_id Optional integer squad ID to filter by the opposing team.
#* @param metric Metric to rank by. One of: comeback_deficit_points (default), largest_lead_points, deepest_deficit_points, seconds_leading, seconds_trailing, trailing_share.
#* @param scenario Optional scenario filter. One of: all (default), comeback_wins, won_trailing_most, trailed_most, wins.
#* @param limit Maximum rows to return (default 25, max 100).
function(season = "", seasons = "", team_id = "", opponent_id = "", metric = "", scenario = "", limit = "25", res) {
  conn <- tryCatch(get_db_conn(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }
  if (!has_match_scoreflow_summary(conn)) {
    return(scoreflow_table_unavailable(res))
  }

  tryCatch({
    effective_seasons <- parse_season_filter(season, seasons)
    team_id           <- parse_optional_int(team_id, "team_id", minimum = 1L)
    opponent_id       <- parse_optional_int(opponent_id, "opponent_id", minimum = 1L)
    metric            <- parse_scoreflow_metric(metric)
    scenario          <- parse_scoreflow_scenario(scenario)
    limit             <- parse_limit(limit, default = 25L, maximum = 100L)

    rows <- with_statement_timeout(
      conn,
      scoreflow_statement_timeout_ms(),
      fetch_scoreflow_game_records(
        conn,
        metric      = metric,
        scenario    = scenario,
        seasons     = effective_seasons,
        team_id     = team_id,
        opponent_id = opponent_id,
        limit       = limit
      )
    )

    list(
      filters = list(
        seasons     = if (is.null(effective_seasons)) list() else as.list(as.integer(effective_seasons)),
        team_id     = team_id,
        opponent_id = opponent_id,
        metric      = jsonlite::unbox(metric),
        scenario    = jsonlite::unbox(scenario),
        limit       = limit
      ),
      data = rows_to_records(rows)
    )
  }, error = function(error) {
    handle_request_error(error, res)
  })
}

#* @get /scoreflow-team-summary
#* @get /api/scoreflow-team-summary
#* @serializer unboxedJSONNullNA
#* @summary Scoreflow team summary — per-team aggregates from match_scoreflow_summary
#* @param season Optional single season year (e.g. 2023). Overridden by seasons.
#* @param seasons Optional comma-separated season years (e.g. 2022,2023).
#* @param team_id Optional integer squad ID to restrict to a single team.
#* @param min_matches Minimum matches with scoreflow data for inclusion (default 1, max 200).
#* @param sort_by Aggregate column to rank by. One of: total_seconds_leading (default), total_seconds_trailing, games_led_most, games_trailed_most, comeback_wins, won_trailing_most, largest_comeback_win_points.
#* @param limit Maximum rows to return (default 20, max 50).
function(season = "", seasons = "", team_id = "", min_matches = "1", sort_by = "", limit = "20", res) {
  conn <- tryCatch(get_db_conn(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }
  if (!has_match_scoreflow_summary(conn)) {
    return(scoreflow_table_unavailable(res))
  }

  tryCatch({
    effective_seasons <- parse_season_filter(season, seasons)
    team_id     <- parse_optional_int(team_id, "team_id", minimum = 1L)
    min_matches <- parse_optional_int(min_matches, "min_matches", minimum = 1L, maximum = 200L) %||% 1L
    sort_by     <- parse_scoreflow_team_sort(sort_by)
    limit       <- parse_limit(limit, default = 20L, maximum = 50L)

    rows <- with_statement_timeout(
      conn,
      scoreflow_statement_timeout_ms(),
      fetch_scoreflow_team_summary(
        conn,
        seasons     = effective_seasons,
        team_id     = team_id,
        min_matches = min_matches,
        sort_by     = sort_by,
        limit       = limit
      )
    )

    list(
      filters = list(
        seasons     = if (is.null(effective_seasons)) list() else as.list(as.integer(effective_seasons)),
        team_id     = team_id,
        min_matches = min_matches,
        sort_by     = jsonlite::unbox(sort_by),
        limit       = limit
      ),
      data = rows_to_records(rows)
    )
  }, error = function(error) {
    handle_request_error(error, res)
  })
}

#* @get /scoreflow-featured-records
#* @get /api/scoreflow-featured-records
#* @serializer unboxedJSONNullNA
#* @summary Scoreflow featured records — three curated cards for the archive homepage
#* @param season Optional single season year (overridden by seasons).
#* @param seasons Optional comma-separated season years.
#* @param team_id Optional integer squad ID to focus the featured cards on one club.
function(season = "", seasons = "", team_id = "", res) {
  conn <- tryCatch(get_db_conn(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }
  if (!has_match_scoreflow_summary(conn)) {
    return(scoreflow_table_unavailable(res))
  }

  tryCatch({
    effective_seasons <- parse_season_filter(season, seasons)
    team_id <- parse_optional_int(team_id, "team_id", minimum = 1L)
    list(
      filters = list(
        seasons = if (is.null(effective_seasons)) list() else as.list(as.integer(effective_seasons)),
        team_id = team_id
      ),
      data = with_statement_timeout(
        conn,
        scoreflow_statement_timeout_ms(),
        fetch_scoreflow_featured_records(conn, seasons = effective_seasons, team_id = team_id)
      )
    )
  }, error = function(error) {
    handle_request_error(error, res)
  })
}

#* @get /league-composition-summary
#* @get /api/league-composition-summary
#* @serializer unboxedJSONNullNA
#* @summary League composition summary — per-season player count and demographic aggregates
#* @param season Optional single season year (e.g. 2023). Overridden by seasons.
#* @param seasons Optional comma-separated season years (e.g. 2022,2023).
function(season = "", seasons = "", res) {
  conn <- tryCatch(get_db_conn(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }

  tryCatch({
    effective_seasons <- parse_composition_seasons(season, seasons)
    if (!has_league_composition_summary(conn)) {
      return(json_error(res, 503, "League composition data is not yet available. The database requires a current build."))
    }
    query_league_composition_summary(conn, seasons = effective_seasons)
  }, error = function(error) {
    handle_request_error(error, res)
  })
}

#* @get /league-composition-debut-bands
#* @get /api/league-composition-debut-bands
#* @serializer unboxedJSONNullNA
#* @summary League debut age bands — per-season debut age distribution for debutants
#* @param season Optional single season year (e.g. 2023). Overridden by seasons.
#* @param seasons Optional comma-separated season years (e.g. 2022,2023).
function(season = "", seasons = "", res) {
  conn <- tryCatch(get_db_conn(), error = function(error) error)
  if (inherits(conn, "error")) {
    return(database_unavailable(res, conn))
  }

  tryCatch({
    effective_seasons <- parse_composition_seasons(season, seasons)
    if (!has_league_composition_debut_bands(conn)) {
      return(json_error(res, 503, "League composition debut band data is not yet available. The database requires a current build."))
    }
    list(data = query_league_composition_debut_bands(conn, seasons = effective_seasons))
  }, error = function(error) {
    handle_request_error(error, res)
  })
}


#* @plumber
function(pr) {
  # Startup warmup: populate in-process caches before the first request arrives.
  # Runs synchronously during process startup. Adds ~2-4s to cold-start time
  # but eliminates the first-hit DB penalty for the most common endpoints.
  tryCatch({
    conn <- get_db_conn()

    available_stats(conn, "player_period_stats")
    available_stats(conn, "team_period_stats")
    team_alias_lookup(conn)
    has_player_match_stats(conn)

    # Pre-warm /meta cache (called on every page load)
    meta_ok <- tryCatch({
      payload <- with_statement_timeout(conn, meta_statement_timeout_ms(), build_meta_payload(conn))
      .meta_cache[["meta"]] <- list(payload = payload, ts = Sys.time())
      TRUE
    }, error = function(e) FALSE)

    # Pre-warm the latest round summary (most-visited page after home)
    build_round_summary_payload(conn, season = NULL, round = NULL)

    api_log("INFO", "startup_warmup_complete", meta_ok = meta_ok)
  }, error = function(e) {
    api_log("WARN", "startup_warmup_failed",
            error_class = class(e)[[1]], error_message = substr(conditionMessage(e), 1L, 200L))
  })
}
