repo_root <- function() {
  getOption(
    "netballstats.repo_root",
    normalizePath(file.path(getwd()), mustWork = FALSE)
  )
}

resolve_request_client_key <- function(raw_forwarded, remote_addr) {
  if (is.null(raw_forwarded) || length(raw_forwarded) == 0L || all(is.na(raw_forwarded))) {
    raw_forwarded <- ""
  }

  if (is.null(remote_addr) || length(remote_addr) == 0L || all(is.na(remote_addr))) {
    remote_addr <- "unknown"
  }

  raw_forwarded <- as.character(raw_forwarded)[[1]]
  remote_addr <- as.character(remote_addr)[[1]]
  if (!nzchar(trimws(remote_addr))) {
    remote_addr <- "unknown"
  }

  if (nzchar(raw_forwarded)) {
    forwarded_token <- trimws(strsplit(raw_forwarded, ",", fixed = TRUE)[[1]][[1]])
    if (nzchar(forwarded_token)) {
      return(forwarded_token)
    }
  }

  remote_addr
}

DEFAULT_TEAM_STATS <- c(
  "attempt_from_zone1", "attempt_from_zone2", "attempts1", "attempts2",
  "badHands", "badPasses", "blocked", "blocks", "breaks",
  "centrePassReceives", "contactPenalties",
  "deflections", "deflectionWithGain", "deflectionWithNoGain",
  "disposals", "feedWithAttempt", "feeds", "gain", "generalPlayTurnovers",
  "goal1", "goal2", "goal_from_zone1", "goal_from_zone2",
  "goalAssists", "goalAttempts", "goalMisses", "goals",
  "goalsFromCentrePass", "goalsFromGain", "goalsFromTurnovers",
  "intercepts", "interceptPassThrown", "missedGoalTurnover",
  "netPoints", "obstructionPenalties", "offsides", "passes", "penalties",
  "pickups", "points", "possessionChanges", "possessions", "rebounds",
  "secondPhaseReceive", "timeInPossession", "tossUpWin",
  "turnoverHeld", "unforcedTurnovers"
)

DEFAULT_PLAYER_STATS <- c(
  "attempt_from_zone1", "attempt_from_zone2", "attempts1", "attempts2",
  "badHands", "badPasses", "blocked", "blocks", "breaks",
  "centrePassReceives", "contactPenalties",
  "defensiveRebounds", "deflections", "deflectionWithGain", "deflectionWithNoGain",
  "disposals", "feedWithAttempt", "feeds", "gain", "gamesPlayed",
  "generalPlayTurnovers", "goal1", "goal2",
  "goal_from_zone1", "goal_from_zone2",
  "goalAssists", "goalAttempts", "goalMisses", "goals", "intercepts",
  "interceptPassThrown", "minutesPlayed", "missedGoalTurnover", "netPoints",
  "obstructionPenalties", "offsides", "offensiveRebounds", "passes", "penalties",
  "pickups", "points", "possessionChanges", "possessions", "quartersPlayed", "rebounds",
  "secondPhaseReceive", "tossUpWin", "turnoverHeld", "unforcedTurnovers"
)

QUERY_STAT_DEFINITIONS <- list(
  goals = list(
    label = "Goals",
    aliases = c("goals", "scored", "score", "goal total", "goal totals")
  ),
  goalAttempts = list(
    label = "Goal Attempts",
    aliases = c("goal attempts", "attempts", "shot attempts", "shots")
  ),
  goalAssists = list(
    label = "Assists",
    aliases = c("assists", "assist", "goal assists", "goal assist")
  ),
  feeds = list(
    label = "Feeds",
    aliases = c("feeds", "feed")
  ),
  gain = list(
    label = "Gains",
    aliases = c("gains", "gain")
  ),
  intercepts = list(
    label = "Intercepts",
    aliases = c("intercepts", "intercept", "interceptions", "interception")
  ),
  netPoints = list(
    label = "NetPoints",
    aliases = c("net points", "netpoints")
  ),
  obstructionPenalties = list(
    label = "Obstructions",
    aliases = c("obstructions", "obstruction penalties", "obstruction penalty")
  ),
  contactPenalties = list(
    label = "Contacts",
    aliases = c("contacts", "contact penalties", "contact penalty")
  ),
  generalPlayTurnovers = list(
    label = "General Play Turnovers",
    aliases = c("general play turnovers", "general play turnover")
  ),
  unforcedTurnovers = list(
    label = "Unforced Turnovers",
    aliases = c("unforced turnovers", "unforced turnover")
  ),
  pickups = list(
    label = "Pickups",
    aliases = c("pickups", "pickup")
  ),
  centrePassReceives = list(
    label = "Centre Pass Receives",
    aliases = c("centre pass receives", "centre pass receive")
  ),
  deflections = list(
    label = "Deflections",
    aliases = c("deflections", "deflection")
  ),
  rebounds = list(
    label = "Rebounds",
    aliases = c("rebounds", "rebound")
  ),
  goal1 = list(
    label = "1 Point Goals",
    aliases = c("1 point goals", "one point goals", "1 point goal", "one point goal")
  ),
  attempts1 = list(
    label = "1 Point Goal Attempts",
    aliases = c("1 point goal attempts", "one point goal attempts")
  ),
  goal2 = list(
    label = "2 Point Goals",
    aliases = c("2 point goals", "two point goals", "2 point goal", "two point goal")
  ),
  attempts2 = list(
    label = "2 Point Goal Attempts",
    aliases = c("2 point goal attempts", "two point goal attempts")
  )
)

QUERY_COMPARISON_DEFINITIONS <- list(
  gte = list(label = "at least", sql = ">="),
  gt = list(label = "more than", sql = ">"),
  lte = list(label = "at most", sql = "<="),
  lt = list(label = "fewer than", sql = "<"),
  eq = list(label = "exactly", sql = "=")
)

QUERY_SUPPORTED_EXAMPLES <- c(
  "How many times has Fowler scored 50 goals or more against the Vixens?",
  "What is Fowler's highest goals total against the Swifts?",
  "Which players scored 40+ goals in 2025?",
  "How many times have the Swifts scored 70 goals or more against the Vixens?",
  "Which teams scored 70+ goals in 2025?"
)

open_db <- function() {
  open_database_connection()
}

# Persistent connection reused across requests (R Plumber is single-threaded,
# so a single connection is safe).  Falls back to a fresh connect if the
# existing connection has been closed by an idle timeout or DB failover.
.persistent_conn <- NULL

get_db_conn <- function() {
  if (!is.null(.persistent_conn) && DBI::dbIsValid(.persistent_conn)) {
    return(.persistent_conn)
  }
  if (!is.null(.persistent_conn)) {
    tryCatch(DBI::dbDisconnect(.persistent_conn), error = function(e) NULL)
  }
  .persistent_conn <<- open_database_connection()
  .persistent_conn
}

json_error <- function(res, status, message) {
  res$status <- status
  list(error = message)
}

