repo_root <- function() {
  getOption(
    "netballstats.repo_root",
    normalizePath(file.path(getwd()), mustWork = FALSE)
  )
}

DEFAULT_TEAM_STATS <- c(
  "attempts1", "attempts2", "badHands", "badPasses", "blocked", "blocks", "breaks",
  "centrePassReceives", "contactPenalties", "defensiveRebounds", "deflections",
  "disposals", "feeds", "gain", "generalPlayTurnovers", "goal1", "goal2",
  "goalAssists", "goalAttempts", "goalMisses", "goals", "goalsFromCentrePass",
  "goalsFromGain", "goalsFromTurnovers", "intercepts", "netPoints",
  "obstructionPenalties", "offensiveRebounds", "offsides", "passes", "penalties",
  "pickups", "possessions", "rebounds", "timeInPossession", "tossUpWin",
  "turnovers", "unforcedTurnovers"
)

DEFAULT_PLAYER_STATS <- c(
  "attempts1", "attempts2", "badHands", "badPasses", "blocked", "blocks", "breaks",
  "centrePassReceives", "contactPenalties", "defensiveRebounds", "deflections",
  "disposals", "feeds", "gain", "generalPlayTurnovers", "goal1", "goal2",
  "goalAssists", "goalAttempts", "goalMisses", "goals", "intercepts",
  "minutesPlayed", "missedGoalTurnover", "netPoints", "obstructionPenalties",
  "offensiveRebounds", "offsides", "passes", "penalties", "pickups", "possessions",
  "quartersPlayed", "rebounds", "tossUpWin", "turnovers", "unforcedTurnovers"
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
  "Which players scored 40+ goals in 2025?"
)

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
  if (grepl("^(which players|list players|show players|who)\\b", text)) {
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
  alias_rows
}

QUERY_STAT_ALIASES <- build_query_stat_alias_rows()

resolve_query_stat <- function(text) {
  matched <- logical(nrow(QUERY_STAT_ALIASES))
  for (index in seq_len(nrow(QUERY_STAT_ALIASES))) {
    alias <- QUERY_STAT_ALIASES$alias[[index]]
    pattern <- paste0("\\b", gsub(" ", "\\\\s+", escape_regex(alias), fixed = TRUE), "\\b")
    matched[[index]] <- grepl(pattern, text, perl = TRUE)
  }

  candidates <- QUERY_STAT_ALIASES[matched, , drop = FALSE]
  if (!nrow(candidates)) {
    return(NULL)
  }

  unique(as.character(candidates$stat))[[1]]
}