parse_optional_int <- function(value, name, minimum = NULL, maximum = NULL) {
  if (is.null(value) || length(value) == 0L || all(is.na(value))) {
    return(NULL)
  }

  value <- trimws(as.character(value[[1]]))
  if (!nzchar(value)) {
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
  if (is.null(value) || length(value) == 0L || all(is.na(value))) {
    return(NULL)
  }

  value <- trimws(as.character(value))
  if (!length(value) || !any(nzchar(value))) {
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
    minimum = 2008L,
    maximum = 2100L,
    max_items = 20L
  )
  if (!is.null(parsed_seasons)) {
    return(parsed_seasons)
  }

  parsed_season <- parse_optional_int(season, "season", minimum = 2008L, maximum = 2100L)
  if (is.null(parsed_season)) {
    return(NULL)
  }

  c(parsed_season)
}

parse_nwar_era <- function(value = "", name = "era") {
  if (is.null(value) || !nzchar(trimws(value))) {
    return(NULL)
  }

  parsed <- tolower(trimws(value))
  if (!parsed %in% c("anzc", "ssn")) {
    stop(name, " must be one of anzc or ssn.", call. = FALSE)
  }

  parsed
}

parse_nwar_position_group <- function(value = "", name = "position_group") {
  if (is.null(value) || !nzchar(trimws(value))) {
    return(NULL)
  }

  parsed <- tolower(trimws(value))
  choices <- c(
    shooter = "Shooter",
    midcourt = "Midcourt",
    defender = "Defender"
  )
  if (!parsed %in% names(choices)) {
    stop(name, " must be one of shooter, midcourt, or defender.", call. = FALSE)
  }

  unname(choices[[parsed]])
}

seasons_from_nwar_era <- function(era) {
  if (is.null(era)) {
    return(NULL)
  }
  if (identical(era, "anzc")) {
    return(2008L:2016L)
  }
  if (identical(era, "ssn")) {
    return(2017L:2100L)
  }

  stop("Unsupported nWAR era.", call. = FALSE)
}

parse_limit <- function(value, default = 20L, maximum = 100L) {
  if (is.null(value) || !nzchar(value)) {
    return(default)
  }

  parsed <- parse_optional_int(value, "limit", minimum = 1L, maximum = maximum)
  parsed %||% default
}

parse_metric <- function(value = "", name = "metric") {
  if (is.null(value) || !nzchar(trimws(value))) {
    return("total")
  }

  parsed <- tolower(trimws(value))
  if (!parsed %in% c("total", "average")) {
    stop(name, " must be either total or average.", call. = FALSE)
  }

  parsed
}

parse_ranking_mode <- function(value = "", name = "ranking") {
  if (is.null(value) || !nzchar(trimws(value))) {
    return("highest")
  }

  parsed <- tolower(trimws(value))
  if (parsed %in% c("highest", "desc", "descending", "top")) {
    return("highest")
  }
  if (parsed %in% c("lowest", "asc", "ascending", "bottom")) {
    return("lowest")
  }

  stop(name, " must be either highest or lowest.", call. = FALSE)
}

ranking_order_sql <- function(ranking_mode = "highest") {
  if (identical(ranking_mode, "lowest")) "ASC" else "DESC"
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

parse_optional_text <- function(value, name, max_length = 120L) {
  if (is.null(value) || length(value) == 0L || all(is.na(value))) {
    return(NULL)
  }

  trimmed <- trimws(as.character(value[[1]]))
  if (!nzchar(trimmed)) {
    return(NULL)
  }
  if (nchar(trimmed) > max_length) {
    stop(name, " must be ", max_length, " characters or fewer.", call. = FALSE)
  }
  if (grepl("[[:cntrl:]]", trimmed)) {
    stop(name, " contains unsupported characters.", call. = FALSE)
  }

  trimmed
}

normalize_stat_catalog <- function(values) {
  normalized <- as.character(values %||% character())
  normalized <- normalized[!is.na(normalized)]
  normalized <- trimws(normalized)
  sort(unique(normalized[nzchar(normalized)]))
}

stat_catalog_metadata_entries <- function(team_stats, player_stats) {
  data.frame(
    key = c("team_stats_json", "player_stats_json"),
    value = c(
      jsonlite::toJSON(normalize_stat_catalog(team_stats), auto_unbox = TRUE),
      jsonlite::toJSON(normalize_stat_catalog(player_stats), auto_unbox = TRUE)
    ),
    stringsAsFactors = FALSE
  )
}

metadata_stat_catalog <- function(metadata_map, key, fallback) {
  raw_value <- if (key %in% names(metadata_map)) metadata_map[[key]] else ""
  if (!nzchar(raw_value)) {
    return(normalize_stat_catalog(fallback))
  }

  parsed <- tryCatch(
    jsonlite::fromJSON(raw_value, simplifyVector = TRUE),
    error = function(error) NULL
  )
  normalized <- normalize_stat_catalog(parsed)
  if (length(normalized)) {
    return(normalized)
  }

  normalize_stat_catalog(fallback)
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

normalize_record_value <- function(value) {
  if (is.null(value) || length(value) == 0L || (length(value) == 1L && is.na(value))) {
    return(NULL)
  }

  if (inherits(value, "POSIXt")) {
    return(format(value, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  }

  if (inherits(value, "Date")) {
    return(format(value, "%Y-%m-%d"))
  }

  if (is.factor(value)) {
    return(as.character(value))
  }

  unname(value)
}

row_to_record <- function(rows, index) {
  setNames(
    lapply(rows, function(column) normalize_record_value(column[[index]])),
    names(rows)
  )
}

# NOTE: rows_to_records is defined in plumber.R (with jsonlite::unbox support)
# and overrides this file at runtime. Do not add a second definition here.

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

opponent_name_sql <- function(subject_squad_column, aggregate = FALSE) {
  expr <- paste0(
    "CASE WHEN matches.home_squad_id = ", subject_squad_column,
    " THEN matches.away_squad_name ELSE matches.home_squad_name END"
  )

  if (isTRUE(aggregate)) {
    return(paste0("MAX(", expr, ")"))
  }

  expr
}

opponent_id_sql <- function(subject_squad_column) {
  paste0(
    "CASE WHEN matches.home_squad_id = ", subject_squad_column,
    " THEN matches.away_squad_id ELSE matches.home_squad_id END"
  )
}

validate_sql_identifier <- function(value, name = "identifier") {
  if (!grepl("^[A-Za-z][A-Za-z0-9_]*$", value)) {
    stop(name, " must start with a letter and contain only letters, digits, and underscores.", call. = FALSE)
  }
}

available_stats <- function(conn, table_name) {
  validate_sql_identifier(table_name, "table_name")
  cache_key <- paste0("netballstats.stat_catalog.", table_name)
  cached <- getOption(cache_key)
  if (!is.null(cached)) return(cached)

  result <- query_rows(
    conn,
    sprintf(
      "SELECT DISTINCT stat FROM %s WHERE value_number IS NOT NULL ORDER BY stat",
      table_name
    )
  )$stat
  options(setNames(list(result), cache_key))
  result
}

validate_stat <- function(conn, table_name, stat, default_stat = "points") {
  chosen <- stat %||% default_stat
  # Fast path: validate against compile-time constants to avoid a DB round-trip
  # for all common stats (covers >95% of requests without touching the DB).
  known <- if (grepl("player", table_name, fixed = TRUE)) DEFAULT_PLAYER_STATS else DEFAULT_TEAM_STATS
  if (chosen %in% known) return(chosen)

  # Slow path: full DB lookup for any stat not in the compile-time list.
  stats <- available_stats(conn, table_name)
  if (!length(stats)) {
    stop("No numeric stats are available in ", table_name, ".", call. = FALSE)
  }
  if (!chosen %in% stats) {
    stop("Unsupported stat: ", chosen, ".", call. = FALSE)
  }
  chosen
}

apply_metric_value <- function(rows, metric) {
  rows$metric <- metric
  if (!nrow(rows)) {
    rows$value <- numeric(0)
    return(rows)
  }

  rows$value <- if (identical(metric, "average")) rows$average_value else rows$total_value
  rows
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

query_examples <- function() {
  QUERY_SUPPORTED_EXAMPLES
}

query_error_payload <- function(status, question, reason, candidates = NULL) {
  payload <- list(
    status = jsonlite::unbox(status),
    question = jsonlite::unbox(question),
    reason = jsonlite::unbox(reason),
    examples = query_examples()
  )

  if (!is.null(candidates) && length(candidates)) {
    payload$candidates <- candidates
  }

  payload
}

pretty_stat_label <- function(stat) {
  if (is.null(stat) || !nzchar(stat)) {
    return("")
  }

  label <- QUERY_STAT_DEFINITIONS[[stat]]$label %||% ""
  if (nzchar(label)) {
    return(label)
  }

  label <- gsub("([a-z0-9])([A-Z])", "\\1 \\2", stat, perl = TRUE)
  label <- gsub("_", " ", label, fixed = TRUE)
  tools::toTitleCase(label)
}

query_stat_label <- function(stat) {
  pretty_stat_label(stat)
}

query_comparison_label <- function(comparison) {
  QUERY_COMPARISON_DEFINITIONS[[comparison]]$label %||% comparison
}

query_comparison_sql <- function(comparison) {
  QUERY_COMPARISON_DEFINITIONS[[comparison]]$sql %||% "="
}

escape_regex <- function(value) {
  gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", value)
}

normalize_query_phrase <- function(value, keep_spaces = TRUE) {
  if (is.null(value)) {
    return("")
  }

  normalized <- iconv(as.character(value), to = "ASCII//TRANSLIT")
  normalized[is.na(normalized)] <- as.character(value)[is.na(normalized)]
  normalized <- tolower(normalized)
  normalized <- gsub("&", " and ", normalized, fixed = TRUE)
  normalized <- gsub("[^a-z0-9+ ]+", " ", normalized)
  normalized <- gsub("\\s+", " ", trimws(normalized))

  if (!keep_spaces) {
    normalized <- gsub(" ", "", normalized, fixed = TRUE)
  }

  normalized
}

parse_query_question <- function(value, max_length = 220L) {
  if (is.null(value) || !nzchar(trimws(value))) {
    stop("question is required.", call. = FALSE)
  }

  trimmed <- trimws(value)
  if (nchar(trimmed) > max_length) {
    stop("question must be 220 characters or fewer.", call. = FALSE)
  }
  if (!grepl("[A-Za-z0-9]", trimmed)) {
    stop("question must include at least one letter or digit.", call. = FALSE)
  }

  trimmed
}

extract_first_capture <- function(value, pattern) {
  matched <- regexec(pattern, value, perl = TRUE)
  groups <- regmatches(value, matched)[[1]]
  if (length(groups) < 2L) {
    return(NULL)
  }

  capture <- trimws(groups[[2]])
  if (!nzchar(capture)) {
    return(NULL)
  }

  capture
}

detect_query_intent_type <- function(text) {
  if (grepl("^(how many times|how many matches)\\b", text)) {
    return("count")
  }
  if (grepl("\\bhighest\\b", text)) {
    return("highest")
  }
  if (grepl("\\blowest\\b", text)) {
    return("lowest")
  }
  if (grepl("^(which players|which teams|list players|list teams|show players|show teams|who)\\b", text)) {
    return("list")
  }
  if (grepl("^(show|list)\\b", text)) {
    return("list")
  }

  NULL
}

parse_query_threshold <- function(text) {
  patterns <- list(
    list(pattern = "\\b(\\d+(?:\\.\\d+)?)\\s*\\+", comparison = "gte"),
    list(pattern = "\\b(\\d+(?:\\.\\d+)?)\\s+[a-z]+(?:\\s+[a-z]+){0,4}\\s+or more\\b", comparison = "gte"),
    list(pattern = "\\b(\\d+(?:\\.\\d+)?)\\s+or more\\b", comparison = "gte"),
    list(pattern = "\\bat least\\s+(\\d+(?:\\.\\d+)?)\\b", comparison = "gte"),
    list(pattern = "\\bat most\\s+(\\d+(?:\\.\\d+)?)\\b", comparison = "lte"),
    list(pattern = "\\bmore than\\s+(\\d+(?:\\.\\d+)?)\\b", comparison = "gt"),
    list(pattern = "\\bfewer than\\s+(\\d+(?:\\.\\d+)?)\\b", comparison = "lt"),
    list(pattern = "\\bless than\\s+(\\d+(?:\\.\\d+)?)\\b", comparison = "lt"),
    list(pattern = "\\bexactly\\s+(\\d+(?:\\.\\d+)?)\\b", comparison = "eq")
  )

  for (entry in patterns) {
    raw_value <- extract_first_capture(text, entry$pattern)
    if (!is.null(raw_value)) {
      return(list(
        comparison = entry$comparison,
        threshold = as.numeric(raw_value)
      ))
    }
  }

  NULL
}

extract_query_seasons <- function(text) {
  matched <- gregexpr("\\b20[0-9]{2}\\b", text, perl = TRUE)
  seasons <- regmatches(text, matched)[[1]]
  if (!length(seasons)) {
    return(NULL)
  }

  unique(as.integer(seasons))
}

build_query_stat_alias_rows <- function() {
  rows <- lapply(names(QUERY_STAT_DEFINITIONS), function(stat_name) {
    aliases <- QUERY_STAT_DEFINITIONS[[stat_name]]$aliases %||% character()
    data.frame(
      stat = stat_name,
      alias = aliases,
      alias_length = nchar(aliases),
      stringsAsFactors = FALSE
    )
  })
  alias_rows <- do.call(rbind, rows)
  alias_rows <- alias_rows[order(alias_rows$alias_length, decreasing = TRUE), , drop = FALSE]
  rownames(alias_rows) <- NULL
  # Pre-compile regex patterns once at load time so resolve_query_stat() is
  # pure vectorised matching with no per-call regex construction.
  alias_rows$pattern <- paste0(
    "\\b",
    gsub(" ", "\\\\s+", sapply(alias_rows$alias, escape_regex, USE.NAMES = FALSE), fixed = TRUE),
    "\\b"
  )
  alias_rows
}

QUERY_STAT_ALIASES <- build_query_stat_alias_rows()

resolve_query_stat_fallback <- function(text) {
  fallback_patterns <- list(
    goalAssists = c("\\bgoal\\s+assists?\\b", "\\bassists?\\b"),
    goalAttempts = c("\\bgoal\\s+attempts?\\b", "\\bshot\\s+attempts?\\b", "\\bshots\\b", "\\battempts\\b"),
    goal1 = c("\\b(?:1|one)\\s+point\\s+goals?\\b"),
    goal2 = c("\\b(?:2|two)\\s+point\\s+goals?\\b"),
    goals = c("\\bgoal\\s+totals?\\b", "\\bgoals\\b")
  )

  for (stat_name in names(fallback_patterns)) {
    patterns <- fallback_patterns[[stat_name]]
    if (any(vapply(patterns, function(pattern) grepl(pattern, text, perl = TRUE), logical(1)))) {
      return(stat_name)
    }
  }

  NULL
}

resolve_query_stat <- function(text) {
  matched <- vapply(
    QUERY_STAT_ALIASES$pattern,
    function(pattern) grepl(pattern, text, perl = TRUE),
    logical(1)
  )
  candidates <- QUERY_STAT_ALIASES[matched, , drop = FALSE]
  if (!nrow(candidates)) {
    return(resolve_query_stat_fallback(text))
  }
  unique(as.character(candidates$stat))[[1]]
}

.team_alias_cache <- NULL

team_alias_lookup <- function(conn) {
  if (!is.null(.team_alias_cache)) return(.team_alias_cache)

  teams <- query_rows(
    conn,
    "SELECT squad_id, squad_name, squad_code FROM teams ORDER BY squad_name"
  )
  if (!nrow(teams)) {
    return(data.frame())
  }

  rows <- lapply(seq_len(nrow(teams)), function(index) {
    team <- teams[index, , drop = FALSE]
    tokens <- unlist(strsplit(as.character(team$squad_name), "[^A-Za-z0-9]+"))
    tokens <- tokens[nzchar(tokens)]
    first_token <- if (length(tokens)) tokens[[1]] else ""
    last_token <- if (length(tokens)) tokens[[length(tokens)]] else ""
    aliases <- unique(c(
      as.character(team$squad_name),
      as.character(team$squad_code),
      first_token,
      last_token
    ))
    aliases <- aliases[nzchar(aliases)]
    aliases <- aliases[nchar(normalize_player_search_name(aliases)) >= 3L]

    data.frame(
      squad_id = rep(team$squad_id[[1]], length(aliases)),
      squad_name = rep(as.character(team$squad_name[[1]]), length(aliases)),
      alias_name = aliases,
      alias_search_name = normalize_player_search_name(aliases),
      stringsAsFactors = FALSE
    )
  })

  alias_rows <- unique(do.call(rbind, rows))
  rownames(alias_rows) <- NULL
  .team_alias_cache <<- alias_rows
  alias_rows
}

resolve_query_team <- function(conn, phrase) {
  if (is.null(phrase) || !nzchar(trimws(phrase))) {
    return(NULL)
  }

  lookup <- team_alias_lookup(conn)
  if (!nrow(lookup)) {
    return(query_error_payload("unsupported", phrase, "No team lookup data is available."))
  }

  normalized <- normalize_player_search_name(gsub("^the\\s+", "", trimws(phrase), ignore.case = TRUE))
  if (!nzchar(normalized)) {
    return(NULL)
  }

  exact <- lookup[lookup$alias_search_name == normalized, , drop = FALSE]
  candidates <- if (nrow(exact)) {
    exact
  } else {
    matched <- lookup[
      vapply(
        lookup$alias_search_name,
        function(alias_search_name) {
          grepl(normalized, alias_search_name, fixed = TRUE) ||
            grepl(alias_search_name, normalized, fixed = TRUE)
        },
        logical(1)
      ),
      ,
      drop = FALSE
    ]
    matched
  }

  if (!nrow(candidates)) {
    return(query_error_payload(
      "unsupported",
      phrase,
      "I couldn't match the opponent name to a Super Netball team."
    ))
  }

  alias_lengths <- nchar(candidates$alias_search_name)
  longest <- max(alias_lengths)
  candidates <- candidates[alias_lengths == longest, , drop = FALSE]
  squad_ids <- unique(candidates$squad_id)
  if (length(squad_ids) > 1L) {
    return(query_error_payload(
      "ambiguous",
      phrase,
      "That opponent name matches multiple teams.",
      candidates = unique(as.character(candidates$squad_name))
    ))
  }

  list(
    status = "supported",
    squad_id = as.integer(squad_ids[[1]]),
    squad_name = as.character(candidates$squad_name[[1]])
  )
}

resolve_query_player <- function(conn, question) {
  normalized_phrase <- normalize_player_search_name(question)
  if (!nzchar(normalized_phrase)) {
    return(NULL)
  }

  direct_lookup <- query_rows(
    conn,
    paste(
      "SELECT player_id, alias_name, alias_search_name, canonical_name FROM (",
      "  SELECT p.player_id, p.canonical_name AS alias_name, p.search_name AS alias_search_name,",
      "    p.canonical_name FROM players p WHERE p.search_name LIKE ?search",
      "  UNION ALL",
      "  SELECT pa.player_id, pa.alias_name, pa.alias_search_name, p.canonical_name",
      "  FROM player_aliases pa",
      "  JOIN players p ON p.player_id = pa.player_id",
      "  WHERE pa.alias_search_name LIKE ?search",
      ") combined",
      "ORDER BY canonical_name ASC"
    ),
    list(search = paste0("%", normalized_phrase, "%"))
  )
  if (!nrow(direct_lookup)) {
    return(query_error_payload("unsupported", question, "No player lookup data is available."))
  }

  direct_lookup$canonical_name <- as.character(direct_lookup$canonical_name)
  direct_lookup$alias_search_name <- as.character(direct_lookup$alias_search_name)
  direct_lookup$match_score <- ifelse(
    direct_lookup$alias_search_name == normalized_phrase,
    3L,
    ifelse(
      normalize_player_search_name(direct_lookup$canonical_name) == normalized_phrase,
      3L,
      ifelse(
        grepl(normalized_phrase, direct_lookup$alias_search_name, fixed = TRUE) |
          grepl(normalized_phrase, normalize_player_search_name(direct_lookup$canonical_name), fixed = TRUE),
        2L,
        1L
      )
    )
  )

  best_score <- max(direct_lookup$match_score, na.rm = TRUE)
  matched <- direct_lookup[direct_lookup$match_score == best_score, , drop = FALSE]
  player_ids <- unique(matched$player_id[!is.na(matched$player_id)])
  matched <- matched[!is.na(matched$player_id), , drop = FALSE]
  if (!length(player_ids)) {
    return(query_error_payload(
      "unsupported",
      question,
      "I couldn't match a player name in that question."
    ))
  }
  if (length(player_ids) > 1L) {
    return(query_error_payload(
      "ambiguous",
      question,
      "That player reference matches multiple people.",
      candidates = unique(as.character(matched$canonical_name))
    ))
  }

  list(
    status = "supported",
    player_id = as.integer(player_ids[[1]]),
    player_name = as.character(matched$canonical_name[[1]])
  )
}

extract_query_player_phrase <- function(question, intent_type) {
  patterns <- switch(
    intent_type,
    count = c(
      "(?i)^how many (?:times|matches) (?:has|have)\\s+(.+?)\\s+(?:scored|recorded|made|had|posted|notched|registered)\\b",
      "(?i)^how many (?:times|matches) did\\s+(.+?)\\s+(?:score|record|make|have|post|notch|register)\\b"
    ),
    highest = c(
      "(?i)^what is\\s+(.+?)\\s+highest\\b"
    ),
    lowest = c(
      "(?i)^what is\\s+(.+?)\\s+lowest\\b"
    ),
    character()
  )

  for (pattern in patterns) {
    captured <- extract_first_capture(question, pattern)
    if (!is.null(captured)) {
      normalized <- trimws(captured)
      normalized <- sub("(?:'s|’s)$", "", normalized, perl = TRUE)
      normalized <- sub("([sS])['’]$", "\\1", normalized, perl = TRUE)
      if (nzchar(normalized)) {
        return(normalized)
      }
    }
  }

  NULL
}

extract_query_subject_phrase <- function(question, intent_type) {
  extract_query_player_phrase(question, intent_type)
}

detect_query_list_subject_type <- function(text) {
  if (grepl("^(which players|list players|show players|who)\\b", text)) {
    return("players")
  }
  if (grepl("^(which teams|list teams|show teams)\\b", text)) {
    return("teams")
  }

  NULL
}

resolve_query_subject <- function(conn, phrase) {
  team <- resolve_query_team(conn, phrase)
  if (is.list(team) && !is.null(team$status) && identical(team$status, "supported")) {
    return(list(
      status = "supported",
      subject_type = "team",
      team_id = team$squad_id,
      team_name = team$squad_name
    ))
  }

  player <- resolve_query_player(conn, phrase)
  if (is.list(player) && !is.null(player$status) && identical(player$status, "supported")) {
    return(list(
      status = "supported",
      subject_type = "player",
      player_id = player$player_id,
      player_name = player$player_name
    ))
  }

  if (is.list(team) && !is.null(team$status) && identical(team$status, "ambiguous")) {
    return(team)
  }
  if (is.list(player) && !is.null(player$status) && identical(player$status, "ambiguous")) {
    return(player)
  }

  query_error_payload(
    "unsupported",
    phrase,
    "I couldn't match a player or team in that question."
  )
}

parse_query_intent <- function(conn, question, limit = 12L) {
  parsed_question <- parse_query_question(question)
  normalized_text <- normalize_query_phrase(parsed_question, keep_spaces = TRUE)
  intent_type <- detect_query_intent_type(normalized_text)
  if (is.null(intent_type)) {
    return(query_error_payload(
      "unsupported",
      parsed_question,
      "Try a count, highest/lowest, or list-style stats question."
    ))
  }

  stat <- resolve_query_stat(normalized_text)
  if (is.null(stat)) {
    return(query_error_payload(
      "unsupported",
      parsed_question,
      "I couldn't identify which stat you want to query."
    ))
  }

  threshold <- parse_query_threshold(normalized_text)
  seasons <- extract_query_seasons(normalized_text)
  season <- if (!is.null(seasons) && length(seasons) == 1L) seasons[[1]] else NULL
  opponent_phrase <- extract_first_capture(
    normalized_text,
    "\\bagainst\\s+(.+?)(?:\\s+(?:in|during)\\s+20[0-9]{2}\\b|$)"
  )
  opponent <- resolve_query_team(conn, opponent_phrase)
  if (is.list(opponent) && !is.null(opponent$status) && !identical(opponent$status, "supported")) {
    opponent$question <- parsed_question
    return(opponent)
  }

  plural_subject_type <- if (identical(intent_type, "list")) {
    detect_query_list_subject_type(normalized_text)
  } else {
    NULL
  }

  subject_search_phrase <- if (!is.null(plural_subject_type)) {
    NULL
  } else {
    extract_query_subject_phrase(parsed_question, intent_type) %||% parsed_question
  }
  subject <- if (!is.null(plural_subject_type)) {
    list(status = "supported", subject_type = plural_subject_type)
  } else {
    resolve_query_subject(conn, subject_search_phrase)
  }
  if (is.list(subject) && !is.null(subject$status) && !identical(subject$status, "supported")) {
    subject$question <- parsed_question
    return(subject)
  }

  subject_type <- subject$subject_type %||% NULL
  if (is.null(subject_type)) {
    return(query_error_payload(
      "unsupported",
      parsed_question,
      "I couldn't identify whether the question is about a player or a team."
    ))
  }
  if (
    identical(subject_type, "player") &&
    (
      is.null(subject$player_id) ||
      is.null(subject$player_name) ||
      !nzchar(as.character(subject$player_name))
    )
  ) {
    return(query_error_payload(
      "unsupported",
      parsed_question,
      "I couldn't confidently match a single player in that question."
    ))
  }
  if (
    identical(subject_type, "team") &&
    (
      is.null(subject$team_id) ||
      is.null(subject$team_name) ||
      !nzchar(as.character(subject$team_name))
    )
  ) {
    return(query_error_payload(
      "unsupported",
      parsed_question,
      "I couldn't confidently match a single team in that question."
    ))
  }

  if (identical(intent_type, "count") && is.null(threshold)) {
    return(query_error_payload(
      "unsupported",
      parsed_question,
      "Count questions need a threshold such as 50+, at least 40, or exactly 20."
    ))
  }
  if (identical(intent_type, "list") && identical(subject_type, "players") &&
      is.null(threshold) && is.null(opponent) && is.null(seasons)) {
    return(query_error_payload(
      "unsupported",
      parsed_question,
      "Broader list questions need at least one narrowing filter such as a threshold, opponent, or season."
    ))
  }
  if (identical(intent_type, "list") && identical(subject_type, "teams") &&
      is.null(threshold) && is.null(opponent) && is.null(seasons)) {
    return(query_error_payload(
      "unsupported",
      parsed_question,
      "Broader list questions need at least one narrowing filter such as a threshold, opponent, or season."
    ))
  }

  list(
    status = "supported",
    question = parsed_question,
    intent_type = intent_type,
    subject_type = subject_type,
    player_id = subject$player_id %||% NULL,
    player_name = subject$player_name %||% NULL,
    team_id = subject$team_id %||% NULL,
    team_name = subject$team_name %||% NULL,
    stat = stat,
    stat_label = query_stat_label(stat),
    comparison = threshold$comparison %||% NULL,
    comparison_label = if (!is.null(threshold$comparison)) query_comparison_label(threshold$comparison) else NULL,
    threshold = threshold$threshold %||% NULL,
    opponent_id = opponent$squad_id %||% NULL,
    opponent_name = opponent$squad_name %||% NULL,
    seasons = seasons,
    season = season,
    limit = limit
  )
}

build_player_match_query <- function(stat, seasons = NULL, player_id = NULL, opponent_id = NULL, comparison = NULL, threshold = NULL) {
  query <- paste(
    "SELECT stats.player_id, players.canonical_name AS player_name, stats.squad_name,",
    paste0(opponent_name_sql("stats.squad_id", aggregate = TRUE), " AS opponent,"),
    "stats.season AS season, stats.round_number AS round_number, stats.match_id AS match_id, matches.local_start_time AS local_start_time,",
    "?stat AS stat, ROUND(CAST(SUM(stats.value_number) AS numeric), 2) AS total_value",
    "FROM player_period_stats AS stats",
    "INNER JOIN players ON players.player_id = stats.player_id",
    "INNER JOIN matches ON matches.match_id = stats.match_id",
    "WHERE stats.stat = ?stat"
  )
  params <- list(stat = stat)

  filters <- apply_stat_filters(query, params, seasons = seasons, team_id = NULL, round_number = NULL, table_alias = "stats")
  query <- filters$query
  params <- filters$params

  if (!is.null(player_id)) {
    query <- paste0(query, " AND stats.player_id = ?player_id")
    params$player_id <- player_id
  }
  if (!is.null(opponent_id)) {
    query <- paste0(
      query,
      " AND (", opponent_id_sql("stats.squad_id"), ") = ?opponent_id"
    )
    params$opponent_id <- opponent_id
  }

  query <- paste0(
    query,
    " GROUP BY stats.player_id, players.canonical_name, stats.squad_name, stats.season, stats.round_number, stats.match_id, matches.local_start_time"
  )

  if (!is.null(comparison) && !is.null(threshold)) {
    query <- paste0(query, " HAVING SUM(stats.value_number) ", query_comparison_sql(comparison), " ?threshold")
    params$threshold <- threshold
  }

  list(query = query, params = params)
}

# Returns TRUE when player_match_stats is available in the connected database.
# The table is created by build_database.R; older DB builds won't have it.
has_player_match_stats <- function(conn) {
  cached <- getOption("netballstats.pms_available")
  if (!is.null(cached)) return(isTRUE(cached))
  result <- isTRUE(tryCatch(
    DBI::dbExistsTable(conn, "player_match_stats"),
    error = function(e) FALSE
  ))
  options(netballstats.pms_available = result)
  result
}

has_player_match_positions <- function(conn) {
  cached <- getOption("netballstats.pmp_available")
  if (!is.null(cached)) return(isTRUE(cached))
  result <- isTRUE(tryCatch(
    DBI::dbExistsTable(conn, "player_match_positions"),
    error = function(e) FALSE
  ))
  options(netballstats.pmp_available = result)
  result
}

has_player_match_participation <- function(conn) {
  cached <- getOption("netballstats.pmpart_available")
  if (!is.null(cached)) return(isTRUE(cached))
  result <- isTRUE(tryCatch(
    DBI::dbExistsTable(conn, "player_match_participation"),
    error = function(e) FALSE
  ))
  options(netballstats.pmpart_available = result)
  result
}

# Returns TRUE when team_match_stats is available in the connected database.
# The table is created by build_database.R; older DB builds won't have it.
has_team_match_stats <- function(conn) {
  cached <- getOption("netballstats.tms_available")
  if (!is.null(cached)) return(isTRUE(cached))
  result <- isTRUE(tryCatch(
    DBI::dbExistsTable(conn, "team_match_stats"),
    error = function(e) FALSE
  ))
  options(netballstats.tms_available = result)
  result
}

has_home_venue_impact_rows <- function(conn) {
  cached <- getOption("netballstats.hvir_available")
  if (!is.null(cached)) return(isTRUE(cached))
  result <- isTRUE(tryCatch(
    DBI::dbExistsTable(conn, "home_venue_impact_rows"),
    error = function(e) FALSE
  ))
  options(netballstats.hvir_available = result)
  result
}

has_home_venue_breakdown_rows <- function(conn) {
  cached <- getOption("netballstats.hvbr_available")
  if (!is.null(cached)) return(isTRUE(cached))
  result <- isTRUE(tryCatch(
    DBI::dbExistsTable(conn, "home_venue_breakdown_rows"),
    error = function(e) FALSE
  ))
  options(netballstats.hvbr_available = result)
  result
}

# Maps a Champion Data startingPositionCode to a broad positional group.
# GS/GA are Shooters; WA/C/WD are Midcourt; GD/GK are Defenders.
# Interchange and unrecognised codes fall through to "Other".
position_group_from_code <- function(code) {
  ifelse(code %in% c("GS", "GA"), "Shooter",
    ifelse(code %in% c("WA", "C", "WD"), "Midcourt",
      ifelse(code %in% c("GD", "GK"), "Defender", "Other")))
}

# Faster alternative to build_player_match_query that reads from the
# player_match_stats pre-aggregated table (one row per player per match per
# stat) instead of player_period_stats (one row per player per period per
# stat).  No GROUP BY required; threshold comparisons become WHERE clauses
# instead of HAVING, so the stat+value index can be used directly.
build_fast_player_match_query <- function(stat, seasons = NULL, player_id = NULL, opponent_id = NULL, comparison = NULL, threshold = NULL) {
  query <- paste(
    "SELECT pms.player_id, players.canonical_name AS player_name, pms.squad_name,",
    paste0(opponent_name_sql("pms.squad_id"), " AS opponent,"),
    "pms.season AS season, pms.round_number AS round_number, pms.match_id AS match_id, matches.local_start_time AS local_start_time,",
    "?stat AS stat, pms.match_value AS total_value",
    "FROM player_match_stats AS pms",
    "INNER JOIN players ON players.player_id = pms.player_id",
    "INNER JOIN matches ON matches.match_id = pms.match_id",
    "WHERE pms.stat = ?stat"
  )
  params <- list(stat = stat)

  filters <- apply_stat_filters(query, params, seasons = seasons, team_id = NULL, round_number = NULL, table_alias = "pms")
  query <- filters$query
  params <- filters$params

  if (!is.null(player_id)) {
    query <- paste0(query, " AND pms.player_id = ?player_id")
    params$player_id <- player_id
  }
  if (!is.null(opponent_id)) {
    query <- paste0(
      query,
      " AND (", opponent_id_sql("pms.squad_id"), ") = ?opponent_id"
    )
    params$opponent_id <- opponent_id
  }
  if (!is.null(comparison) && !is.null(threshold)) {
    query <- paste0(query, " AND pms.match_value ", query_comparison_sql(comparison), " ?threshold")
    params$threshold <- threshold
  }

  list(query = query, params = params)
}

build_team_match_query <- function(stat, seasons = NULL, team_id = NULL, opponent_id = NULL, comparison = NULL, threshold = NULL) {
  query <- paste(
    "SELECT stats.squad_id AS team_id, stats.squad_name,",
    paste0(opponent_name_sql("stats.squad_id", aggregate = TRUE), " AS opponent,"),
    "stats.season AS season, stats.round_number AS round_number, stats.match_id AS match_id, matches.local_start_time AS local_start_time,",
    "?stat AS stat, ROUND(CAST(SUM(stats.value_number) AS numeric), 2) AS total_value",
    "FROM team_period_stats AS stats",
    "INNER JOIN matches ON matches.match_id = stats.match_id",
    "WHERE stats.stat = ?stat"
  )
  params <- list(stat = stat)

  filters <- apply_stat_filters(query, params, seasons = seasons, team_id = team_id, round_number = NULL, table_alias = "stats")
  query <- filters$query
  params <- filters$params

  if (!is.null(opponent_id)) {
    query <- paste0(
      query,
      " AND (", opponent_id_sql("stats.squad_id"), ") = ?opponent_id"
    )
    params$opponent_id <- opponent_id
  }

  query <- paste0(
    query,
    " GROUP BY stats.squad_id, stats.squad_name, stats.season, stats.round_number, stats.match_id, matches.local_start_time"
  )

  if (!is.null(comparison) && !is.null(threshold)) {
    query <- paste0(query, " HAVING SUM(stats.value_number) ", query_comparison_sql(comparison), " ?threshold")
    params$threshold <- threshold
  }

  list(query = query, params = params)
}

# Faster alternative to build_team_match_query that reads from the
# team_match_stats pre-aggregated table (one row per team per match per
# stat) instead of team_period_stats (one row per team per period per
# stat).  No GROUP BY required; threshold comparisons become WHERE clauses
# instead of HAVING, so the stat+value index can be used directly.
build_fast_team_match_query <- function(stat, seasons = NULL, team_id = NULL, opponent_id = NULL, comparison = NULL, threshold = NULL) {
  query <- paste(
    "SELECT tms.squad_id AS team_id, tms.squad_name,",
    paste0(opponent_name_sql("tms.squad_id"), " AS opponent,"),
    "tms.season AS season, tms.round_number AS round_number, tms.match_id AS match_id, matches.local_start_time AS local_start_time,",
    "?stat AS stat, tms.match_value AS total_value",
    "FROM team_match_stats AS tms",
    "INNER JOIN matches ON matches.match_id = tms.match_id",
    "WHERE tms.stat = ?stat"
  )
  params <- list(stat = stat)

  filters <- apply_stat_filters(query, params, seasons = seasons, team_id = team_id, round_number = NULL, table_alias = "tms")
  query <- filters$query
  params <- filters$params

  if (!is.null(opponent_id)) {
    query <- paste0(
      query,
      " AND (", opponent_id_sql("tms.squad_id"), ") = ?opponent_id"
    )
    params$opponent_id <- opponent_id
  }
  if (!is.null(comparison) && !is.null(threshold)) {
    query <- paste0(query, " AND tms.match_value ", query_comparison_sql(comparison), " ?threshold")
    params$threshold <- threshold
  }

  list(query = query, params = params)
}

format_query_number <- function(value) {
  if (is.null(value) || !is.finite(as.numeric(value))) {
    return(as.character(value))
  }

  numeric <- as.numeric(value)
  format(
    round(numeric, if (numeric %% 1 == 0) 0 else 2),
    trim = TRUE,
    scientific = FALSE
  )
}

format_query_season_label <- function(seasons) {
  seasons <- as.integer(seasons %||% integer())
  seasons <- seasons[!is.na(seasons)]
  if (!length(seasons)) {
    return(NULL)
  }

  seasons <- sort(unique(seasons))
  season_labels <- as.character(seasons)
  if (length(season_labels) == 1L) {
    return(season_labels[[1]])
  }
  if (length(season_labels) == 2L) {
    return(paste(season_labels, collapse = " or "))
  }

  paste0(
    paste(season_labels[seq_len(length(season_labels) - 1L)], collapse = ", "),
    ", or ",
    season_labels[[length(season_labels)]]
  )
}

query_filter_suffix <- function(intent) {
  suffix <- character()
  if (!is.null(intent$opponent_name)) {
    suffix <- c(suffix, paste("against", intent$opponent_name))
  }
  season_label <- format_query_season_label(intent$seasons %||% intent$season)
  if (!is.null(season_label)) {
    suffix <- c(suffix, paste("in", season_label))
  }

  if (!length(suffix)) {
    return("")
  }

  paste0(" ", paste(suffix, collapse = " "))
}

query_possessive_label <- function(value) {
  if (is.null(value) || !nzchar(value)) {
    return("")
  }

  trimmed <- trimws(as.character(value))
  if (!nzchar(trimmed)) {
    return("")
  }

  paste0(trimmed, if (grepl("s$", trimmed, ignore.case = TRUE)) "'" else "'s")
}

build_query_answer <- function(intent, rows, total_matches) {
  stat_label <- tolower(query_stat_label(intent$stat))
  subject <- intent$player_name %||% intent$team_name %||%
    if (identical(intent$subject_type, "teams")) "Teams" else "Players"
  possessive_subject <- query_possessive_label(subject)
  filter_suffix <- query_filter_suffix(intent)
  threshold_phrase <- if (!is.null(intent$comparison) && !is.null(intent$threshold)) {
    paste(query_comparison_label(intent$comparison), format_query_number(intent$threshold), stat_label)
  } else {
    stat_label
  }

  if (identical(intent$intent_type, "count")) {
    times_label <- if (identical(total_matches, 1L)) "time" else "times"
    return(sprintf(
      "%s recorded %s%s %s.",
      subject,
      threshold_phrase,
      filter_suffix,
      paste(total_matches, times_label)
    ))
  }

  if (!nrow(rows)) {
    return(sprintf("No matching %s performances were found%s.", stat_label, filter_suffix))
  }

  first_row <- rows[1, , drop = FALSE]
  performance_suffix <- sprintf(
    " in %s Round %s.",
    first_row$season[[1]],
    first_row$round_number[[1]]
  )

  if (identical(intent$intent_type, "highest")) {
    return(sprintf(
      "%s highest %s%s was %s%s",
      possessive_subject,
      stat_label,
      filter_suffix,
      format_query_number(first_row$total_value[[1]]),
      performance_suffix
    ))
  }

  if (identical(intent$intent_type, "lowest")) {
    return(sprintf(
      "%s lowest %s%s was %s%s",
      possessive_subject,
      stat_label,
      filter_suffix,
      format_query_number(first_row$total_value[[1]]),
      performance_suffix
    ))
  }

  if (identical(intent$subject_type, "players")) {
    return(sprintf(
      "Found %s matching player performances for %s%s.",
      format_query_number(total_matches),
      threshold_phrase,
      filter_suffix
    ))
  }
  if (identical(intent$subject_type, "teams")) {
    return(sprintf(
      "Found %s matching team performances for %s%s.",
      format_query_number(total_matches),
      threshold_phrase,
      filter_suffix
    ))
  }

  sprintf(
    "Found %s matching %s performances for %s%s.",
    format_query_number(total_matches),
    stat_label,
    subject,
    filter_suffix
  )
}

available_match_seasons <- function(conn) {
  query_rows(conn, "SELECT DISTINCT season FROM matches ORDER BY season DESC")$season
}

requested_or_available_seasons <- function(conn, seasons = NULL) {
  if (!is.null(seasons) && length(seasons)) {
    return(unique(as.integer(seasons)))
  }

  available_match_seasons(conn)
}

bind_query_result_rows <- function(rows_list) {
  if (!length(rows_list)) {
    return(data.frame())
  }

  non_empty <- Filter(function(rows) nrow(rows) > 0L, rows_list)
  if (!length(non_empty)) {
    return(rows_list[[1]][0, , drop = FALSE])
  }
  if (length(non_empty) == 1L) {
    return(non_empty[[1]])
  }

  do.call(rbind, non_empty)
}

sort_query_result_rows <- function(rows, intent_type = "list") {
  if (!nrow(rows)) {
    return(rows)
  }

  rows$season <- suppressWarnings(as.integer(rows$season))
  rows$round_number <- suppressWarnings(as.integer(rows$round_number))
  rows$total_value <- suppressWarnings(as.numeric(rows$total_value))
  label_column <- if ("player_name" %in% names(rows)) {
    "player_name"
  } else if ("squad_name" %in% names(rows)) {
    "squad_name"
  } else {
    NULL
  }
  rows$sort_label <- if (is.null(label_column)) {
    rep("", nrow(rows))
  } else {
    as.character(rows[[label_column]])
  }

  order_index <- if (identical(intent_type, "lowest")) {
    order(
      rows$total_value,
      -rows$season,
      -rows$round_number,
      rows$sort_label,
      na.last = TRUE
    )
  } else {
    order(
      -rows$total_value,
      -rows$season,
      -rows$round_number,
      rows$sort_label,
      na.last = TRUE
    )
  }

  ordered <- rows[order_index, , drop = FALSE]
  ordered$sort_label <- NULL
  ordered
}

# Fetches player leaderboard rows aggregated across all requested seasons in SQL.
# Returns one row per player with cross-season totals. ORDER BY and LIMIT are
# pushed to the database so only the top-N rows are transferred.
fetch_player_leader_rows <- function(conn, seasons = NULL, team_id = NULL, round = NULL, stat = "points", search = "", metric = "total", ranking = "highest", limit = 12L) {
  seasons_filter <- if (!is.null(seasons) && length(seasons)) as.integer(seasons) else NULL
  stats_table <- if (has_player_match_stats(conn)) "player_match_stats" else "player_period_stats"
  value_col   <- if (identical(stats_table, "player_match_stats")) "match_value" else "value_number"
  order_column <- if (identical(metric, "average")) "average_value" else "total_value"
  order_direction <- ranking_order_sql(ranking)
  has_participation <- has_player_match_stats(conn) && has_player_match_participation(conn)
  participation_join <- if (has_participation) {
    "INNER JOIN player_match_participation pmpart ON pmpart.player_id = stats.player_id AND pmpart.match_id = stats.match_id"
  } else ""
  matches_played_expr <- if (has_participation) "pmpart.match_id" else "stats.match_id"

  query <- paste(
    "SELECT stats.player_id, players.canonical_name AS player_name, MAX(stats.squad_name) AS squad_name,",
    paste0("?stat AS stat, ROUND(CAST(SUM(stats.", value_col, ") AS numeric), 2) AS total_value,"),
    paste0("COUNT(DISTINCT ", matches_played_expr, ") AS matches_played,"),
    paste0("ROUND(CAST(SUM(stats.", value_col, ") AS numeric) / NULLIF(COUNT(DISTINCT ", matches_played_expr, "), 0), 2) AS average_value"),
    paste0("FROM ", stats_table, " AS stats"),
    "INNER JOIN players ON players.player_id = stats.player_id",
    participation_join,
    "WHERE stats.stat = ?stat"
  )
  filters <- apply_stat_filters(
    query,
    list(stat = stat),
    seasons = seasons_filter,
    team_id = team_id,
    round_number = round,
    table_alias = "stats"
  )
  search_filters <- apply_player_search_filter(filters$query, filters$params, search, "stats.player_id")
  filters$query <- paste0(
    search_filters$query,
    " GROUP BY stats.player_id, players.canonical_name",
    " ORDER BY ", order_column, " ", order_direction, ", players.canonical_name ASC",
    " LIMIT ?limit"
  )
  filters$params <- search_filters$params
  filters$params$limit <- as.integer(limit)

  query_rows(conn, filters$query, filters$params)
}

fetch_player_season_metric_rows <- function(conn, seasons = NULL, team_id = NULL, round = NULL, stat = "points", search = "") {
  # Single query over all requested seasons; avoids one round-trip per season.
  # When seasons is NULL (no filter), omit the IN clause so the planner can do
  # a straight index scan on stat without a large IN list covering every season.
  seasons_filter <- if (!is.null(seasons) && length(seasons)) as.integer(seasons) else NULL

  # Use the pre-aggregated player_match_stats table when available — it has
  # one row per player per match instead of one per period, so GROUP BY at the
  # season level scans ~4x fewer rows.
  stats_table <- if (has_player_match_stats(conn)) "player_match_stats" else "player_period_stats"
  value_col   <- if (identical(stats_table, "player_match_stats")) "match_value" else "value_number"
  has_participation <- has_player_match_stats(conn) && has_player_match_participation(conn)
  participation_join <- if (has_participation) {
    "INNER JOIN player_match_participation pmpart ON pmpart.player_id = stats.player_id AND pmpart.match_id = stats.match_id"
  } else ""
  matches_played_expr <- if (has_participation) "pmpart.match_id" else "stats.match_id"

  query <- paste(
    "SELECT stats.player_id, players.canonical_name AS player_name, MAX(stats.squad_name) AS squad_name,",
    paste0("stats.season, ?stat AS stat, ROUND(CAST(SUM(stats.", value_col, ") AS numeric), 2) AS total_value,"),
    paste0("COUNT(DISTINCT ", matches_played_expr, ") AS matches_played,"),
    paste0("ROUND(CAST(SUM(stats.", value_col, ") AS numeric) / NULLIF(COUNT(DISTINCT ", matches_played_expr, "), 0), 2) AS average_value"),
    paste0("FROM ", stats_table, " AS stats"),
    "INNER JOIN players ON players.player_id = stats.player_id",
    participation_join,
    "WHERE stats.stat = ?stat"
  )
  filters <- apply_stat_filters(
    query,
    list(stat = stat),
    seasons = seasons_filter,
    team_id = team_id,
    round_number = round,
    table_alias = "stats"
  )
  search_filters <- apply_player_search_filter(filters$query, filters$params, search, "stats.player_id")
  filters$query <- paste0(
    search_filters$query,
    " GROUP BY stats.player_id, players.canonical_name, stats.season"
  )
  filters$params <- search_filters$params

  query_rows(conn, filters$query, filters$params)
}

summarize_player_metric_rows <- function(rows) {
  if (!nrow(rows)) {
    return(rows)
  }

  rows$player_id <- suppressWarnings(as.integer(rows$player_id))
  rows$player_name <- as.character(rows$player_name)
  rows$squad_name <- as.character(rows$squad_name)
  rows$season <- suppressWarnings(as.integer(rows$season))
  rows$total_value <- suppressWarnings(as.numeric(rows$total_value))
  rows$matches_played <- suppressWarnings(as.integer(rows$matches_played))

  group_keys <- interaction(
    as.character(rows$player_id),
    rows$player_name,
    drop = TRUE,
    lex.order = TRUE
  )

  combined_rows <- lapply(split(seq_len(nrow(rows)), group_keys), function(indices) {
    part <- rows[indices, , drop = FALSE]
    latest_index <- order(-part$season, part$squad_name, na.last = TRUE)[[1]]
    total_value <- round(sum(part$total_value, na.rm = TRUE), 2)
    matches_played <- sum(part$matches_played, na.rm = TRUE)

    data.frame(
      player_id = part$player_id[[1]],
      player_name = part$player_name[[1]],
      squad_name = part$squad_name[[latest_index]],
      stat = part$stat[[1]],
      total_value = total_value,
      matches_played = matches_played,
      average_value = round(total_value / ifelse(matches_played == 0, NA_real_, matches_played), 2),
      stringsAsFactors = FALSE
    )
  })

  combined <- do.call(rbind, combined_rows)
  rownames(combined) <- NULL
  combined
}

sort_player_leader_rows <- function(rows, metric = "total", ranking = "highest") {
  if (!nrow(rows)) {
    return(rows)
  }

  order_column <- if (identical(metric, "average")) "average_value" else "total_value"
  rows$total_value <- suppressWarnings(as.numeric(rows$total_value))
  rows$average_value <- suppressWarnings(as.numeric(rows$average_value))
  rows$player_name <- as.character(rows$player_name)

  if (identical(ranking, "lowest")) {
    return(rows[order(rows[[order_column]], rows$player_name, na.last = TRUE), , drop = FALSE])
  }

  rows[order(-rows[[order_column]], rows$player_name, na.last = TRUE), , drop = FALSE]
}

top_player_ids_from_series_rows <- function(rows, metric = "total", ranking = "highest", limit = 10L) {
  if (!nrow(rows)) {
    return(integer())
  }

  summarized <- summarize_player_metric_rows(rows)
  ranked <- sort_player_leader_rows(summarized, metric, ranking = ranking)
  head(as.integer(ranked$player_id), limit)
}

sort_player_series_rows <- function(rows, metric = "total", ranking = "highest") {
  if (!nrow(rows)) {
    return(rows)
  }

  order_column <- if (identical(metric, "average")) "average_value" else "total_value"
  rows$season <- suppressWarnings(as.integer(rows$season))
  rows$total_value <- suppressWarnings(as.numeric(rows$total_value))
  rows$average_value <- suppressWarnings(as.numeric(rows$average_value))
  rows$player_name <- as.character(rows$player_name)

  if (identical(ranking, "lowest")) {
    return(rows[order(rows$season, rows[[order_column]], rows$player_name, na.last = TRUE), , drop = FALSE])
  }

  rows[order(rows$season, -rows[[order_column]], rows$player_name, na.last = TRUE), , drop = FALSE]
}

fetch_player_game_high_rows <- function(conn, seasons = NULL, team_id = NULL, round = NULL, competition_phase = NULL, stat = "points", search = "", ranking = "highest", limit = 10L) {
  # Single query over all requested seasons; avoids one round-trip per season.
  # When seasons is NULL (no filter), omit the IN clause so the planner can do
  # a straight index scan on stat without a large IN list covering every season.
  seasons_filter <- if (!is.null(seasons) && length(seasons)) as.integer(seasons) else NULL
  order_direction <- ranking_order_sql(ranking)

  if (has_player_match_stats(conn)) {
    # Fast path: player_match_stats is pre-aggregated at match level — no
    # GROUP BY needed. ORDER BY + LIMIT uses idx_pms_stat_value directly.
    query <- paste(
      "SELECT pms.player_id, players.canonical_name AS player_name, pms.squad_name,",
      paste0(opponent_name_sql("pms.squad_id"), " AS opponent,"),
      "pms.season, pms.round_number, pms.match_id, matches.local_start_time,",
      "?stat AS stat, pms.match_value AS total_value",
      "FROM player_match_stats AS pms",
      "INNER JOIN players ON players.player_id = pms.player_id",
      "INNER JOIN matches ON matches.match_id = pms.match_id",
      "WHERE pms.stat = ?stat"
    )
    filters <- apply_stat_filters(
      query, list(stat = stat), seasons = seasons_filter, team_id = team_id,
      round_number = round, table_alias = "pms"
    )
    if (!is.null(competition_phase)) {
      filters$query <- paste0(filters$query, " AND COALESCE(matches.competition_phase, '') = ?competition_phase")
      filters$params$competition_phase <- as.character(competition_phase)
    }
    search_filters <- apply_player_search_filter(filters$query, filters$params, search, "pms.player_id")
    filters$query  <- paste0(
      search_filters$query,
      " ORDER BY pms.match_value ", order_direction, ", pms.season DESC, pms.round_number DESC, players.canonical_name ASC LIMIT ?limit"
    )
    filters$params <- search_filters$params
    filters$params$limit <- limit
    return(query_rows(conn, filters$query, filters$params))
  }

  # Fallback: aggregate period rows at query time (slower on B1ms)
  query <- paste(
    "SELECT stats.player_id, players.canonical_name AS player_name, stats.squad_name,",
    paste0(opponent_name_sql("stats.squad_id", aggregate = TRUE), " AS opponent,"),
    "stats.season, stats.round_number, stats.match_id, matches.local_start_time,",
    "?stat AS stat, ROUND(CAST(SUM(stats.value_number) AS numeric), 2) AS total_value",
    "FROM player_period_stats AS stats",
    "INNER JOIN players ON players.player_id = stats.player_id",
    "INNER JOIN matches ON matches.match_id = stats.match_id",
    "WHERE stats.stat = ?stat"
  )
  filters <- apply_stat_filters(
    query,
    list(stat = stat),
    seasons = seasons_filter,
    team_id = team_id,
    round_number = round,
    table_alias = "stats"
  )
  if (!is.null(competition_phase)) {
    filters$query <- paste0(filters$query, " AND COALESCE(matches.competition_phase, '') = ?competition_phase")
    filters$params$competition_phase <- as.character(competition_phase)
  }
  search_filters <- apply_player_search_filter(filters$query, filters$params, search, "stats.player_id")
  filters$query <- paste0(
    search_filters$query,
    " GROUP BY stats.player_id, players.canonical_name, stats.squad_name, stats.season, stats.round_number, stats.match_id, matches.local_start_time",
    " ORDER BY total_value ", order_direction, ", stats.season DESC, stats.round_number DESC, players.canonical_name ASC LIMIT ?limit"
  )
  filters$params <- search_filters$params
  filters$params$limit <- limit

  sort_query_result_rows(
    query_rows(conn, filters$query, filters$params),
    if (identical(ranking, "lowest")) "lowest" else "highest"
  )
}

fetch_team_game_high_rows <- function(conn, seasons = NULL, team_id = NULL, round = NULL, competition_phase = NULL, stat = "points", ranking = "highest", limit = 10L) {
  seasons_filter <- if (!is.null(seasons) && length(seasons)) as.integer(seasons) else NULL
  order_direction <- ranking_order_sql(ranking)

  if (has_team_match_stats(conn)) {
    # Fast path: team_match_stats is pre-aggregated at match level — no
    # GROUP BY needed. ORDER BY + LIMIT uses idx_tms_stat_value directly.
    query <- paste(
      "SELECT tms.squad_id, tms.squad_name,",
      paste0(opponent_name_sql("tms.squad_id"), " AS opponent,"),
      "tms.season, tms.round_number, tms.match_id, matches.local_start_time,",
      "?stat AS stat, tms.match_value AS total_value",
      "FROM team_match_stats AS tms",
      "INNER JOIN matches ON matches.match_id = tms.match_id",
      "WHERE tms.stat = ?stat"
    )
    filters <- apply_stat_filters(
      query, list(stat = stat), seasons = seasons_filter, team_id = team_id,
      round_number = round, table_alias = "tms"
    )
    if (!is.null(competition_phase)) {
      filters$query <- paste0(filters$query, " AND COALESCE(matches.competition_phase, '') = ?competition_phase")
      filters$params$competition_phase <- as.character(competition_phase)
    }
    filters$query <- paste0(
      filters$query,
      " ORDER BY tms.match_value ", order_direction, ", tms.season DESC, tms.round_number DESC, tms.squad_name ASC LIMIT ?limit"
    )
    filters$params$limit <- limit
    return(query_rows(conn, filters$query, filters$params))
  }

  # Fallback: aggregate period rows at query time (slower on B1ms)
  query <- paste(
    "SELECT stats.squad_id, stats.squad_name,",
    paste0(opponent_name_sql("stats.squad_id", aggregate = TRUE), " AS opponent,"),
    "stats.season, stats.round_number, stats.match_id, matches.local_start_time,",
    "?stat AS stat, ROUND(CAST(SUM(stats.value_number) AS numeric), 2) AS total_value",
    "FROM team_period_stats AS stats",
    "INNER JOIN matches ON matches.match_id = stats.match_id",
    "WHERE stats.stat = ?stat"
  )
  filters <- apply_stat_filters(
    query,
    list(stat = stat),
    seasons = seasons_filter,
    team_id = team_id,
    round_number = round,
    table_alias = "stats"
  )
  if (!is.null(competition_phase)) {
    filters$query <- paste0(filters$query, " AND COALESCE(matches.competition_phase, '') = ?competition_phase")
    filters$params$competition_phase <- as.character(competition_phase)
  }
  filters$query <- paste0(
    filters$query,
    " GROUP BY stats.squad_id, stats.squad_name, stats.season, stats.round_number, stats.match_id, matches.local_start_time",
    " ORDER BY total_value ", order_direction, ", stats.season DESC, stats.round_number DESC, stats.squad_name ASC LIMIT ?limit"
  )
  filters$params$limit <- limit

  query_rows(conn, filters$query, filters$params)
}

numeric_equal <- function(left, right, tolerance = 1e-9) {
  if (is.null(left) || is.null(right) || any(is.na(c(left, right)))) {
    return(FALSE)
  }

  abs(as.numeric(left) - as.numeric(right)) <= tolerance
}

record_badge_label <- function(scope = c("season", "archive"), ranking = "highest") {
  scope <- match.arg(scope)
  prefix <- if (identical(scope, "season")) "Season" else "Archive"
  suffix <- if (identical(ranking, "lowest")) "low" else "high"
  paste(prefix, suffix)
}

extract_first_numeric <- function(rows, column = "total_value") {
  if (!nrow(rows) || !(column %in% names(rows))) {
    return(NA_real_)
  }

  suppressWarnings(as.numeric(rows[[column]][[1]]))
}

# ---------------------------------------------------------------------------
# Batch spotlight helpers — reduce ~195 queries to ~30 per round-summary call
# ---------------------------------------------------------------------------

# Validates that stat names are alphanumeric camelCase (internal constants only,
# never user input) and returns a SQL IN list string.
safe_stat_in_sql <- function(stats) {
  valid <- stats[grepl("^[A-Za-z0-9]+$", stats)]
  dropped <- setdiff(stats, valid)
  if (length(dropped)) stop("Invalid stat names rejected from SQL list: ", paste(dropped, collapse = ", "))
  if (!length(valid)) return("")
  paste(sprintf("'%s'", valid), collapse = ", ")
}

# Batch-fetch the top-1 player row per stat for a given season/round in a single
# DB round-trip.  Returns a named list keyed by stat name.
fetch_player_spotlight_rows <- function(conn, seasons, round, competition_phase, stats) {
  empty <- setNames(lapply(stats, function(s) data.frame()), stats)
  if (!length(stats)) return(empty)
  stat_sql <- safe_stat_in_sql(stats)
  if (!nzchar(stat_sql)) return(empty)

  if (has_player_match_stats(conn)) {
    query <- paste0(
      "WITH ranked AS (",
      " SELECT pms.stat, pms.player_id, players.canonical_name AS player_name, pms.squad_name,",
      "   ", opponent_name_sql("pms.squad_id"), " AS opponent,",
      "   pms.season, pms.round_number, pms.match_id, matches.local_start_time,",
      "   pms.match_value AS total_value,",
      "   ROW_NUMBER() OVER (PARTITION BY pms.stat",
      "     ORDER BY pms.match_value DESC, pms.season DESC, pms.round_number DESC,",
      "              players.canonical_name ASC) AS rn",
      " FROM player_match_stats pms",
      " INNER JOIN players ON players.player_id = pms.player_id",
      " INNER JOIN matches ON matches.match_id = pms.match_id",
      " WHERE pms.stat IN (", stat_sql, ")",
      "   AND pms.season = ?season",
      "   AND pms.round_number = ?round_number",
      "   AND COALESCE(matches.competition_phase, '') = ?competition_phase",
      ")",
      " SELECT stat, player_id, player_name, squad_name, opponent,",
      "   season, round_number, match_id, local_start_time, total_value",
      " FROM ranked WHERE rn = 1"
    )
    rows <- tryCatch(
      query_rows(conn, query, list(
        season            = as.integer(seasons[[1]]),
        round_number      = as.integer(round),
        competition_phase = as.character(competition_phase %||% "")
      )),
      error = function(e) {
        api_log("WARN", "spotlight_player_batch_failed",
          error_class = paste(class(e), collapse = "/"),
          error_message = conditionMessage(e))
        data.frame()
      }
    )
    result <- lapply(stats, function(s) {
      r <- rows[!is.na(rows$stat) & rows$stat == s, , drop = FALSE]
      if (nrow(r)) r else data.frame()
    })
    names(result) <- stats
    return(result)
  }

  # Fallback when player_match_stats is unavailable
  lapply(setNames(stats, stats), function(s) {
    fetch_player_game_high_rows(
      conn, seasons = seasons, round = round,
      competition_phase = competition_phase,
      stat = s, ranking = "highest", limit = 1L
    )
  })
}

# Batch-fetch the top-1 team row per stat for a given season/round in a single
# DB round-trip.  Returns a named list keyed by stat name.
fetch_team_spotlight_rows <- function(conn, seasons, round, competition_phase, stats, ranking = "highest") {
  empty <- setNames(lapply(stats, function(s) data.frame()), stats)
  if (!length(stats)) return(empty)
  stat_sql <- safe_stat_in_sql(stats)
  if (!nzchar(stat_sql)) return(empty)
  order_dir <- ranking_order_sql(ranking)

  if (has_team_match_stats(conn)) {
    query <- paste0(
      "WITH ranked AS (",
      " SELECT tms.stat, tms.squad_id, tms.squad_name,",
      "   ", opponent_name_sql("tms.squad_id"), " AS opponent,",
      "   tms.season, tms.round_number, tms.match_id, matches.local_start_time,",
      "   tms.match_value AS total_value,",
      "   ROW_NUMBER() OVER (PARTITION BY tms.stat",
      "     ORDER BY tms.match_value ", order_dir, ", tms.season DESC, tms.round_number DESC,",
      "              tms.squad_name ASC) AS rn",
      " FROM team_match_stats tms",
      " INNER JOIN matches ON matches.match_id = tms.match_id",
      " WHERE tms.stat IN (", stat_sql, ")",
      "   AND tms.season = ?season",
      "   AND tms.round_number = ?round_number",
      "   AND COALESCE(matches.competition_phase, '') = ?competition_phase",
      ")",
      " SELECT stat, squad_id, squad_name, opponent,",
      "   season, round_number, match_id, local_start_time, total_value",
      " FROM ranked WHERE rn = 1"
    )
    rows <- tryCatch(
      query_rows(conn, query, list(
        season            = as.integer(seasons[[1]]),
        round_number      = as.integer(round),
        competition_phase = as.character(competition_phase %||% "")
      )),
      error = function(e) {
        api_log("WARN", "spotlight_team_batch_failed",
          error_class = paste(class(e), collapse = "/"),
          error_message = conditionMessage(e))
        data.frame()
      }
    )
    result <- lapply(stats, function(s) {
      r <- rows[!is.na(rows$stat) & rows$stat == s, , drop = FALSE]
      if (nrow(r)) r else data.frame()
    })
    names(result) <- stats
    return(result)
  }

  # Fallback: aggregate period rows at query time
  query <- paste0(
    "WITH agg AS (",
    " SELECT stats.stat, stats.squad_id, stats.squad_name,",
    "   ", opponent_name_sql("stats.squad_id", aggregate = TRUE), " AS opponent,",
    "   stats.season, stats.round_number, stats.match_id, matches.local_start_time,",
    "   ROUND(CAST(SUM(stats.value_number) AS numeric), 2) AS total_value",
    " FROM team_period_stats stats",
    " INNER JOIN matches ON matches.match_id = stats.match_id",
    " WHERE stats.stat IN (", stat_sql, ")",
    "   AND stats.season = ?season",
    "   AND stats.round_number = ?round_number",
    "   AND COALESCE(matches.competition_phase, '') = ?competition_phase",
    " GROUP BY stats.stat, stats.squad_id, stats.squad_name,",
    "   stats.season, stats.round_number, stats.match_id, matches.local_start_time",
    "), ranked AS (",
    " SELECT *,",
    "   ROW_NUMBER() OVER (PARTITION BY stat",
    "     ORDER BY total_value ", order_dir, ", season DESC, round_number DESC, squad_name ASC) AS rn",
    " FROM agg",
    ")",
    " SELECT stat, squad_id, squad_name, opponent,",
    "   season, round_number, match_id, local_start_time, total_value",
    " FROM ranked WHERE rn = 1"
  )

  rows <- tryCatch(
    query_rows(conn, query, list(
      season            = as.integer(seasons[[1]]),
      round_number      = as.integer(round),
      competition_phase = as.character(competition_phase %||% "")
    )),
    error = function(e) {
      api_log("WARN", "spotlight_team_batch_failed",
        error_class = paste(class(e), collapse = "/"),
        error_message = conditionMessage(e))
      data.frame()
    }
  )

  result <- lapply(stats, function(s) {
    r <- rows[!is.na(rows$stat) & rows$stat == s, , drop = FALSE]
    if (nrow(r)) r else data.frame()
  })
  names(result) <- stats
  result
}

# Batch-fetch the best value per stat across all time (season=NULL) or within a season.
# Returns a named numeric vector.
fetch_spotlight_bests <- function(conn, subject_type, stats, season = NULL, ranking = "highest") {
  result <- setNames(rep(NA_real_, length(stats)), stats)
  if (!length(stats)) return(result)
  stat_sql <- safe_stat_in_sql(stats)
  if (!nzchar(stat_sql)) return(result)
  agg_fn        <- if (identical(ranking, "highest")) "MAX" else "MIN"
  season_clause <- if (!is.null(season)) " AND season = ?season" else ""
  params        <- if (!is.null(season)) list(season = as.integer(season)) else list()

  query <- if (identical(subject_type, "player") && has_player_match_stats(conn)) {
    paste0(
      "SELECT stat, ", agg_fn, "(match_value) AS best_value",
      " FROM player_match_stats WHERE stat IN (", stat_sql, ")", season_clause,
      " GROUP BY stat"
    )
  } else if (identical(subject_type, "player")) {
    paste0(
      "SELECT stat, ", agg_fn, "(total_value) AS best_value FROM (",
      " SELECT stat, player_id, match_id,",
      "   ROUND(CAST(SUM(value_number) AS numeric), 2) AS total_value",
      " FROM player_period_stats WHERE stat IN (", stat_sql, ")", season_clause,
      " GROUP BY stat, player_id, match_id) sub GROUP BY stat"
    )
  } else if (identical(subject_type, "team") && has_team_match_stats(conn)) {
    paste0(
      "SELECT stat, ", agg_fn, "(match_value) AS best_value",
      " FROM team_match_stats WHERE stat IN (", stat_sql, ")", season_clause,
      " GROUP BY stat"
    )
  } else {
    paste0(
      "SELECT stat, ", agg_fn, "(total_value) AS best_value FROM (",
      " SELECT stat, squad_id, match_id,",
      "   ROUND(CAST(SUM(value_number) AS numeric), 2) AS total_value",
      " FROM team_period_stats WHERE stat IN (", stat_sql, ")", season_clause,
      " GROUP BY stat, squad_id, match_id) sub GROUP BY stat"
    )
  }
  rows <- tryCatch(
    query_rows(conn, query, params),
    error = function(e) {
      api_log("WARN", "spotlight_bests_failed",
        error_class = paste(class(e), collapse = "/"),
        error_message = conditionMessage(e))
      data.frame()
    }
  )
  if (nrow(rows) && all(c("stat", "best_value") %in% names(rows))) {
    for (i in seq_len(nrow(rows))) {
      s <- as.character(rows$stat[[i]])
      if (s %in% names(result)) {
        result[[s]] <- suppressWarnings(as.numeric(rows$best_value[[i]]))
      }
    }
  }
  result
}

# Combined single-query fetch of archive bests AND archive ranks per stat.
# Saves one DB round-trip vs calling fetch_spotlight_bests + batch_compute_archive_ranks.
# stat_values: named list of stat -> numeric threshold (NA values pre-filtered).
# Returns list(bests = named numeric, ranks = named integer).
fetch_spotlight_archive_data <- function(conn, subject_type, stat_values, ranking = "highest") {
  stats      <- names(stat_values)
  stat_sql   <- safe_stat_in_sql(stats)
  agg_fn     <- if (identical(ranking, "highest")) "MAX" else "MIN"
  compare_op <- if (identical(ranking, "highest")) ">" else "<"

  empty_bests <- setNames(rep(NA_real_,    length(stats)), stats)
  empty_ranks <- setNames(rep(NA_integer_, length(stats)), stats)
  if (!length(stats) || !nzchar(stat_sql)) return(list(bests = empty_bests, ranks = empty_ranks))

  make_rank_case <- function(value_col) {
    parts <- vapply(stats, function(s) {
      v <- as.numeric(stat_values[[s]])
      sprintf("WHEN stat = '%s' AND %s %s %.15g THEN 1", s, value_col, compare_op, v)
    }, character(1))
    paste0("CASE ", paste(parts, collapse = " "), " END")
  }

  query <- tryCatch({
    if (identical(subject_type, "player") && has_player_match_stats(conn)) {
      paste0(
        "SELECT stat, ", agg_fn, "(match_value) AS best_value,",
        " COUNT(", make_rank_case("match_value"), ") + 1 AS rank_for_stat",
        " FROM player_match_stats WHERE stat IN (", stat_sql, ")",
        " GROUP BY stat"
      )
    } else if (identical(subject_type, "player")) {
      paste0(
        "SELECT stat, ", agg_fn, "(total_value) AS best_value,",
        " COUNT(", make_rank_case("total_value"), ") + 1 AS rank_for_stat FROM (",
        " SELECT stat, player_id, match_id,",
        "   ROUND(CAST(SUM(value_number) AS numeric), 2) AS total_value",
        " FROM player_period_stats WHERE stat IN (", stat_sql, ")",
        " GROUP BY stat, player_id, match_id) sub GROUP BY stat"
      )
    } else if (identical(subject_type, "team") && has_team_match_stats(conn)) {
      paste0(
        "SELECT stat, ", agg_fn, "(match_value) AS best_value,",
        " COUNT(", make_rank_case("match_value"), ") + 1 AS rank_for_stat",
        " FROM team_match_stats WHERE stat IN (", stat_sql, ")",
        " GROUP BY stat"
      )
    } else {
      paste0(
        "SELECT stat, ", agg_fn, "(total_value) AS best_value,",
        " COUNT(", make_rank_case("total_value"), ") + 1 AS rank_for_stat FROM (",
        " SELECT stat, squad_id, match_id,",
        "   ROUND(CAST(SUM(value_number) AS numeric), 2) AS total_value",
        " FROM team_period_stats WHERE stat IN (", stat_sql, ")",
        " GROUP BY stat, squad_id, match_id) sub GROUP BY stat"
      )
    }
  }, error = function(e) NULL)
  rows <- tryCatch(query_rows(conn, query, list()), error = function(e) data.frame())

  bests <- empty_bests
  ranks <- empty_ranks
  if (nrow(rows) && "stat" %in% names(rows)) {
    for (i in seq_len(nrow(rows))) {
      s <- as.character(rows$stat[[i]])
      if (s %in% stats) {
        if ("best_value" %in% names(rows))
          bests[[s]] <- suppressWarnings(as.numeric(rows$best_value[[i]]))
        if ("rank_for_stat" %in% names(rows)) {
          r <- suppressWarnings(as.integer(rows$rank_for_stat[[i]]))
          if (!is.na(r) && r > 0L) ranks[[s]] <- r
        }
      }
    }
  }
  list(bests = bests, ranks = ranks)
}

# Batch-compute the historical rank for multiple (stat, value) pairs in one
# DB round-trip using a CASE WHEN counting pattern.
# stat_values: named list of stat -> numeric value (NA values pre-filtered).
# Returns a named integer vector.
batch_compute_archive_ranks <- function(conn, subject_type, stat_values, ranking = "highest") {
  if (!length(stat_values)) return(setNames(integer(0), character(0)))
  stats      <- names(stat_values)
  stat_sql   <- safe_stat_in_sql(stats)
  compare_op <- if (identical(ranking, "highest")) ">" else "<"
  result     <- setNames(rep(NA_integer_, length(stats)), stats)

  make_case <- function(value_col) {
    parts <- vapply(stats, function(s) {
      v <- as.numeric(stat_values[[s]])
      sprintf("WHEN stat = '%s' AND %s %s %.15g THEN 1", s, value_col, compare_op, v)
    }, character(1))
    paste0("CASE ", paste(parts, collapse = " "), " END")
  }

  query <- tryCatch({
    if (identical(subject_type, "player") && has_player_match_stats(conn)) {
      paste0(
        "SELECT stat, COUNT(", make_case("match_value"), ") + 1 AS rank",
        " FROM player_match_stats WHERE stat IN (", stat_sql, ")",
        " GROUP BY stat"
      )
    } else if (identical(subject_type, "player")) {
      paste0(
        "SELECT stat, COUNT(", make_case("total_value"), ") + 1 AS rank FROM (",
        " SELECT stat, player_id, match_id,",
        "   ROUND(CAST(SUM(value_number) AS numeric), 2) AS total_value",
        " FROM player_period_stats WHERE stat IN (", stat_sql, ")",
        " GROUP BY stat, player_id, match_id) sub GROUP BY stat"
      )
    } else if (identical(subject_type, "team") && has_team_match_stats(conn)) {
      paste0(
        "SELECT stat, COUNT(", make_case("match_value"), ") + 1 AS rank",
        " FROM team_match_stats WHERE stat IN (", stat_sql, ")",
        " GROUP BY stat"
      )
    } else {
      paste0(
        "SELECT stat, COUNT(", make_case("total_value"), ") + 1 AS rank FROM (",
        " SELECT stat, squad_id, match_id,",
        "   ROUND(CAST(SUM(value_number) AS numeric), 2) AS total_value",
        " FROM team_period_stats WHERE stat IN (", stat_sql, ")",
        " GROUP BY stat, squad_id, match_id) sub GROUP BY stat"
      )
    }
  }, error = function(e) NULL)

  if (is.null(query)) return(result)
  rows <- tryCatch(query_rows(conn, query, list()), error = function(e) data.frame())
  if (nrow(rows) && all(c("stat", "rank") %in% names(rows))) {
    for (i in seq_len(nrow(rows))) {
      s <- as.character(rows$stat[[i]])
      if (s %in% names(result)) {
        r <- suppressWarnings(as.integer(rows$rank[[i]]))
        if (!is.na(r) && r > 0L) result[[s]] <- r
      }
    }
  }
  result
}

# Pure function: compute record badges from pre-fetched best vectors (no DB access).
spotlight_badges <- function(stat, ranking, total_value, season_bests, archive_bests) {
  if (is.null(total_value) || is.na(total_value)) return(character())
  compare_fn   <- if (identical(ranking, "highest")) `>=` else `<=`
  badges       <- character()
  season_best  <- season_bests[[stat]]
  archive_best <- archive_bests[[stat]]
  if (!is.null(season_best)  && !is.na(season_best)  && compare_fn(as.numeric(total_value), as.numeric(season_best)))
    badges <- c(badges, record_badge_label("season",  ranking))
  if (!is.null(archive_best) && !is.na(archive_best) && compare_fn(as.numeric(total_value), as.numeric(archive_best)))
    badges <- c(badges, record_badge_label("archive", ranking))
  badges
}

# ---------------------------------------------------------------------------

fetch_player_points_high <- function(conn, seasons = NULL, round = NULL, competition_phase = NULL, ranking = "highest", limit = 1L) {
  order_direction <- ranking_order_sql(ranking)

  query <- paste(
    "SELECT pms1.player_id, players.canonical_name AS player_name, pms1.squad_name,",
    paste0(opponent_name_sql("pms1.squad_id"), " AS opponent,"),
    "pms1.season, pms1.round_number, pms1.match_id, matches.local_start_time,",
    "'points' AS stat,",
    "(COALESCE(pms1.match_value, 0) + 2 * COALESCE(pms2.match_value, 0)) AS total_value",
    "FROM player_match_stats AS pms1",
    "LEFT JOIN player_match_stats AS pms2",
    "  ON pms1.player_id = pms2.player_id AND pms1.match_id = pms2.match_id AND pms2.stat = 'goal2'",
    "INNER JOIN players ON players.player_id = pms1.player_id",
    "INNER JOIN matches ON matches.match_id = pms1.match_id",
    "WHERE pms1.stat = 'goal1'"
  )

  params <- list()
  seasons_filter <- if (!is.null(seasons) && length(seasons)) as.integer(seasons) else NULL
  if (!is.null(seasons_filter)) {
    season_result <- append_integer_in_filter(query, params, "pms1.season", seasons_filter, "season")
    query  <- season_result$query
    params <- season_result$params
  }
  if (!is.null(round)) {
    query <- paste0(query, " AND pms1.round_number = ?round_number")
    params$round_number <- as.integer(round)
  }
  if (!is.null(competition_phase)) {
    query <- paste0(query, " AND COALESCE(matches.competition_phase, '') = ?competition_phase")
    params$competition_phase <- as.character(competition_phase)
  }
  query <- paste0(
    query,
    " ORDER BY total_value ", order_direction,
    ", pms1.season DESC, pms1.round_number DESC, players.canonical_name ASC LIMIT ?limit"
  )
  params$limit <- limit

  query_rows(conn, query, params)
}

fetch_team_points_high <- function(conn, seasons = NULL, round = NULL, competition_phase = NULL, ranking = "highest", limit = 1L) {
  order_direction <- ranking_order_sql(ranking)

  query <- paste(
    "SELECT sq.squad_id, sq.squad_name, sq.opponent, sq.season, sq.round_number, sq.match_id,",
    "sq.local_start_time, 'points' AS stat, sq.total_value",
    "FROM (",
    "  SELECT m.home_squad_id AS squad_id, m.home_squad_name AS squad_name, m.away_squad_name AS opponent,",
    "  m.season, m.round_number, m.match_id, m.local_start_time,",
    "  COALESCE(m.competition_phase, '') AS competition_phase, CAST(m.home_score AS numeric) AS total_value",
    "  FROM matches m WHERE m.home_score IS NOT NULL",
    "  UNION ALL",
    "  SELECT m.away_squad_id, m.away_squad_name, m.home_squad_name,",
    "  m.season, m.round_number, m.match_id, m.local_start_time,",
    "  COALESCE(m.competition_phase, ''), CAST(m.away_score AS numeric)",
    "  FROM matches m WHERE m.away_score IS NOT NULL",
    ") sq WHERE 1=1"
  )

  params <- list()
  seasons_filter <- if (!is.null(seasons) && length(seasons)) as.integer(seasons) else NULL
  if (!is.null(seasons_filter)) {
    season_result <- append_integer_in_filter(query, params, "sq.season", seasons_filter, "season")
    query  <- season_result$query
    params <- season_result$params
  }
  if (!is.null(round)) {
    query <- paste0(query, " AND sq.round_number = ?round_number")
    params$round_number <- as.integer(round)
  }
  if (!is.null(competition_phase)) {
    query <- paste0(query, " AND sq.competition_phase = ?competition_phase")
    params$competition_phase <- as.character(competition_phase)
  }
  query <- paste0(
    query,
    sprintf(" ORDER BY sq.total_value %s, sq.season DESC, sq.round_number DESC, sq.squad_name ASC LIMIT ?limit", order_direction)
  )
  params$limit <- limit

  query_rows(conn, query, params)
}

points_record_badges <- function(conn, subject_type = c("team", "player"), ranking = "highest", total_value, season) {
  subject_type <- match.arg(subject_type)

  if (is.null(total_value) || is.na(total_value) || is.null(season) || is.na(season)) {
    return(character())
  }

  fetcher <- if (identical(subject_type, "team")) fetch_team_points_high else fetch_player_points_high
  season_best  <- fetcher(conn, seasons = as.integer(season), ranking = ranking, limit = 1L)
  archive_best <- fetcher(conn, seasons = NULL,               ranking = ranking, limit = 1L)

  badges <- character()
  if (numeric_equal(total_value, extract_first_numeric(season_best))) {
    badges <- c(badges, record_badge_label("season", ranking))
  }
  if (numeric_equal(total_value, extract_first_numeric(archive_best))) {
    badges <- c(badges, record_badge_label("archive", ranking))
  }
  unique(badges)
}

compute_archive_rank <- function(conn, subject_type = c("team", "player"), stat, ranking = "highest", total_value) {
  subject_type <- match.arg(subject_type)

  if (is.null(total_value) || is.na(total_value)) {
    return(NA_integer_)
  }

  compare_op <- if (identical(ranking, "highest")) ">" else "<"

  count_row <- tryCatch({
    if (identical(stat, "points")) {
      if (identical(subject_type, "player")) {
        query_rows(
          conn,
          paste0(
            "SELECT COUNT(*) + 1 AS rank FROM (",
            " SELECT COALESCE(pms1.match_value, 0) + 2 * COALESCE(pms2.match_value, 0) AS total_value",
            " FROM player_match_stats pms1",
            " LEFT JOIN player_match_stats pms2",
            "   ON pms1.player_id = pms2.player_id AND pms1.match_id = pms2.match_id AND pms2.stat = 'goal2'",
            " WHERE pms1.stat = 'goal1'",
            ") sub WHERE total_value ", compare_op, " ?total_value"
          ),
          list(total_value = as.numeric(total_value))
        )
      } else {
        query_rows(
          conn,
          paste0(
            "SELECT COUNT(*) + 1 AS rank FROM (",
            " SELECT CAST(home_score AS numeric) AS total_value FROM matches WHERE home_score IS NOT NULL",
            " UNION ALL",
            " SELECT CAST(away_score AS numeric) FROM matches WHERE away_score IS NOT NULL",
            ") sq WHERE total_value ", compare_op, " ?total_value"
          ),
          list(total_value = as.numeric(total_value))
        )
      }
    } else if (identical(subject_type, "player")) {
      if (has_player_match_stats(conn)) {
        query_rows(
          conn,
          paste0(
            "SELECT COUNT(*) + 1 AS rank FROM player_match_stats",
            " WHERE stat = ?stat AND match_value ", compare_op, " ?total_value"
          ),
          list(stat = stat, total_value = as.numeric(total_value))
        )
      } else {
        query_rows(
          conn,
          paste0(
            "SELECT COUNT(*) + 1 AS rank FROM (",
            " SELECT ROUND(CAST(SUM(value_number) AS numeric), 2) AS total_value",
            " FROM player_period_stats WHERE stat = ?stat GROUP BY player_id, match_id",
            ") sub WHERE total_value ", compare_op, " ?total_value"
          ),
          list(stat = stat, total_value = as.numeric(total_value))
        )
      }
    } else if (has_team_match_stats(conn)) {
      query_rows(
        conn,
        paste0(
          "SELECT COUNT(*) + 1 AS rank FROM team_match_stats",
          " WHERE stat = ?stat AND match_value ", compare_op, " ?total_value"
        ),
        list(stat = stat, total_value = as.numeric(total_value))
      )
    } else {
      query_rows(
        conn,
        paste0(
          "SELECT COUNT(*) + 1 AS rank FROM (",
          " SELECT ROUND(CAST(SUM(value_number) AS numeric), 2) AS total_value",
          " FROM team_period_stats WHERE stat = ?stat GROUP BY squad_id, match_id",
          ") sub WHERE total_value ", compare_op, " ?total_value"
        ),
        list(stat = stat, total_value = as.numeric(total_value))
      )
    }
  }, error = function(e) {
    data.frame(rank = NA_integer_)
  })

  rank_val <- suppressWarnings(as.integer(count_row$rank[[1]] %||% NA_integer_))
  if (is.na(rank_val) || rank_val <= 0L) return(NA_integer_)
  rank_val
}

game_record_badges <- function(conn, subject_type = c("team", "player"), stat, ranking = "highest", total_value, season) {
  subject_type <- match.arg(subject_type)

  if (is.null(total_value) || is.na(total_value) || is.null(season) || is.na(season)) {
    return(character())
  }

  fetcher <- if (identical(subject_type, "team")) fetch_team_game_high_rows else fetch_player_game_high_rows
  season_best <- fetcher(
    conn,
    seasons = as.integer(season),
    stat = stat,
    ranking = ranking,
    limit = 1L
  )
  archive_best <- fetcher(
    conn,
    seasons = NULL,
    stat = stat,
    ranking = ranking,
    limit = 1L
  )

  badges <- character()
  if (numeric_equal(total_value, extract_first_numeric(season_best))) {
    badges <- c(badges, record_badge_label("season", ranking))
  }
  if (numeric_equal(total_value, extract_first_numeric(archive_best))) {
    badges <- c(badges, record_badge_label("archive", ranking))
  }

  unique(badges)
}

margin_record_badges <- function(conn, margin_value, season) {
  if (is.null(margin_value) || is.na(margin_value) || is.null(season) || is.na(season)) {
    return(character())
  }

  row <- query_rows(
    conn,
    paste(
      "SELECT",
      "  MAX(CASE WHEN season = ?season THEN ABS(home_score - away_score) END) AS season_max,",
      "  MAX(ABS(home_score - away_score)) AS archive_max",
      "FROM matches",
      "WHERE home_score IS NOT NULL AND away_score IS NOT NULL"
    ),
    list(season = as.integer(season))
  )

  badges <- character()
  if (numeric_equal(margin_value, extract_first_numeric(row, "season_max"))) {
    badges <- c(badges, record_badge_label("season", "highest"))
  }
  if (numeric_equal(margin_value, extract_first_numeric(row, "archive_max"))) {
    badges <- c(badges, record_badge_label("archive", "highest"))
  }

  unique(badges)
}

format_round_label <- function(competition_phase, round_number) {
  phase <- trimws(as.character(competition_phase %||% ""))

  if (!nzchar(phase) || grepl("^regular", phase, ignore.case = TRUE)) {
    return(sprintf("Round %s", round_number))
  }

  sprintf("%s Round %s", phase, round_number)
}

fetch_latest_completed_round <- function(conn, season = NULL, round = NULL) {
  query <- paste(
    "SELECT season, COALESCE(competition_phase, '') AS competition_phase, round_number,",
    "COUNT(*) AS total_matches, MAX(local_start_time) AS round_end_time",
    "FROM matches",
    "WHERE home_score IS NOT NULL AND away_score IS NOT NULL"
  )
  params <- list()

  if (!is.null(season)) {
    query <- paste0(query, " AND season = ?season")
    params$season <- as.integer(season)
  }

  if (!is.null(round)) {
    query <- paste0(query, " AND round_number = ?round_number")
    params$round_number <- as.integer(round)
  }

  query <- paste0(
    query,
    " GROUP BY season, COALESCE(competition_phase, ''), round_number",
    " ORDER BY season DESC, round_end_time DESC, round_number DESC LIMIT 1"
  )

  query_rows(conn, query, params)
}

fetch_round_matches <- function(conn, season, competition_phase = "", round_number) {
  query_rows(
    conn,
    paste(
      "SELECT match_id, season, COALESCE(competition_phase, '') AS competition_phase, round_number, game_number, local_start_time, venue_name,",
      "home_squad_id, home_squad_name, home_score, away_squad_id, away_squad_name, away_score,",
      "ABS(home_score - away_score) AS margin,",
      "CASE",
      "WHEN home_score = away_score THEN 'Draw'",
      "WHEN home_score > away_score THEN home_squad_name",
      "ELSE away_squad_name",
      "END AS winner_name",
      "FROM matches",
      "WHERE home_score IS NOT NULL AND away_score IS NOT NULL",
      "AND season = ?season",
      "AND COALESCE(competition_phase, '') = ?competition_phase",
      "AND round_number = ?round_number",
      "ORDER BY local_start_time ASC, game_number ASC, match_id ASC"
    ),
    list(
      season = as.integer(season),
      competition_phase = as.character(competition_phase %||% ""),
      round_number = as.integer(round_number)
    )
  )
}

build_round_match_summary <- function(matches) {
  if (!nrow(matches)) {
    return(list(
      total_matches = 0L,
      total_goals = 0,
      biggest_margin = NULL,
      closest_margin = NULL,
      average_margin = NULL,
      round_high_team_score = NULL,
      biggest_margin_match = NULL,
      closest_match = NULL
    ))
  }

  all_scores <- suppressWarnings(as.numeric(c(matches$home_score, matches$away_score)))
  margins <- suppressWarnings(as.numeric(matches$margin))
  biggest_index <- which.max(margins)
  closest_index <- which.min(margins)

  list(
    total_matches = nrow(matches),
    total_goals = sum(all_scores, na.rm = TRUE),
    biggest_margin = suppressWarnings(as.numeric(matches$margin[[biggest_index]])),
    closest_margin = suppressWarnings(as.numeric(matches$margin[[closest_index]])),
    average_margin = round(mean(margins, na.rm = TRUE), 1),
    round_high_team_score = max(all_scores, na.rm = TRUE),
    biggest_margin_match = row_to_record(matches, biggest_index),
    closest_match = row_to_record(matches, closest_index)
  )
}

performance_entry_from_row <- function(row, title, subject_type = c("player", "team"), ranking = "highest", badges = character(), historical_rank = NULL) {
  subject_type <- match.arg(subject_type)

  if (!nrow(row)) {
    return(NULL)
  }

  list(
    title = title,
    stat = normalize_record_value(row$stat[[1]]),
    stat_label = query_stat_label(as.character(row$stat[[1]])),
    ranking = ranking,
    value = suppressWarnings(as.numeric(row$total_value[[1]])),
    subject_name = normalize_record_value(row[[if (identical(subject_type, "player")) "player_name" else "squad_name"]][[1]]),
    squad_name = normalize_record_value(row$squad_name[[1]] %||% NULL),
    opponent = normalize_record_value(row$opponent[[1]] %||% NULL),
    season = suppressWarnings(as.integer(row$season[[1]])),
    round_number = suppressWarnings(as.integer(row$round_number[[1]])),
    local_start_time = normalize_record_value(row$local_start_time[[1]] %||% NULL),
    player_id = if (identical(subject_type, "player") && "player_id" %in% names(row)) suppressWarnings(as.integer(row$player_id[[1]])) else NULL,
    badges = unique(as.character(badges)),
    historical_rank = if (!is.null(historical_rank) && !is.na(historical_rank)) as.integer(historical_rank) else NULL
  )
}

build_round_fact <- function(title, value, detail, badges = character()) {
  list(
    title = title,
    value = value,
    detail = detail,
    badges = unique(as.character(badges))
  )
}

# Per-process cache for round summary payloads (keyed by season+round+phase).
# Cleared automatically when the Container App restarts (e.g. after a DB refresh).
.round_summary_cache <- new.env(parent = emptyenv())
.round_cache_ttl_secs <- 3600L  # 1 hour

build_round_summary_payload <- function(conn, season = NULL, round = NULL) {
  # Fast path: when both season and round are specified, we can build the cache
  # key immediately and skip the DB lookup entirely on a hit.
  if (!is.null(season) && !is.null(round)) {
    fast_key <- paste0(as.integer(season), "_", as.integer(round), "_")
    # Try an exact key match; also check with known phase suffixes.
    for (candidate_key in ls(envir = .round_summary_cache)) {
      if (startsWith(candidate_key, fast_key)) {
        cached <- .round_summary_cache[[candidate_key]]
        if (!is.null(cached) &&
            as.numeric(difftime(Sys.time(), cached$ts, units = "secs")) < .round_cache_ttl_secs) {
          return(cached$payload)
        }
      }
    }
  }

  selected_round <- fetch_latest_completed_round(conn, season = season, round = round)
  if (!nrow(selected_round)) {
    return(NULL)
  }

  season_value <- suppressWarnings(as.integer(selected_round$season[[1]]))
  round_value <- suppressWarnings(as.integer(selected_round$round_number[[1]]))
  competition_phase <- as.character(selected_round$competition_phase[[1]] %||% "")

  cache_key <- paste0(season_value, "_", round_value, "_", competition_phase)
  cached <- .round_summary_cache[[cache_key]]
  if (!is.null(cached) && as.numeric(difftime(Sys.time(), cached$ts, units = "secs")) < .round_cache_ttl_secs) {
    return(cached$payload)
  }

  matches <- fetch_round_matches(conn, season_value, competition_phase, round_value)
  if (!nrow(matches)) {
    return(NULL)
  }

  round_summary <- build_round_match_summary(matches)

  team_points_row <- fetch_team_points_high(
    conn,
    seasons = season_value,
    round = round_value,
    competition_phase = competition_phase,
    ranking = "highest",
    limit = 1L
  )
  player_points_row <- fetch_player_points_high(
    conn,
    seasons = season_value,
    round = round_value,
    competition_phase = competition_phase,
    ranking = "highest",
    limit = 1L
  )
  # --- Batch spotlight queries (replaces ~195 sequential queries with ~14) ---
  PLAYER_BATCH_STATS <- c(
    "goalAssists", "feeds", "gain", "deflections", "intercepts",
    "goals", "goalAttempts", "centrePassReceives", "rebounds",
    "offensiveRebounds", "defensiveRebounds",
    "netPoints", "goal2", "attempts2"
  )
  TEAM_BATCH_HIGHEST <- c(
    "gain", "deflections", "intercepts",
    "goalsFromCentrePass", "goalsFromGain",
    "netPoints", "attempts2"
  )
  TEAM_BATCH_LOWEST <- c("penalties", "generalPlayTurnovers")

  player_rows    <- fetch_player_spotlight_rows(conn, season_value, round_value, competition_phase, PLAYER_BATCH_STATS)
  team_rows_high <- fetch_team_spotlight_rows(conn, season_value, round_value, competition_phase, TEAM_BATCH_HIGHEST, "highest")
  team_rows_low  <- fetch_team_spotlight_rows(conn, season_value, round_value, competition_phase, TEAM_BATCH_LOWEST, "lowest")

  # Season bests (filtered — fast with indexed season column)
  player_season_bests <- fetch_spotlight_bests(conn, "player", PLAYER_BATCH_STATS, season_value, "highest")
  team_season_high    <- fetch_spotlight_bests(conn, "team", TEAM_BATCH_HIGHEST, season_value, "highest")
  team_season_low     <- fetch_spotlight_bests(conn, "team", TEAM_BATCH_LOWEST, season_value, "lowest")

  # Archive bests + ranks combined (single full-scan per subject/ranking)
  non_na <- function(vals) Filter(function(v) !is.null(v) && !is.na(v), vals)
  player_archive <- fetch_spotlight_archive_data(
    conn, "player",
    non_na(setNames(lapply(PLAYER_BATCH_STATS, function(s) extract_first_numeric(player_rows[[s]])), PLAYER_BATCH_STATS)),
    "highest"
  )
  team_archive_h <- fetch_spotlight_archive_data(
    conn, "team",
    non_na(setNames(lapply(TEAM_BATCH_HIGHEST, function(s) extract_first_numeric(team_rows_high[[s]])), TEAM_BATCH_HIGHEST)),
    "highest"
  )
  team_archive_l <- fetch_spotlight_archive_data(
    conn, "team",
    non_na(setNames(lapply(TEAM_BATCH_LOWEST, function(s) extract_first_numeric(team_rows_low[[s]])), TEAM_BATCH_LOWEST)),
    "lowest"
  )

  player_archive_bests <- player_archive$bests
  player_ranks         <- player_archive$ranks
  team_archive_high    <- team_archive_h$bests
  team_ranks_h         <- team_archive_h$ranks
  team_archive_low     <- team_archive_l$bests
  team_ranks_l         <- team_archive_l$ranks

  entry_player <- function(stat, title) {
    row <- player_rows[[stat]]
    if (!length(row) || !nrow(row)) return(NULL)
    val <- extract_first_numeric(row)
    performance_entry_from_row(
      row, title, subject_type = "player", ranking = "highest",
      badges = spotlight_badges(stat, "highest", val, player_season_bests, player_archive_bests),
      historical_rank = if (stat %in% names(player_ranks)) player_ranks[[stat]] else NA_integer_
    )
  }

  entry_team <- function(stat, title, ranking = "highest") {
    rows_src  <- if (identical(ranking, "highest")) team_rows_high else team_rows_low
    s_bests   <- if (identical(ranking, "highest")) team_season_high  else team_season_low
    a_bests   <- if (identical(ranking, "highest")) team_archive_high else team_archive_low
    ranks_src <- if (identical(ranking, "highest")) team_ranks_h else team_ranks_l
    row <- rows_src[[stat]]
    if (!length(row) || !nrow(row)) return(NULL)
    val <- extract_first_numeric(row)
    performance_entry_from_row(
      row, title, subject_type = "team", ranking = ranking,
      badges = spotlight_badges(stat, ranking, val, s_bests, a_bests),
      historical_rank = if (stat %in% names(ranks_src)) ranks_src[[stat]] else NA_integer_
    )
  }

  standout_players <- Filter(Negate(is.null), list(
    performance_entry_from_row(
      player_points_row, "Top score",
      subject_type = "player", ranking = "highest",
      badges = points_record_badges(conn, subject_type = "player", ranking = "highest",
        total_value = extract_first_numeric(player_points_row), season = season_value),
      historical_rank = compute_archive_rank(
        conn, "player", "points", "highest", extract_first_numeric(player_points_row))
    ),
    entry_player("goalAssists",        "Most goal assists"),
    entry_player("feeds",              "Most feeds"),
    entry_player("gain",               "Most gains"),
    entry_player("deflections",        "Most deflections"),
    entry_player("intercepts",         "Most intercepts"),
    entry_player("goals",              "Most goals"),
    entry_player("goalAttempts",       "Most goal attempts"),
    entry_player("centrePassReceives", "Most centre pass receives"),
    entry_player("rebounds",           "Most rebounds"),
    entry_player("offensiveRebounds",  "Most offensive rebounds"),
    entry_player("defensiveRebounds",  "Most defensive rebounds"),
    entry_player("netPoints",          "Most net points"),
    entry_player("goal2",              "Most super shots"),
    entry_player("attempts2",          "Most super shot attempts")
  ))

  standout_teams <- Filter(Negate(is.null), list(
    performance_entry_from_row(
      team_points_row, "Highest team score",
      subject_type = "team", ranking = "highest",
      badges = points_record_badges(conn, subject_type = "team", ranking = "highest",
        total_value = extract_first_numeric(team_points_row), season = season_value),
      historical_rank = compute_archive_rank(
        conn, "team", "points", "highest", extract_first_numeric(team_points_row))
    ),
    entry_team("gain",                 "Most gains"),
    entry_team("deflections",          "Most deflections"),
    entry_team("intercepts",           "Most intercepts"),
    entry_team("penalties",            "Fewest penalties",   "lowest"),
    entry_team("generalPlayTurnovers", "Fewest turnovers",   "lowest"),
    entry_team("goalsFromCentrePass",  "Most goals from centre pass"),
    entry_team("goalsFromGain",        "Most goals from gain"),
    entry_team("netPoints",            "Most net points"),
    entry_team("attempts2",            "Most super shot attempts")
  ))

  biggest_margin_match <- round_summary$biggest_margin_match
  closest_match <- round_summary$closest_match

  # Rehydrate convenience aliases from batch data for notable_facts
  team_turnover_row <- team_rows_low[["generalPlayTurnovers"]]

  notable_facts <- Filter(Negate(is.null), list(
    if (nrow(team_points_row)) {
      build_round_fact(
        "Highest team score",
        sprintf("%s points", format_query_number(extract_first_numeric(team_points_row))),
        sprintf(
          "%s scored %s against %s.",
          team_points_row$squad_name[[1]],
          format_query_number(extract_first_numeric(team_points_row)),
          team_points_row$opponent[[1]]
        ),
        points_record_badges(
          conn,
          subject_type = "team",
          ranking = "highest",
          total_value = extract_first_numeric(team_points_row),
          season = season_value
        )
      )
    },
    if (!is.null(biggest_margin_match)) {
      build_round_fact(
        "Biggest winning margin",
        sprintf("%s points", format_query_number(biggest_margin_match$margin)),
        sprintf(
          "%s beat %s %s-%s.",
          biggest_margin_match$winner_name,
          if (identical(biggest_margin_match$winner_name, biggest_margin_match$home_squad_name)) biggest_margin_match$away_squad_name else biggest_margin_match$home_squad_name,
          format_query_number(if (identical(biggest_margin_match$winner_name, biggest_margin_match$home_squad_name)) biggest_margin_match$home_score else biggest_margin_match$away_score),
          format_query_number(if (identical(biggest_margin_match$winner_name, biggest_margin_match$home_squad_name)) biggest_margin_match$away_score else biggest_margin_match$home_score)
        ),
        margin_record_badges(conn, biggest_margin_match$margin, season_value)
      )
    },
    if (nrow(player_points_row)) {
      build_round_fact(
        "Top individual score",
        sprintf("%s points", format_query_number(extract_first_numeric(player_points_row))),
        sprintf(
          "%s scored %s for %s against %s.",
          player_points_row$player_name[[1]],
          format_query_number(extract_first_numeric(player_points_row)),
          player_points_row$squad_name[[1]],
          player_points_row$opponent[[1]]
        ),
        points_record_badges(
          conn,
          subject_type = "player",
          ranking = "highest",
          total_value = extract_first_numeric(player_points_row),
          season = season_value
        )
      )
    },
    if (nrow(team_turnover_row)) {
      build_round_fact(
        "Cleanest ball security",
        sprintf("%s general play turnovers", format_query_number(extract_first_numeric(team_turnover_row))),
        sprintf(
          "%s kept it to %s against %s.",
          team_turnover_row$squad_name[[1]],
          format_query_number(extract_first_numeric(team_turnover_row)),
          team_turnover_row$opponent[[1]]
        ),
        spotlight_badges("generalPlayTurnovers", "lowest", extract_first_numeric(team_turnover_row), team_season_low, team_archive_low)
      )
    },
    if (!is.null(closest_match)) {
      build_round_fact(
        "Closest finish",
        if (numeric_equal(closest_match$margin, 0)) "Draw" else sprintf("%s-point margin", format_query_number(closest_match$margin)),
        if (numeric_equal(closest_match$margin, 0)) {
          sprintf(
            "%s and %s finished level at %s-%s.",
            closest_match$home_squad_name,
            closest_match$away_squad_name,
            format_query_number(closest_match$home_score),
            format_query_number(closest_match$away_score)
          )
        } else {
          sprintf(
            "%s edged %s %s-%s.",
            closest_match$winner_name,
            if (identical(closest_match$winner_name, closest_match$home_squad_name)) closest_match$away_squad_name else closest_match$home_squad_name,
            format_query_number(if (identical(closest_match$winner_name, closest_match$home_squad_name)) closest_match$home_score else closest_match$away_score),
            format_query_number(if (identical(closest_match$winner_name, closest_match$home_squad_name)) closest_match$away_score else closest_match$home_score)
          )
        }
      )
    }
  ))

  payload <- list(
    season = season_value,
    competition_phase = competition_phase,
    round_number = round_value,
    round_label = format_round_label(competition_phase, round_value),
    round_end_time = normalize_record_value(selected_round$round_end_time[[1]]),
    summary = round_summary,
    matches = rows_to_records(matches),
    standout_players = standout_players,
    standout_teams = standout_teams,
    notable_facts = notable_facts
  )

  .round_summary_cache[[cache_key]] <- list(payload = payload, ts = Sys.time())
  payload
}

fetch_query_result_rows <- function(conn, intent) {
  # Resolve the season filter: specific seasons from the intent, or NULL (no
  # restriction) when the user didn't mention a season. Passing NULL lets the
  # planner do a stat-only index scan instead of an IN list covering every year.
  seasons_filter <- if (!is.null(intent$seasons) && length(intent$seasons)) {
    as.integer(intent$seasons)
  } else if (!is.null(intent$season) && length(intent$season)) {
    as.integer(intent$season)
  } else {
    NULL
  }

  team_query <- identical(intent$subject_type, "team") || identical(intent$subject_type, "teams")
  if (team_query) {
    # Use the pre-aggregated table when available; fall back to period-level aggregation.
    builder <- if (has_team_match_stats(conn)) build_fast_team_match_query else build_team_match_query
    base_query <- builder(
      stat = intent$stat,
      seasons = seasons_filter,
      team_id = intent$team_id,
      opponent_id = intent$opponent_id,
      comparison = intent$comparison,
      threshold = intent$threshold
    )
    tbl_alias <- if (identical(builder, build_fast_team_match_query)) "tms" else "stats"
    order_name_expr <- paste0(tbl_alias, ".squad_name")
  } else {
    # Use the pre-aggregated table when available; fall back to period-level aggregation.
    builder <- if (has_player_match_stats(conn)) build_fast_player_match_query else build_player_match_query
    base_query <- builder(
      stat = intent$stat,
      seasons = seasons_filter,
      player_id = intent$player_id,
      opponent_id = intent$opponent_id,
      comparison = intent$comparison,
      threshold = intent$threshold
    )

    # Alias used in ORDER BY differs between the two tables.
    tbl_alias <- if (identical(builder, build_fast_player_match_query)) "pms" else "stats"
    order_name_expr <- "players.canonical_name"
  }

  # For highest/lowest intents we only ever display 1 row. Push ORDER BY + LIMIT
  # into SQL so the database returns one row instead of the full match history.
  if (identical(intent$intent_type, "highest") || identical(intent$intent_type, "lowest")) {
    order_dir <- if (identical(intent$intent_type, "lowest")) "ASC" else "DESC"
      limited_query <- paste0(
        base_query$query,
        " ORDER BY total_value ", order_dir,
        ", ", tbl_alias, ".season DESC, ", tbl_alias, ".round_number DESC, ", order_name_expr, " ASC",
        " LIMIT 1"
      )
      return(query_rows(conn, limited_query, base_query$params))
  }

  # For list intents push ORDER BY + LIMIT into SQL so we only transfer the
  # rows the caller will actually display, not the full match history.
  if (identical(intent$intent_type, "list")) {
    list_limit <- min(intent$limit %||% 25L, 25L)
    limited_query <- paste0(
      base_query$query,
      " ORDER BY total_value DESC",
      ", ", tbl_alias, ".season DESC, ", tbl_alias, ".round_number DESC, ", order_name_expr, " ASC",
      " LIMIT ", list_limit
    )
    return(sort_query_result_rows(
      query_rows(conn, limited_query, base_query$params),
      "list"
    ))
  }

  # For count intents we need all matching rows to compute total_matches, but
  # cap at 2000 to guard against unbounded scans. No single player has more
  # than ~1000 matches in the dataset.
  sort_query_result_rows(
    query_rows(conn, paste0(base_query$query, " LIMIT 2000"), base_query$params),
    intent$intent_type
  )
}

build_home_venue_impact_base_query <- function(seasons = NULL, team_id = NULL, venue_name = NULL, include_penalties = TRUE) {
  if (isTRUE(include_penalties)) {
    home_penalties_for_sql <- "COALESCE(home_pen.match_value, 0) AS penalties_for,"
    home_penalties_against_sql <- "COALESCE(away_pen.match_value, 0) AS penalties_against,"
    home_penalty_advantage_sql <- "COALESCE(away_pen.match_value, 0) - COALESCE(home_pen.match_value, 0) AS penalty_advantage"
    away_penalties_for_sql <- "COALESCE(away_pen.match_value, 0) AS penalties_for,"
    away_penalties_against_sql <- "COALESCE(home_pen.match_value, 0) AS penalties_against,"
    away_penalty_advantage_sql <- "COALESCE(home_pen.match_value, 0) - COALESCE(away_pen.match_value, 0) AS penalty_advantage"
    penalty_join_sql <- c(
      "LEFT JOIN team_match_stats home_pen",
      "  ON home_pen.match_id = matches.match_id",
      "  AND home_pen.squad_id = matches.home_squad_id",
      "  AND home_pen.stat = 'penalties'",
      "LEFT JOIN team_match_stats away_pen",
      "  ON away_pen.match_id = matches.match_id",
      "  AND away_pen.squad_id = matches.away_squad_id",
      "  AND away_pen.stat = 'penalties'"
    )
  } else {
    home_penalties_for_sql <- "NULL AS penalties_for,"
    home_penalties_against_sql <- "NULL AS penalties_against,"
    home_penalty_advantage_sql <- "NULL AS penalty_advantage"
    away_penalties_for_sql <- "NULL AS penalties_for,"
    away_penalties_against_sql <- "NULL AS penalties_against,"
    away_penalty_advantage_sql <- "NULL AS penalty_advantage"
    penalty_join_sql <- character()
  }

  match_filter_query <- "WHERE matches.home_score IS NOT NULL AND matches.away_score IS NOT NULL"
  params <- list()

  season_filter <- append_integer_in_filter(match_filter_query, params, "matches.season", seasons, "season")
  match_filter_query <- season_filter$query
  params <- season_filter$params

  if (!is.null(venue_name)) {
    match_filter_query <- paste0(match_filter_query, " AND matches.venue_name = ?venue_name")
    params$venue_name <- as.character(venue_name)
  }

  query <- paste(c(
    "SELECT * FROM (",
    "SELECT matches.match_id, matches.season, COALESCE(matches.competition_phase, '') AS competition_phase,",
    "  matches.round_number, matches.venue_name,",
    "  matches.home_squad_id AS team_id, matches.home_squad_name AS team_name,",
    "  matches.away_squad_id AS opponent_id, matches.away_squad_name AS opponent_name,",
    "  1 AS is_home,",
    "  matches.home_score AS team_score, matches.away_score AS opponent_score,",
    "  matches.home_score - matches.away_score AS margin,",
    "  CASE WHEN matches.home_score > matches.away_score THEN 1 ELSE 0 END AS won,",
    "  CASE WHEN matches.home_score = matches.away_score THEN 1 ELSE 0 END AS draw,",
    paste0("  ", home_penalties_for_sql),
    paste0("  ", home_penalties_against_sql),
    paste0("  ", home_penalty_advantage_sql),
    "FROM matches",
    penalty_join_sql,
    match_filter_query,
    "UNION ALL",
    "SELECT matches.match_id, matches.season, COALESCE(matches.competition_phase, '') AS competition_phase,",
    "  matches.round_number, matches.venue_name,",
    "  matches.away_squad_id AS team_id, matches.away_squad_name AS team_name,",
    "  matches.home_squad_id AS opponent_id, matches.home_squad_name AS opponent_name,",
    "  0 AS is_home,",
    "  matches.away_score AS team_score, matches.home_score AS opponent_score,",
    "  matches.away_score - matches.home_score AS margin,",
    "  CASE WHEN matches.away_score > matches.home_score THEN 1 ELSE 0 END AS won,",
    "  CASE WHEN matches.home_score = matches.away_score THEN 1 ELSE 0 END AS draw,",
    paste0("  ", away_penalties_for_sql),
    paste0("  ", away_penalties_against_sql),
    paste0("  ", away_penalty_advantage_sql),
    "FROM matches",
    penalty_join_sql,
    match_filter_query,
    ") AS impact_rows",
    "WHERE 1 = 1"
  ), collapse = " ")

  if (!is.null(team_id)) {
    query <- paste0(query, " AND team_id = ?team_id")
    params$team_id <- as.integer(team_id)
  }

  list(query = query, params = params)
}

build_home_venue_impact_rows_query <- function(seasons = NULL, team_id = NULL, venue_name = NULL) {
  query <- paste(
    "SELECT match_id, season, competition_phase, round_number, venue_name,",
    "team_id, team_name, opponent_id, opponent_name, is_home,",
    "team_score, opponent_score, margin, won, draw,",
    "penalties_for, penalties_against, penalty_advantage",
    "FROM home_venue_impact_rows",
    "WHERE 1 = 1"
  )
  params <- list()

  season_filter <- append_integer_in_filter(query, params, "season", seasons, "season")
  query <- season_filter$query
  params <- season_filter$params

  if (!is.null(team_id)) {
    query <- paste0(query, " AND team_id = ?team_id")
    params$team_id <- as.integer(team_id)
  }

  if (!is.null(venue_name)) {
    query <- paste0(query, " AND venue_name = ?venue_name")
    params$venue_name <- as.character(venue_name)
  }

  list(query = query, params = params)
}

build_home_venue_breakdown_rows_query <- function(seasons = NULL, team_id = NULL, venue_name = NULL) {
  query <- paste(
    "SELECT match_id, season, competition_phase, round_number, venue_name,",
    "team_id, team_name, opponent_id, opponent_name,",
    "team_score, opponent_score, margin, won, draw,",
    "generalplayturnovers AS \"generalPlayTurnovers\",",
    "turnoverheld AS \"turnoverHeld\",",
    "contactpenalties AS \"contactPenalties\",",
    "obstructionpenalties AS \"obstructionPenalties\",",
    "penalties",
    "FROM home_venue_breakdown_rows",
    "WHERE 1 = 1"
  )
  params <- list()

  season_filter <- append_integer_in_filter(query, params, "season", seasons, "season")
  query <- season_filter$query
  params <- season_filter$params

  if (!is.null(team_id)) {
    query <- paste0(query, " AND team_id = ?team_id")
    params$team_id <- as.integer(team_id)
  }

  if (!is.null(venue_name)) {
    query <- paste0(query, " AND venue_name = ?venue_name")
    params$venue_name <- as.character(venue_name)
  }

  list(query = query, params = params)
}

empty_home_venue_impact_summary <- function() {
  list(
    league_summary = NULL,
    team_summary = data.frame(),
    venue_summary = data.frame(),
    team_venue_summary = data.frame()
  )
}

rate_or_na <- function(numerator, denominator, digits = 3L) {
  if (is.null(denominator) || is.na(denominator) || denominator <= 0) {
    return(NA_real_)
  }

  round(as.numeric(numerator) / as.numeric(denominator), digits)
}

mean_or_na <- function(values, digits = 2L) {
  numeric_values <- suppressWarnings(as.numeric(values))
  if (!length(numeric_values) || all(is.na(numeric_values))) {
    return(NA_real_)
  }

  round(mean(numeric_values, na.rm = TRUE), digits)
}

home_venue_group_metrics <- function(rows) {
  list(
    matches = nrow(rows),
    wins = sum(as.integer(rows$won), na.rm = TRUE),
    win_rate = rate_or_na(sum(as.integer(rows$won), na.rm = TRUE), nrow(rows)),
    avg_margin = mean_or_na(rows$margin),
    avg_penalties_for = mean_or_na(rows$penalties_for),
    avg_penalties_against = mean_or_na(rows$penalties_against),
    avg_penalty_advantage = mean_or_na(rows$penalty_advantage)
  )
}

summarise_home_venue_impact_rows <- function(rows, min_matches = 5L, limit = 50L) {
  if (!nrow(rows)) {
    return(empty_home_venue_impact_summary())
  }

  rows$is_home <- as.integer(rows$is_home)
  rows$won <- as.integer(rows$won)
  rows$draw <- as.integer(rows$draw)
  numeric_cols <- c(
    "match_id", "season", "round_number", "team_id", "opponent_id",
    "team_score", "opponent_score", "margin",
    "penalties_for", "penalties_against", "penalty_advantage"
  )
  for (column_name in numeric_cols) {
    rows[[column_name]] <- suppressWarnings(as.numeric(rows[[column_name]]))
  }
  rows$team_name <- as.character(rows$team_name)
  rows$venue_name <- as.character(rows$venue_name)

  home_rows <- rows[rows$is_home == 1L, , drop = FALSE]
  away_rows <- rows[rows$is_home == 0L, , drop = FALSE]

  home_metrics <- home_venue_group_metrics(home_rows)
  away_metrics <- home_venue_group_metrics(away_rows)
  league_summary <- list(
    matches = as.integer(length(unique(rows$match_id))),
    home_wins = as.integer(home_metrics$wins),
    away_wins = as.integer(away_metrics$wins),
    draws = as.integer(length(unique(rows$match_id[rows$draw == 1L]))),
    home_win_rate = home_metrics$win_rate,
    away_win_rate = away_metrics$win_rate,
    avg_home_margin = home_metrics$avg_margin,
    avg_away_margin = away_metrics$avg_margin,
    avg_home_penalties_for = home_metrics$avg_penalties_for,
    avg_home_penalties_against = home_metrics$avg_penalties_against,
    avg_home_penalty_advantage = home_metrics$avg_penalty_advantage
  )

  team_ids <- sort(unique(rows$team_id))
  team_summary_rows <- lapply(team_ids, function(team_id_value) {
    team_rows <- rows[rows$team_id == team_id_value, , drop = FALSE]
    team_home_rows <- team_rows[team_rows$is_home == 1L, , drop = FALSE]
    team_away_rows <- team_rows[team_rows$is_home == 0L, , drop = FALSE]
    if (nrow(team_home_rows) < min_matches || nrow(team_away_rows) < min_matches) {
      return(NULL)
    }

    home_values <- home_venue_group_metrics(team_home_rows)
    away_values <- home_venue_group_metrics(team_away_rows)
    data.frame(
      team_id = as.integer(team_id_value),
      team_name = team_rows$team_name[[1]],
      home_matches = as.integer(home_values$matches),
      away_matches = as.integer(away_values$matches),
      home_wins = as.integer(home_values$wins),
      away_wins = as.integer(away_values$wins),
      home_win_rate = home_values$win_rate,
      away_win_rate = away_values$win_rate,
      win_rate_delta_home_vs_away = round(home_values$win_rate - away_values$win_rate, 3),
      home_avg_margin = home_values$avg_margin,
      away_avg_margin = away_values$avg_margin,
      margin_delta_home_vs_away = round(home_values$avg_margin - away_values$avg_margin, 2),
      home_avg_penalties_for = home_values$avg_penalties_for,
      home_avg_penalties_against = home_values$avg_penalties_against,
      home_avg_penalty_advantage = home_values$avg_penalty_advantage,
      away_avg_penalties_for = away_values$avg_penalties_for,
      away_avg_penalties_against = away_values$avg_penalties_against,
      away_avg_penalty_advantage = away_values$avg_penalty_advantage,
      penalty_delta_home_vs_away = round(home_values$avg_penalty_advantage - away_values$avg_penalty_advantage, 2),
      stringsAsFactors = FALSE
    )
  })
  team_summary <- do.call(rbind, Filter(Negate(is.null), team_summary_rows))
  if (is.null(team_summary)) {
    team_summary <- data.frame()
  } else {
    team_summary <- team_summary[order(-team_summary$margin_delta_home_vs_away, team_summary$team_name), , drop = FALSE]
    team_summary <- utils::head(team_summary, limit)
    row.names(team_summary) <- NULL
  }

  venues <- sort(unique(home_rows$venue_name))
  venue_summary_rows <- lapply(venues, function(venue_name_value) {
    venue_rows <- home_rows[home_rows$venue_name == venue_name_value, , drop = FALSE]
    if (nrow(venue_rows) < min_matches) {
      return(NULL)
    }

    venue_values <- home_venue_group_metrics(venue_rows)
    data.frame(
      venue_name = venue_name_value,
      matches = as.integer(venue_values$matches),
      home_wins = as.integer(venue_values$wins),
      home_win_rate = venue_values$win_rate,
      avg_home_margin = venue_values$avg_margin,
      avg_home_penalties_for = venue_values$avg_penalties_for,
      avg_home_penalties_against = venue_values$avg_penalties_against,
      avg_home_penalty_advantage = venue_values$avg_penalty_advantage,
      win_rate_lift_vs_league_home = round(venue_values$win_rate - home_metrics$win_rate, 3),
      margin_lift_vs_league_home = round(venue_values$avg_margin - home_metrics$avg_margin, 2),
      penalty_lift_vs_league_home = round(venue_values$avg_penalty_advantage - home_metrics$avg_penalty_advantage, 2),
      stringsAsFactors = FALSE
    )
  })
  venue_summary <- do.call(rbind, Filter(Negate(is.null), venue_summary_rows))
  if (is.null(venue_summary)) {
    venue_summary <- data.frame()
  } else {
    venue_summary <- venue_summary[order(-venue_summary$margin_lift_vs_league_home, venue_summary$venue_name), , drop = FALSE]
    venue_summary <- utils::head(venue_summary, limit)
    row.names(venue_summary) <- NULL
  }

  home_keys <- unique(home_rows[, c("team_id", "team_name", "venue_name"), drop = FALSE])
  team_venue_summary_rows <- lapply(seq_len(nrow(home_keys)), function(index) {
    key_row <- home_keys[index, , drop = FALSE]
    team_home_venue_rows <- home_rows[
      home_rows$team_id == key_row$team_id &
      home_rows$venue_name == key_row$venue_name,
      ,
      drop = FALSE
    ]
    if (nrow(team_home_venue_rows) < min_matches) {
      return(NULL)
    }

    team_home_other_rows <- home_rows[
      home_rows$team_id == key_row$team_id &
      home_rows$venue_name != key_row$venue_name,
      ,
      drop = FALSE
    ]
    venue_values <- home_venue_group_metrics(team_home_venue_rows)
    other_matches <- nrow(team_home_other_rows)

    if (other_matches > 0L) {
      other_values <- home_venue_group_metrics(team_home_other_rows)
      comparison_matches <- as.integer(other_matches)
      other_win_rate <- other_values$win_rate
      other_avg_margin <- other_values$avg_margin
      other_avg_penalty_advantage <- other_values$avg_penalty_advantage
      win_rate_lift <- round(venue_values$win_rate - other_values$win_rate, 3)
      margin_lift <- round(venue_values$avg_margin - other_values$avg_margin, 2)
      penalty_lift <- round(venue_values$avg_penalty_advantage - other_values$avg_penalty_advantage, 2)
    } else {
      comparison_matches <- NA_integer_
      other_win_rate <- NA_real_
      other_avg_margin <- NA_real_
      other_avg_penalty_advantage <- NA_real_
      win_rate_lift <- NA_real_
      margin_lift <- NA_real_
      penalty_lift <- NA_real_
    }

    data.frame(
      team_id = as.integer(key_row$team_id),
      team_name = as.character(key_row$team_name),
      venue_name = as.character(key_row$venue_name),
      matches = as.integer(venue_values$matches),
      home_wins = as.integer(venue_values$wins),
      home_win_rate = venue_values$win_rate,
      avg_home_margin = venue_values$avg_margin,
      avg_home_penalties_for = venue_values$avg_penalties_for,
      avg_home_penalties_against = venue_values$avg_penalties_against,
      avg_home_penalty_advantage = venue_values$avg_penalty_advantage,
      comparison_matches_other_home_venues = comparison_matches,
      other_home_venues_win_rate = other_win_rate,
      other_home_venues_avg_margin = other_avg_margin,
      other_home_venues_avg_penalty_advantage = other_avg_penalty_advantage,
      win_rate_lift_vs_team_other_home_venues = win_rate_lift,
      margin_lift_vs_team_other_home_venues = margin_lift,
      penalty_lift_vs_team_other_home_venues = penalty_lift,
      stringsAsFactors = FALSE
    )
  })
  team_venue_summary <- do.call(rbind, Filter(Negate(is.null), team_venue_summary_rows))
  if (is.null(team_venue_summary)) {
    team_venue_summary <- data.frame()
  } else {
    team_venue_summary <- team_venue_summary[
      order(
        is.na(team_venue_summary$margin_lift_vs_team_other_home_venues),
        -team_venue_summary$margin_lift_vs_team_other_home_venues,
        team_venue_summary$team_name,
        team_venue_summary$venue_name,
        na.last = TRUE
      ),
      ,
      drop = FALSE
    ]
    team_venue_summary <- utils::head(team_venue_summary, limit)
    row.names(team_venue_summary) <- NULL
  }

  list(
    league_summary = league_summary,
    team_summary = team_summary,
    venue_summary = venue_summary,
    team_venue_summary = team_venue_summary
  )
}

fetch_home_venue_impact_summary <- function(conn, seasons = NULL, team_id = NULL, venue_name = NULL, min_matches = 5L, limit = 50L) {
  if (has_home_venue_impact_rows(conn)) {
    base_query <- build_home_venue_impact_rows_query(
      seasons = seasons,
      team_id = team_id,
      venue_name = venue_name
    )
  } else {
    include_penalties <- has_team_match_stats(conn)
    if (!include_penalties) {
      api_log("WARN", "home_venue_impact_no_team_match_stats",
              error_message = "home-venue-impact is running without team_match_stats; penalty metrics will be null.")
    }

    base_query <- build_home_venue_impact_base_query(
      seasons = seasons,
      team_id = team_id,
      venue_name = venue_name,
      include_penalties = include_penalties
    )
  }
  rows <- query_rows(conn, base_query$query, base_query$params)
  summarise_home_venue_impact_rows(rows, min_matches = min_matches, limit = limit)
}

build_home_edge_stat_groups <- function() {
  list(
    generalPlayTurnovers = list(
      stat_group = "generalPlayTurnovers",
      stat_key = "generalPlayTurnovers",
      stat_label = "General Play Turnovers",
      preferred_direction = "lower"
    ),
    heldBalls = list(
      stat_group = "heldBalls",
      stat_key = "turnoverHeld",
      stat_label = "Held Balls",
      preferred_direction = "lower"
    ),
    contactPenalties = list(
      stat_group = "contactPenalties",
      stat_key = "contactPenalties",
      stat_label = "Contacts",
      preferred_direction = "lower"
    ),
    obstructionPenalties = list(
      stat_group = "obstructionPenalties",
      stat_key = "obstructionPenalties",
      stat_label = "Obstructions",
      preferred_direction = "lower"
    ),
    penalties = list(
      stat_group = "penalties",
      stat_key = "penalties",
      stat_label = "Penalties",
      preferred_direction = "lower"
    )
  )
}

normalize_home_edge_stat_groups <- function(stat_groups = NULL) {
  catalog <- build_home_edge_stat_groups()
  requested_groups <- stat_groups

  if (is.list(requested_groups) && !is.null(requested_groups$requested_stat_groups)) {
    requested_groups <- requested_groups$requested_stat_groups
  }

  if (is.null(requested_groups) || !length(requested_groups)) {
    requested_groups <- names(catalog)
  } else if (length(requested_groups) == 1L && is.character(requested_groups) && grepl(",", requested_groups[[1]], fixed = TRUE)) {
    requested_groups <- strsplit(requested_groups[[1]], ",", fixed = TRUE)[[1]]
  }

  requested_groups <- trimws(as.character(unlist(requested_groups, use.names = FALSE)))
  requested_groups <- requested_groups[nzchar(requested_groups)]
  if (!length(requested_groups)) {
    requested_groups <- names(catalog)
  }

  normalized_groups <- unique(vapply(requested_groups, function(group_name) {
    group_name <- as.character(group_name)[[1]]
    if (!group_name %in% names(catalog)) {
      stop("Unsupported home edge stat group: ", group_name, ".", call. = FALSE)
    }
    group_name
  }, character(1)))

  resolved <- catalog[normalized_groups]
  requested_stat_keys <- vapply(resolved, function(group) group$stat_key, character(1))
  requested_stat_labels <- vapply(resolved, function(group) group$stat_label, character(1))

  list(
    requested_stat_groups = normalized_groups,
    requested_stat_keys = requested_stat_keys,
    requested_stat_labels = requested_stat_labels,
    available_stat_groups = normalized_groups,
    unavailable_stat_groups = character(0),
    catalog = catalog,
    resolved = resolved
  )
}

home_edge_stat_rows_empty <- function() {
  data.frame(
    stat_group = character(),
    stat_key = character(),
    stat_label = character(),
    matches = integer(),
    venue_average = numeric(),
    baseline_average = numeric(),
    lift = numeric(),
    preferred_direction = character(),
    stringsAsFactors = FALSE
  )
}

home_edge_opposition_overall_empty <- function() {
  data.frame(
    opponent_id = integer(),
    opponent_name = character(),
    matches = integer(),
    home_win_rate = numeric(),
    baseline_home_win_rate = numeric(),
    home_win_rate_lift = numeric(),
    avg_margin = numeric(),
    baseline_avg_margin = numeric(),
    margin_lift = numeric(),
    avg_penalties = numeric(),
    baseline_avg_penalties = numeric(),
    penalties_lift = numeric(),
    stringsAsFactors = FALSE
  )
}

home_edge_opposition_by_stat_empty <- function() {
  data.frame(
    opponent_id = integer(),
    opponent_name = character(),
    stat_group = character(),
    stat_key = character(),
    stat_label = character(),
    matches = integer(),
    venue_average = numeric(),
    baseline_average = numeric(),
    lift = numeric(),
    preferred_direction = character(),
    stringsAsFactors = FALSE
  )
}

home_edge_team_venue_stat_empty <- function() {
  data.frame(
    team_id = integer(),
    team_name = character(),
    venue_name = character(),
    stat_group = character(),
    stat_key = character(),
    stat_label = character(),
    matches = integer(),
    venue_average = numeric(),
    other_home_venues_average = numeric(),
    lift = numeric(),
    preferred_direction = character(),
    stringsAsFactors = FALSE
  )
}

home_edge_prepare_rows <- function(rows, stat_keys = character()) {
  if (!nrow(rows)) {
    return(rows)
  }

  integer_columns <- c("match_id", "season", "round_number", "team_id", "opponent_id", "team_score", "opponent_score", "margin", "won", "draw")
  numeric_columns <- unique(c(stat_keys, "penalties"))

  for (column_name in intersect(integer_columns, names(rows))) {
    rows[[column_name]] <- suppressWarnings(as.integer(rows[[column_name]]))
  }
  for (column_name in intersect(numeric_columns, names(rows))) {
    rows[[column_name]] <- suppressWarnings(as.numeric(rows[[column_name]]))
  }

  for (column_name in intersect(c("venue_name", "team_name", "opponent_name", "competition_phase"), names(rows))) {
    rows[[column_name]] <- as.character(rows[[column_name]])
  }

  rows
}

home_edge_stat_metric <- function(rows, column_name) {
  if (!nrow(rows) || !(column_name %in% names(rows))) {
    return(list(matches = 0L, average = NA_real_))
  }

  values <- suppressWarnings(as.numeric(rows[[column_name]]))
  list(matches = as.integer(nrow(rows)), average = mean_or_na(values))
}

build_home_edge_breakdown_base_query <- function(seasons = NULL, team_id = NULL, venue_name = NULL, stat_groups = NULL, use_match_stats = TRUE) {
  normalized <- normalize_home_edge_stat_groups(stat_groups)
  stat_keys <- unique(c(normalized$requested_stat_keys, "penalties"))
  stat_sql <- safe_stat_in_sql(stat_keys)
  stat_aliases <- vapply(stat_keys, function(stat_key) sprintf("MAX(CASE WHEN stats.stat = '%s' THEN stats.stat_value END) AS \"%s\"", stat_key, stat_key), character(1))
  stats_source_params <- list()

  if (isTRUE(use_match_stats)) {
    stats_source <- paste(
      "SELECT tms.match_id, tms.squad_id, tms.stat, tms.match_value AS stat_value",
      "FROM team_match_stats AS tms",
      "WHERE tms.stat IN (", stat_sql, ")"
    )
    stats_season_filter <- append_integer_in_filter(stats_source, stats_source_params, "tms.season", seasons, "stats_season")
    stats_source <- stats_season_filter$query
    stats_source_params <- stats_season_filter$params
    if (!is.null(team_id)) {
      stats_source <- paste0(stats_source, " AND tms.squad_id = ?stats_team_id")
      stats_source_params$stats_team_id <- as.integer(team_id)
    }
  } else {
    stats_source <- paste(
      "SELECT tps.match_id, tps.squad_id, tps.stat, ROUND(CAST(SUM(tps.value_number) AS numeric), 2) AS stat_value",
      "FROM team_period_stats AS tps",
      "WHERE tps.stat IN (", stat_sql, ")"
    )
    stats_season_filter <- append_integer_in_filter(stats_source, stats_source_params, "tps.season", seasons, "stats_season")
    stats_source <- stats_season_filter$query
    stats_source_params <- stats_season_filter$params
    if (!is.null(team_id)) {
      stats_source <- paste0(stats_source, " AND tps.squad_id = ?stats_team_id")
      stats_source_params$stats_team_id <- as.integer(team_id)
    }
    stats_source <- paste(
      stats_source,
      "GROUP BY tps.match_id, tps.squad_id, tps.stat"
    )
  }

  query <- paste(c(
    "SELECT",
    "  matches.match_id, matches.season, COALESCE(matches.competition_phase, '') AS competition_phase,",
    "  matches.round_number, matches.venue_name,",
    "  matches.home_squad_id AS team_id, matches.home_squad_name AS team_name,",
    "  matches.away_squad_id AS opponent_id, matches.away_squad_name AS opponent_name,",
    "  matches.home_score AS team_score, matches.away_score AS opponent_score,",
    "  matches.home_score - matches.away_score AS margin,",
    "  CASE WHEN matches.home_score > matches.away_score THEN 1 ELSE 0 END AS won,",
    "  CASE WHEN matches.home_score = matches.away_score THEN 1 ELSE 0 END AS draw,",
    paste0("  ", paste(stat_aliases, collapse = ",\n  ")),
    "FROM matches",
    "LEFT JOIN (",
    stats_source,
    ") AS stats",
    "  ON stats.match_id = matches.match_id",
    "  AND stats.squad_id = matches.home_squad_id",
    "WHERE matches.home_score IS NOT NULL AND matches.away_score IS NOT NULL"
  ), collapse = " ")

  params <- stats_source_params
  season_filter <- append_integer_in_filter(query, params, "matches.season", seasons, "season")
  query <- season_filter$query
  params <- season_filter$params

  if (!is.null(team_id)) {
    query <- paste0(query, " AND matches.home_squad_id = ?team_id")
    params$team_id <- as.integer(team_id)
  }
  if (!is.null(venue_name)) {
    query <- paste0(query, " AND matches.venue_name = ?venue_name")
    params$venue_name <- as.character(venue_name)
  }

  query <- paste0(
    query,
    " GROUP BY matches.match_id, matches.season, matches.competition_phase, matches.round_number, matches.venue_name,",
    " matches.home_squad_id, matches.home_squad_name, matches.away_squad_id, matches.away_squad_name,",
    " matches.home_score, matches.away_score, matches.home_score - matches.away_score"
  )

  list(query = query, params = params)
}

summarise_home_edge_stat_rows <- function(rows, baseline_rows = rows, stat_groups = NULL, min_matches = 5L, limit = 50L) {
  normalized <- normalize_home_edge_stat_groups(stat_groups)
  if (!nrow(rows)) {
    return(home_edge_stat_rows_empty())
  }

  rows <- home_edge_prepare_rows(rows, normalized$requested_stat_keys)
  baseline_rows <- home_edge_prepare_rows(baseline_rows, normalized$requested_stat_keys)
  if (nrow(rows) < min_matches) {
    return(home_edge_stat_rows_empty())
  }

  summary_rows <- lapply(seq_along(normalized$requested_stat_groups), function(index) {
    group_name <- normalized$requested_stat_groups[[index]]
    group <- normalized$resolved[[group_name]]
    selected <- home_edge_stat_metric(rows, group$stat_key)
    baseline <- home_edge_stat_metric(baseline_rows, group$stat_key)
    data.frame(
      stat_group = group$stat_group,
      stat_key = group$stat_key,
      stat_label = group$stat_label,
      matches = as.integer(selected$matches),
      venue_average = selected$average,
      baseline_average = baseline$average,
      lift = if (is.na(selected$average) || is.na(baseline$average)) NA_real_ else round(selected$average - baseline$average, 3),
      preferred_direction = group$preferred_direction,
      stringsAsFactors = FALSE
    )
  })

  result <- do.call(rbind, summary_rows)
  if (is.null(result)) {
    return(home_edge_stat_rows_empty())
  }
  result <- result[order(result$stat_group), , drop = FALSE]
  result <- utils::head(result, limit)
  row.names(result) <- NULL
  result
}

summarise_home_edge_opposition_overall <- function(rows, baseline_rows = rows, min_matches = 5L, limit = 50L) {
  if (!nrow(rows)) {
    return(home_edge_opposition_overall_empty())
  }

  rows <- home_edge_prepare_rows(rows, c("penalties"))
  baseline_rows <- home_edge_prepare_rows(baseline_rows, c("penalties"))
  if (nrow(rows) < min_matches) {
    return(home_edge_opposition_overall_empty())
  }

  baseline_win_rate <- rate_or_na(sum(baseline_rows$won, na.rm = TRUE), nrow(baseline_rows))
  baseline_margin <- mean_or_na(baseline_rows$margin)
  baseline_penalties <- mean_or_na(baseline_rows$penalties)

  opponent_ids <- sort(unique(rows$opponent_id))
  summary_rows <- lapply(opponent_ids, function(opponent_id_value) {
    opponent_rows <- rows[rows$opponent_id == opponent_id_value, , drop = FALSE]
    if (nrow(opponent_rows) < min_matches) {
      return(NULL)
    }

    data.frame(
      opponent_id = as.integer(opponent_id_value),
      opponent_name = opponent_rows$opponent_name[[1]],
      matches = as.integer(nrow(opponent_rows)),
      home_win_rate = rate_or_na(sum(opponent_rows$won, na.rm = TRUE), nrow(opponent_rows)),
      baseline_home_win_rate = baseline_win_rate,
      home_win_rate_lift = if (is.na(baseline_win_rate)) NA_real_ else round(rate_or_na(sum(opponent_rows$won, na.rm = TRUE), nrow(opponent_rows)) - baseline_win_rate, 3),
      avg_margin = mean_or_na(opponent_rows$margin),
      baseline_avg_margin = baseline_margin,
      margin_lift = if (is.na(baseline_margin)) NA_real_ else round(mean_or_na(opponent_rows$margin) - baseline_margin, 3),
      avg_penalties = mean_or_na(opponent_rows$penalties),
      baseline_avg_penalties = baseline_penalties,
      penalties_lift = if (is.na(baseline_penalties)) NA_real_ else round(mean_or_na(opponent_rows$penalties) - baseline_penalties, 3),
      stringsAsFactors = FALSE
    )
  })

  result <- do.call(rbind, Filter(Negate(is.null), summary_rows))
  if (is.null(result)) {
    return(home_edge_opposition_overall_empty())
  }
  result <- result[order(is.na(result$margin_lift), -abs(result$margin_lift), result$opponent_name, na.last = TRUE), , drop = FALSE]
  result <- utils::head(result, limit)
  row.names(result) <- NULL
  result
}

summarise_home_edge_opposition_by_stat <- function(rows, baseline_rows = rows, stat_groups = NULL, min_matches = 5L, limit = 50L) {
  normalized <- normalize_home_edge_stat_groups(stat_groups)
  if (!nrow(rows)) {
    return(home_edge_opposition_by_stat_empty())
  }

  rows <- home_edge_prepare_rows(rows, normalized$requested_stat_keys)
  baseline_rows <- home_edge_prepare_rows(baseline_rows, normalized$requested_stat_keys)
  if (nrow(rows) < min_matches) {
    return(home_edge_opposition_by_stat_empty())
  }

  summary_rows <- lapply(seq_along(normalized$requested_stat_groups), function(index) {
    group_name <- normalized$requested_stat_groups[[index]]
    group <- normalized$resolved[[group_name]]
    baseline_metric <- home_edge_stat_metric(baseline_rows, group$stat_key)
    opponent_ids <- sort(unique(rows$opponent_id))
    lapply(opponent_ids, function(opponent_id_value) {
      opponent_rows <- rows[rows$opponent_id == opponent_id_value, , drop = FALSE]
      selected_metric <- home_edge_stat_metric(opponent_rows, group$stat_key)
      if (selected_metric$matches < min_matches) {
        return(NULL)
      }

      data.frame(
        opponent_id = as.integer(opponent_id_value),
        opponent_name = opponent_rows$opponent_name[[1]],
        stat_group = group$stat_group,
        stat_key = group$stat_key,
        stat_label = group$stat_label,
        matches = as.integer(selected_metric$matches),
        venue_average = selected_metric$average,
        baseline_average = baseline_metric$average,
        lift = if (is.na(selected_metric$average) || is.na(baseline_metric$average)) NA_real_ else round(selected_metric$average - baseline_metric$average, 3),
        preferred_direction = group$preferred_direction,
        stringsAsFactors = FALSE
      )
    })
  })

  result_rows <- list()
  for (group_result in summary_rows) {
    result_rows <- c(result_rows, Filter(Negate(is.null), group_result))
  }
  result <- if (length(result_rows)) do.call(rbind, result_rows) else NULL
  if (is.null(result)) {
    return(home_edge_opposition_by_stat_empty())
  }
  result <- result[order(result$stat_group, result$opponent_name), , drop = FALSE]
  result <- utils::head(result, limit)
  row.names(result) <- NULL
  result
}

summarise_home_edge_team_venue_stats <- function(rows, baseline_rows = rows, stat_groups = NULL, team_id = NULL, min_matches = 5L, limit = 50L) {
  normalized <- normalize_home_edge_stat_groups(stat_groups)
  if (is.null(team_id) || !nrow(rows)) {
    return(home_edge_team_venue_stat_empty())
  }

  rows <- home_edge_prepare_rows(rows, normalized$requested_stat_keys)
  baseline_rows <- home_edge_prepare_rows(baseline_rows, normalized$requested_stat_keys)
  rows <- rows[rows$team_id == as.integer(team_id), , drop = FALSE]
  baseline_rows <- baseline_rows[baseline_rows$team_id == as.integer(team_id), , drop = FALSE]
  if (!nrow(rows) || !nrow(baseline_rows)) {
    return(home_edge_team_venue_stat_empty())
  }

  venue_names <- sort(unique(rows$venue_name))
  summary_rows <- lapply(venue_names, function(venue_name_value) {
    venue_rows <- rows[rows$venue_name == venue_name_value, , drop = FALSE]
    other_rows <- baseline_rows[baseline_rows$venue_name != venue_name_value, , drop = FALSE]
    if (nrow(venue_rows) < min_matches || !nrow(other_rows)) {
      return(NULL)
    }

    venue_team_name <- venue_rows$team_name[[1]]
    lapply(seq_along(normalized$requested_stat_groups), function(index) {
      group_name <- normalized$requested_stat_groups[[index]]
      group <- normalized$resolved[[group_name]]
      venue_metric <- home_edge_stat_metric(venue_rows, group$stat_key)
      other_metric <- home_edge_stat_metric(other_rows, group$stat_key)
      data.frame(
        team_id = as.integer(team_id),
        team_name = venue_team_name,
        venue_name = venue_name_value,
        stat_group = group$stat_group,
        stat_key = group$stat_key,
        stat_label = group$stat_label,
        matches = as.integer(venue_metric$matches),
        venue_average = venue_metric$average,
        other_home_venues_average = other_metric$average,
        lift = if (is.na(venue_metric$average) || is.na(other_metric$average)) NA_real_ else round(venue_metric$average - other_metric$average, 3),
        preferred_direction = group$preferred_direction,
        stringsAsFactors = FALSE
      )
    })
  })

  result_rows <- list()
  for (venue_result in summary_rows) {
    result_rows <- c(result_rows, Filter(Negate(is.null), venue_result))
  }
  result <- if (length(result_rows)) do.call(rbind, result_rows) else NULL
  if (is.null(result)) {
    return(home_edge_team_venue_stat_empty())
  }
  result <- result[order(result$venue_name, result$stat_group), , drop = FALSE]
  result <- utils::head(result, limit)
  row.names(result) <- NULL
  result
}

empty_home_venue_breakdown_summary <- function(filters = list()) {
  list(
    filters = filters,
    stat_summary = home_edge_stat_rows_empty(),
    opposition_summary_overall = home_edge_opposition_overall_empty(),
    opposition_summary_by_stat = home_edge_opposition_by_stat_empty(),
    team_venue_stat_summary = home_edge_team_venue_stat_empty()
  )
}

fetch_home_venue_breakdown <- function(conn, seasons = NULL, team_id = NULL, venue_name = NULL, stat_groups = NULL, min_matches = 5L, limit = 50L) {
  bounded_limit <- suppressWarnings(as.integer(limit %||% 50L))
  if (is.na(bounded_limit) || bounded_limit < 1L) {
    bounded_limit <- 1L
  }
  bounded_limit <- min(bounded_limit, 50L)
  normalized <- normalize_home_edge_stat_groups(stat_groups)

  if (has_home_venue_breakdown_rows(conn)) {
    selected_query <- build_home_venue_breakdown_rows_query(
      seasons = seasons,
      team_id = team_id,
      venue_name = venue_name
    )
  } else {
    use_match_stats <- has_team_match_stats(conn)
    selected_query <- build_home_edge_breakdown_base_query(
      seasons = seasons,
      team_id = team_id,
      venue_name = venue_name,
      stat_groups = normalized,
      use_match_stats = use_match_stats
    )
  }
  selected_rows <- query_rows(conn, selected_query$query, selected_query$params)
  selected_rows <- home_edge_prepare_rows(selected_rows, normalized$requested_stat_keys)

  baseline_rows <- if (!is.null(venue_name) || !is.null(team_id)) {
    baseline_query <- if (has_home_venue_breakdown_rows(conn)) {
      build_home_venue_breakdown_rows_query(
        seasons = seasons,
        team_id = team_id,
        venue_name = NULL
      )
    } else {
      build_home_edge_breakdown_base_query(
        seasons = seasons,
        team_id = team_id,
        venue_name = NULL,
        stat_groups = normalized,
        use_match_stats = has_team_match_stats(conn)
      )
    }
    query_rows(conn, baseline_query$query, baseline_query$params)
  } else {
    selected_rows
  }
  baseline_rows <- home_edge_prepare_rows(baseline_rows, normalized$requested_stat_keys)

  list(
    filters = list(
      seasons = if (!is.null(seasons)) as.integer(seasons) else NULL,
      team_id = if (!is.null(team_id)) as.integer(team_id) else NULL,
      venue_name = if (!is.null(venue_name)) as.character(venue_name) else NULL,
      requested_stat_groups = normalized$requested_stat_groups,
      requested_stat_keys = normalized$requested_stat_keys,
      available_stat_groups = normalized$available_stat_groups,
      unavailable_stat_groups = normalized$unavailable_stat_groups,
      min_matches = as.integer(min_matches),
      limit = as.integer(bounded_limit)
    ),
    stat_summary = summarise_home_edge_stat_rows(
      selected_rows,
      baseline_rows = baseline_rows,
      stat_groups = normalized,
      min_matches = min_matches,
      limit = bounded_limit
    ),
    opposition_summary_overall = summarise_home_edge_opposition_overall(
      selected_rows,
      baseline_rows = baseline_rows,
      min_matches = min_matches,
      limit = bounded_limit
    ),
    opposition_summary_by_stat = summarise_home_edge_opposition_by_stat(
      selected_rows,
      baseline_rows = baseline_rows,
      stat_groups = normalized,
      min_matches = min_matches,
      limit = bounded_limit
    ),
    team_venue_stat_summary = summarise_home_edge_team_venue_stats(
      selected_rows,
      baseline_rows = baseline_rows,
      stat_groups = normalized,
      team_id = team_id,
      min_matches = min_matches,
      limit = bounded_limit
    )
  )
}

# Netball Wins Above Replacement (nWAR) constants.
#
# Scoring is based on the 2025 Fantasy Netball Blog scoring system:
#   https://fantasynetballblog.wordpress.com/2025/03/18/2025-fn-scoring-system/
# This replaces the old Champion Data netPoints metric, which was unavailable
# in early seasons (2017) and had calibration issues with replacement levels.
#
# NWAR_POINTS_PER_WIN: fantasy points per estimated win.
# Calibration target: elite player earns ~6–8 nWAR per full season;
# solid starter earns ~2–3 nWAR; fringe qualifier earns ~0.5–1 nWAR.
# Derived empirically: (Jhaniele avg_fs − shooter_repl) × 16 games / 7 target
# = (155.31 − 22.58) × 16 / 7 ≈ 303 → rounded to 300.
NWAR_POINTS_PER_WIN      <- 300.0
# NWAR_REPLACEMENT_PERCENTILE: bottom fraction of qualified players used to
# define the replacement-level baseline (e.g. 0.15 = bottom 15%).
NWAR_REPLACEMENT_PERCENTILE <- 0.15
# NWAR_STAT_KEYS: the exact set of player_match_stats.stat values consumed by
# fantasy scoring. Used as a literal IN filter in build_nwar_query() so that
# the aggregate only scans the relevant rows — roughly 16 of the ~50+ stat
# types stored in player_match_stats — reducing scan width by ~70%.
NWAR_STAT_KEYS <- c(
  "goal1", "goal2", "goals",
  "offensiveRebounds", "defensiveRebounds",
  "feeds", "centrePassReceives", "secondPhaseReceive",
  "gain", "intercepts", "deflections", "pickups",
  "goalMisses", "generalPlayTurnovers", "penalties",
  "quartersPlayed"
)

# Builds the SQL query and parameter list for the nWAR stat aggregate.
# Returns a list(query, params) ready to pass to query_rows(), or NULL when
# only period-level stats exist.
#
# Position resolution is intentionally absent from this query. It is handled
# by fetch_nwar_positions(), which runs a separate lightweight GROUP BY on
# player_match_positions and is merged in R inside fetch_nwar_rows(). Keeping
# the two concerns separate lets this aggregate stay cheap:
#   • Only NWAR_STAT_KEYS rows are scanned (stat IN literal filter).
#   • No JOIN to player_match_positions (removes the ordered-set MODE() aggregate
#     from an already-wide conditional-SUM scan).
build_nwar_query <- function(conn, seasons, team_id, min_games) {
  if (!has_player_match_stats(conn)) return(NULL)

  seasons_filter <- if (!is.null(seasons) && length(seasons)) as.integer(seasons) else NULL

  # Use player_match_participation to count only games where the player actually
  # played >= 1 minute. The INNER JOIN also gates all stat SUM columns so bench
  # appearances (minutesPlayed = 0) cannot contribute to the nWAR calculation.
  has_participation <- has_player_match_participation(conn)
  participation_join <- if (has_participation) {
    "INNER JOIN player_match_participation pmpart ON pmpart.player_id = stats.player_id AND pmpart.match_id = stats.match_id"
  } else ""
  games_played_expr <- if (has_participation) "pmpart.match_id" else "stats.match_id"

  # Literal IN filter over the 16 stat keys used by fantasy scoring. Inlining
  # as a string constant (not parameterised) lets the query planner see the
  # exact key set and exploit the stat-leading indexes on player_match_stats.
  stat_in_sql <- paste0(
    "stats.stat IN (",
    paste(sprintf("'%s'", NWAR_STAT_KEYS), collapse = ", "),
    ")"
  )

  query <- paste(
    # MAX(squad_name) is used because a player who transferred mid-season can
    # appear under multiple squad names. The MAX picks one name arbitrarily
    # (alphabetical); this is display-only and does not affect nWAR calculations.
    "SELECT stats.player_id, players.canonical_name AS player_name, MAX(stats.squad_name) AS squad_name,",
    "COUNT(DISTINCT stats.season) AS seasons_played,",
    paste0("COUNT(DISTINCT ", games_played_expr, ") AS games_played,"),
    "SUM(CASE WHEN stats.stat = 'goal1' THEN stats.match_value ELSE 0 END) AS total_goal1,",
    "SUM(CASE WHEN stats.stat = 'goal2' THEN stats.match_value ELSE 0 END) AS total_goal2,",
    "SUM(CASE WHEN stats.stat = 'goals' THEN stats.match_value ELSE 0 END) AS total_goals_legacy,",
    "MAX(CASE WHEN stats.stat = 'goal1' THEN 1 ELSE 0 END) AS has_goal1_data,",
    "SUM(CASE WHEN stats.stat = 'offensiveRebounds' THEN stats.match_value ELSE 0 END) AS total_off_reb,",
    "SUM(CASE WHEN stats.stat = 'defensiveRebounds' THEN stats.match_value ELSE 0 END) AS total_def_reb,",
    "SUM(CASE WHEN stats.stat = 'feeds' THEN stats.match_value ELSE 0 END) AS total_feeds,",
    "SUM(CASE WHEN stats.stat = 'centrePassReceives' THEN stats.match_value ELSE 0 END) AS total_cpr,",
    "SUM(CASE WHEN stats.stat = 'secondPhaseReceive' THEN stats.match_value ELSE 0 END) AS total_spr,",
    "SUM(CASE WHEN stats.stat = 'gain' THEN stats.match_value ELSE 0 END) AS total_gain,",
    "SUM(CASE WHEN stats.stat = 'intercepts' THEN stats.match_value ELSE 0 END) AS total_intercepts,",
    "SUM(CASE WHEN stats.stat = 'deflections' THEN stats.match_value ELSE 0 END) AS total_deflections,",
    "SUM(CASE WHEN stats.stat = 'pickups' THEN stats.match_value ELSE 0 END) AS total_pickups,",
    "SUM(CASE WHEN stats.stat = 'goalMisses' THEN stats.match_value ELSE 0 END) AS total_missed_goals,",
    "SUM(CASE WHEN stats.stat = 'generalPlayTurnovers' THEN stats.match_value ELSE 0 END) AS total_gpto,",
    "SUM(CASE WHEN stats.stat = 'penalties' THEN stats.match_value ELSE 0 END) AS total_penalties,",
    "SUM(CASE WHEN stats.stat = 'quartersPlayed' THEN stats.match_value ELSE 0 END) AS total_quarters",
    "FROM player_match_stats AS stats",
    "INNER JOIN players ON players.player_id = stats.player_id",
    participation_join,
    paste("WHERE", stat_in_sql)
  )

  filters <- apply_stat_filters(
    query,
    list(),
    seasons = seasons_filter,
    team_id = team_id,
    round_number = NULL,
    table_alias = "stats"
  )
  filters$query <- paste0(
    filters$query,
    " GROUP BY stats.player_id, players.canonical_name",
    paste0(" HAVING COUNT(DISTINCT ", games_played_expr, ") >= ?min_games")
  )
  filters$params$min_games <- as.integer(min_games)
  filters
}

# Fetches each player's dominant position code from player_match_positions.
#
# Runs as a separate lightweight query (one GROUP BY on the small pre-built
# position table) and is merged in R by fetch_nwar_rows(). Keeping position
# resolution here — instead of inside the stat aggregate — avoids a JOIN and
# a MODE() WITHIN GROUP ordered-set aggregate on an already-wide scan.
#
# Two-level resolution in a single SQL pass:
#   1. Per-filter MODE: the CASE WHEN expression returns starting_position_code
#      only for matches that satisfy the active season and team_id filters, so
#      MODE picks the dominant field position within that filtered match set.
#      This preserves the same scoping semantics as the pre-refactor query which
#      computed position from the same JOIN-filtered rows as the stat aggregate.
#   2. All-time fallback via COALESCE: when the per-filter MODE is NULL (player
#      has no valid position records in the filtered scope), the outer MODE across
#      all seasons/teams provides the fallback, still excluding invalid markers.
# When both seasons_filter and team_id are NULL the COALESCE is omitted and only
# the all-time MODE is computed.
#
# Returns a data.frame(player_id, position_code). Called by fetch_nwar_rows().
fetch_nwar_positions <- function(conn, seasons_filter, team_id = NULL) {
  params <- list()
  has_filter <- (!is.null(seasons_filter) && length(seasons_filter) > 0L) ||
                (!is.null(team_id))

  if (has_filter) {
    # Build the CASE WHEN condition for the per-filter branch. Both clauses are
    # AND-combined when both filters are active.
    filter_parts <- character(0)

    if (!is.null(seasons_filter) && length(seasons_filter) > 0L) {
      phs <- character(length(seasons_filter))
      for (i in seq_along(seasons_filter)) {
        key <- sprintf("pos_season_%d", i)
        phs[[i]] <- paste0("?", key)
        params[[key]] <- seasons_filter[[i]]
      }
      filter_parts <- c(filter_parts, sprintf("season IN (%s)", paste(phs, collapse = ", ")))
    }

    if (!is.null(team_id)) {
      filter_parts <- c(filter_parts, "squad_id = ?pos_team_id")
      params[["pos_team_id"]] <- as.integer(team_id)
    }

    filter_expr <- paste(filter_parts, collapse = " AND ")
    pos_col <- paste(
      "COALESCE(",
      sprintf("  MODE() WITHIN GROUP (ORDER BY CASE WHEN %s", filter_expr),
      "    THEN starting_position_code END),",
      "  MODE() WITHIN GROUP (ORDER BY starting_position_code)",
      ") AS position_code"
    )
  } else {
    # No filters: compute the all-time dominant position directly.
    pos_col <- "MODE() WITHIN GROUP (ORDER BY starting_position_code) AS position_code"
  }

  query <- paste(
    "SELECT player_id,",
    pos_col,
    "FROM player_match_positions",
    "WHERE starting_position_code IS NOT NULL",
    "  AND starting_position_code NOT IN ('I', 'S', '-')",
    "GROUP BY player_id"
  )
  query_rows(conn, query, params)
}

# Calculates Netball Wins Above Replacement (nWAR) for all qualified players.
#
# Scoring uses the 2025 Fantasy Netball Blog system (court time + attack +
# defence − errors) instead of Champion Data's netPoints, so rankings are
# meaningful across all seasons including those predating netPoints.
#
# Steps:
#   1. Aggregate each player's per-match stats via conditional SQL SUM.
#      Only NWAR_STAT_KEYS rows are scanned (stat IN literal filter), cutting
#      the player_match_stats scan to the ~16 relevant stat types.
#   2. Restrict to players with at least min_games qualifying matches.
#   3. Compute fantasy score in R from component stat totals.
#      CPR multiplier is position-specific: GD/WD = 3 pts each, others = 0.5.
#      Court time = games × 10 + quarters_played × 5.
#   4. If player_match_positions exists, resolve each qualifying player's dominant
#      position via fetch_nwar_positions() — a separate lightweight GROUP BY
#      on the small pre-built position table, merged in R by player_id.
#      Without position data a single global replacement level is used.
#   5. Map players to position groups (Shooter / Midcourt / Defender) and
#      compute a per-group replacement level = mean avg fantasy score of the
#      bottom NWAR_REPLACEMENT_PERCENTILE of that group (global fallback for
#      groups with fewer than 2 valid players).
#   6. Compute FPAR/game = avg_fantasy_score - replacement_level.
#   7. Compute nWAR = FPAR/game × games_played / NWAR_POINTS_PER_WIN.
#   8. When no season filter is applied, also compute nWAR/season and rank the
#      all-seasons leaderboard by that normalized value so longer careers do
#      not dominate purely on accumulated volume.
fetch_nwar_rows <- function(conn, seasons = NULL, team_id = NULL, min_games = 5L, limit = 50L, position_group = NULL) {
  filters <- build_nwar_query(conn, seasons, team_id, min_games)

  empty_frame <- data.frame(
    player_id         = integer(0),
    player_name       = character(0),
    squad_name        = character(0),
    seasons_played    = integer(0),
    games_played      = integer(0),
    total_fantasy_score = numeric(0),
    avg_fantasy_score = numeric(0),
    position_code     = character(0),
    position_group    = character(0),
    replacement_level = numeric(0),
    npar              = numeric(0),
    nwar_per_season   = numeric(0),
    nwar              = numeric(0),
    stringsAsFactors  = FALSE
  )

  if (is.null(filters)) {
    api_log("WARN", "nwar_no_match_stats",
            error_message = "Fantasy nWAR requires player_match_stats table; returning empty result.")
    return(empty_frame)
  }

  all_rows <- query_rows(conn, filters$query, filters$params)

  if (nrow(all_rows) == 0L) return(empty_frame)

  games <- as.integer(all_rows$games_played)
  seasons_played <- if ("seasons_played" %in% names(all_rows)) {
    pmax(1L, as.integer(all_rows$seasons_played))
  } else {
    rep.int(1L, nrow(all_rows))
  }

  # Resolve dominant position code via the separate lightweight position query
  # (fetch_nwar_positions). This runs a single GROUP BY on player_match_positions
  # — a small pre-computed table — and is merged here by player_id. Players not
  # found in the position result (no valid position records) get NA.
  seasons_filter <- if (!is.null(seasons) && length(seasons)) as.integer(seasons) else NULL
  has_positions  <- has_player_match_positions(conn)
  pos_code <- if (has_positions) {
    pos_df <- fetch_nwar_positions(conn, seasons_filter, team_id = team_id)
    as.character(pos_df$position_code[match(all_rows$player_id, pos_df$player_id)])
  } else {
    rep(NA_character_, nrow(all_rows))
  }
  pos_group <- position_group_from_code(pos_code)

  # CPR multiplier: GD/WD receive rare centre passes worth 3 pts each;
  # all other positions get 0.5 pts per CPR (1 per 2).
  cpr_mult <- ifelse(!is.na(pos_code) & pos_code %in% c("GD", "WD"), 3.0, 0.5)

  # Court time: 10 pts per game on court + 5 pts per quarter played.
  # quartersPlayed stat may be absent in very early seasons; fall back to
  # assuming a full 4-quarter game so court time is not zeroed out.
  total_quarters <- as.numeric(all_rows$total_quarters)
  total_quarters <- ifelse(
    total_quarters == 0 & games > 0L,
    as.numeric(games) * 4.0,
    total_quarters
  )
  court_time_pts <- as.numeric(games) * 10.0 + total_quarters * 5.0

  fantasy_score <-
    court_time_pts +
    # For 2020+ seasons use goal1 (1-pt) and goal2 (2-pt super shots).
    # For pre-2020 seasons (ANZ Championship, Super Netball 2017-2019) only
    # the legacy 'goals' stat exists; treat each goal as 2 pts.
    ifelse(
      as.integer(all_rows$has_goal1_data) == 1L,
      as.numeric(all_rows$total_goal1) * 2.0 +
        as.numeric(all_rows$total_goal2) * 6.0,
      as.numeric(all_rows$total_goals_legacy) * 2.0
    ) +
    as.numeric(all_rows$total_off_reb)      *  4.0 +
    as.numeric(all_rows$total_feeds)        *  2.0 +
    as.numeric(all_rows$total_cpr)          * cpr_mult +
    as.numeric(all_rows$total_spr)          *  1.0 +
    as.numeric(all_rows$total_gain)         *  6.0 +
    as.numeric(all_rows$total_intercepts)   *  8.0 +
    as.numeric(all_rows$total_deflections)  *  6.0 +
    as.numeric(all_rows$total_def_reb)      *  4.0 +
    as.numeric(all_rows$total_pickups)      *  6.0 +
    as.numeric(all_rows$total_missed_goals) * -4.0 +
    # generalPlayTurnovers is a composite of all turnover types (bad passes,
    # bad hands, intercepted passes, etc.) — applying -4 once covers all of them.
    # Do NOT also add individual turnover-type penalties here.
    as.numeric(all_rows$total_gpto)         * -4.0 +
    as.numeric(all_rows$total_penalties)    * -0.5

  avg_fs <- round(fantasy_score / pmax(as.numeric(games), 1L), 2)
  n_valid <- sum(!is.na(avg_fs))

  if (n_valid == 0L) {
    api_log("WARN", "nwar_no_valid_avg",
            error_message = "All avg_fantasy_score values are NA after computation; cannot compute replacement level.")
    stop("Unable to compute replacement level: no valid average fantasy scores.", call. = FALSE)
  }

  # Compute global replacement level (fallback and reference).
  n_repl_global <- max(1L, ceiling(n_valid * NWAR_REPLACEMENT_PERCENTILE))
  repl_global   <- round(mean(head(sort(avg_fs, na.last = TRUE), n_repl_global), na.rm = TRUE), 2)

  # Compute per-position-group replacement levels when position data is present.
  # Groups with fewer than 2 valid players fall back to the global level to avoid
  # replacement levels driven by a single outlier.
  has_position_data <- any(!is.na(pos_code))
  if (has_position_data) {
    groups <- unique(pos_group[!is.na(pos_group)])
    repl_by_group <- vapply(groups, function(g) {
      grp_avg   <- avg_fs[pos_group == g & !is.na(pos_group)]
      grp_valid <- grp_avg[!is.na(grp_avg)]
      if (length(grp_valid) < 2L) return(repl_global)
      n_r <- max(1L, ceiling(length(grp_valid) * NWAR_REPLACEMENT_PERCENTILE))
      round(mean(head(sort(grp_valid, na.last = TRUE), n_r), na.rm = TRUE), 2)
    }, numeric(1L))
    names(repl_by_group) <- groups
    repl_by_player <- repl_by_group[pos_group]
    repl_by_player[is.na(repl_by_player)] <- repl_global
  } else {
    repl_by_player <- rep(repl_global, nrow(all_rows))
  }

  npar <- round(avg_fs - repl_by_player, 2)
  nwar <- round(npar * as.numeric(games) / NWAR_POINTS_PER_WIN, 2)
  nwar_per_season <- round(nwar / pmax(as.numeric(seasons_played), 1), 2)

  all_rows$seasons_played       <- seasons_played
  all_rows$games_played         <- games
  all_rows$total_fantasy_score  <- round(fantasy_score, 2)
  all_rows$avg_fantasy_score    <- avg_fs
  all_rows$position_code        <- pos_code
  all_rows$position_group       <- pos_group
  all_rows$replacement_level    <- repl_by_player
  all_rows$npar                 <- npar
  all_rows$nwar_per_season      <- nwar_per_season
  all_rows$nwar                 <- nwar

  # Drop intermediate stat columns — only retain the computed summary fields.
  keep_cols <- c("player_id", "player_name", "squad_name", "seasons_played", "games_played",
                 "total_fantasy_score", "avg_fantasy_score",
                 "position_code", "position_group", "replacement_level",
                 "npar", "nwar_per_season", "nwar")
  all_rows <- all_rows[, intersect(keep_cols, names(all_rows)), drop = FALSE]

  if (!is.null(position_group)) {
    all_rows <- all_rows[all_rows$position_group == position_group, , drop = FALSE]
    if (nrow(all_rows) == 0L) {
      return(empty_frame)
    }
  }

  ranking_metric <- if (is.null(seasons) || !length(seasons)) all_rows$nwar_per_season else all_rows$nwar
  all_rows <- all_rows[order(-ranking_metric, -all_rows$nwar, all_rows$player_name, na.last = TRUE), , drop = FALSE]
  rownames(all_rows) <- NULL
  head(all_rows, as.integer(limit))
}