team_alias_lookup <- function(conn) {
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
  normalized_question <- normalize_player_search_name(question)
  if (!nzchar(normalized_question)) {
    return(NULL)
  }

  alias_lookup <- query_rows(
    conn,
    paste(
      "SELECT player_aliases.player_id, player_aliases.alias_name, player_aliases.alias_search_name,",
      "players.canonical_name",
      "FROM player_aliases",
      "INNER JOIN players ON players.player_id = player_aliases.player_id",
      "ORDER BY players.canonical_name ASC"
    )
  )
  players <- query_rows(
    conn,
    "SELECT player_id, canonical_name, short_display_name FROM players ORDER BY canonical_name ASC"
  )

  derived_rows <- lapply(seq_len(nrow(players)), function(index) {
    player <- players[index, , drop = FALSE]
    tokens <- unlist(strsplit(as.character(player$canonical_name), "[^A-Za-z0-9]+"))
    tokens <- tokens[nzchar(tokens)]
    first_token <- if (length(tokens)) tokens[[1]] else ""
    last_token <- if (length(tokens)) tokens[[length(tokens)]] else ""
    aliases <- unique(c(
      as.character(player$canonical_name),
      as.character(player$short_display_name),
      first_token,
      last_token
    ))
    aliases <- aliases[nzchar(aliases)]

    data.frame(
      player_id = rep(player$player_id[[1]], length(aliases)),
      alias_name = aliases,
      alias_search_name = normalize_player_search_name(aliases),
      canonical_name = rep(as.character(player$canonical_name[[1]]), length(aliases)),
      stringsAsFactors = FALSE
    )
  })

  lookup <- unique(rbind(alias_lookup, do.call(rbind, derived_rows)))
  lookup <- lookup[nchar(lookup$alias_search_name) >= 3L, , drop = FALSE]
  if (!nrow(lookup)) {
    return(query_error_payload("unsupported", question, "No player lookup data is available."))
  }

  matched <- lookup[
    nzchar(lookup$alias_search_name) &
      vapply(
        lookup$alias_search_name,
        grepl,
        logical(1),
        x = normalized_question,
        fixed = TRUE
      ),
    ,
    drop = FALSE
  ]

  if (!nrow(matched)) {
    return(query_error_payload(
      "unsupported",
      question,
      "I couldn't match a player name in that question."
    ))
  }

  alias_lengths <- nchar(matched$alias_search_name)
  longest <- max(alias_lengths)
  matched <- matched[alias_lengths == longest, , drop = FALSE]
  player_ids <- unique(matched$player_id)
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
  season_text <- extract_first_capture(normalized_text, "\\b(?:in|during)\\s+(20[0-9]{2})\\b")
  season <- if (is.null(season_text)) NULL else as.integer(season_text)
  opponent_phrase <- extract_first_capture(
    normalized_text,
    "\\bagainst\\s+(.+?)(?:\\s+(?:in|during)\\s+20[0-9]{2}\\b|$)"
  )
  opponent <- resolve_query_team(conn, opponent_phrase)
  if (is.list(opponent) && !is.null(opponent$status) && !identical(opponent$status, "supported")) {
    opponent$question <- parsed_question
    return(opponent)
  }

  plural_list_query <- identical(intent_type, "list") &&
    grepl("^(which players|list players|show players|who)\\b", normalized_text)

  player <- if (plural_list_query) {
    NULL
  } else {
    resolve_query_player(conn, parsed_question)
  }
  if (is.list(player) && !is.null(player$status) && !identical(player$status, "supported")) {
    player$question <- parsed_question
    return(player)
  }

  subject_type <- if (plural_list_query) "players" else "player"
  if (!identical(subject_type, "players") && is.null(player)) {
    return(query_error_payload(
      "unsupported",
      parsed_question,
      "I couldn't identify which player you want to ask about."
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
      is.null(threshold) && is.null(opponent) && is.null(season)) {
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
    player_id = player$player_id %||% NULL,
    player_name = player$player_name %||% NULL,
    stat = stat,
    stat_label = query_stat_label(stat),
    comparison = threshold$comparison %||% NULL,
    comparison_label = if (!is.null(threshold$comparison)) query_comparison_label(threshold$comparison) else NULL,
    threshold = threshold$threshold %||% NULL,
    opponent_id = opponent$squad_id %||% NULL,
    opponent_name = opponent$squad_name %||% NULL,
    season = season,
    limit = limit
  )
}

build_player_match_query <- function(stat, seasons = NULL, player_id = NULL, opponent_id = NULL, comparison = NULL, threshold = NULL) {
  query <- paste(
    "SELECT stats.player_id, players.canonical_name AS player_name, stats.squad_name,",
    "MAX(CASE WHEN matches.home_squad_id = stats.squad_id THEN matches.away_squad_name ELSE matches.home_squad_name END) AS opponent,",
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
      " AND (CASE WHEN matches.home_squad_id = stats.squad_id THEN matches.away_squad_id ELSE matches.home_squad_id END) = ?opponent_id"
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

query_filter_suffix <- function(intent) {
  suffix <- character()
  if (!is.null(intent$opponent_name)) {
    suffix <- c(suffix, paste("against", intent$opponent_name))
  }
  if (!is.null(intent$season)) {
    suffix <- c(suffix, paste("in", intent$season))
  }

  if (!length(suffix)) {
    return("")
  }

  paste0(" ", paste(suffix, collapse = " "))
}

build_query_answer <- function(intent, rows, total_matches) {
  stat_label <- tolower(query_stat_label(intent$stat))
  subject <- intent$player_name %||% "Players"
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
      "%s's highest %s%s was %s%s",
      subject,
      stat_label,
      filter_suffix,
      format_query_number(first_row$total_value[[1]]),
      performance_suffix
    ))
  }

  if (identical(intent$intent_type, "lowest")) {
    return(sprintf(
      "%s's lowest %s%s was %s%s",
      subject,
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
  rows$player_name <- as.character(rows$player_name)

  order_index <- if (identical(intent_type, "lowest")) {
    order(
      rows$total_value,
      -rows$season,
      -rows$round_number,
      rows$player_name,
      na.last = TRUE
    )
  } else {
    order(
      -rows$total_value,
      -rows$season,
      -rows$round_number,
      rows$player_name,
      na.last = TRUE
    )
  }

  rows[order_index, , drop = FALSE]
}

fetch_query_result_rows <- function(conn, intent) {
  seasons_to_query <- if (!is.null(intent$season)) {
    c(as.integer(intent$season))
  } else {
    available_match_seasons(conn)
  }

  rows_by_season <- lapply(seasons_to_query, function(season_value) {
    base_query <- build_player_match_query(
      stat = intent$stat,
      seasons = c(as.integer(season_value)),
      player_id = intent$player_id,
      opponent_id = intent$opponent_id,
      comparison = intent$comparison,
      threshold = intent$threshold
    )
    query_rows(conn, base_query$query, base_query$params)
  })

  sort_query_result_rows(bind_query_result_rows(rows_by_season), intent$intent_type)
}
