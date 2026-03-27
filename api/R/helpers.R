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
  "Which players scored 40+ goals in 2025?",
  "How many times have the Swifts scored 70 goals or more against the Vixens?",
  "Which teams scored 70+ goals in 2025?"
)

open_db <- function() {
  open_database_connection()
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

validate_sql_identifier <- function(value, name = "identifier") {
  if (!grepl("^[A-Za-z][A-Za-z0-9_]*$", value)) {
    stop(name, " must start with a letter and contain only letters, digits, and underscores.", call. = FALSE)
  }
}

available_stats <- function(conn, table_name) {
  validate_sql_identifier(table_name, "table_name")
  query_rows(
    conn,
    sprintf(
      "SELECT DISTINCT stat FROM %s WHERE value_number IS NOT NULL ORDER BY stat",
      table_name
    )
  )$stat
}

validate_stat <- function(conn, table_name, stat, default_stat = "points") {
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
  normalized_phrase <- normalize_player_search_name(question)
  if (!nzchar(normalized_phrase)) {
    return(NULL)
  }

  direct_lookup <- query_rows(
    conn,
    paste(
      "SELECT DISTINCT players.player_id, player_aliases.alias_name, player_aliases.alias_search_name,",
      "players.canonical_name",
      "FROM players",
      "LEFT JOIN player_aliases ON players.player_id = player_aliases.player_id",
      "WHERE players.search_name LIKE ?search OR player_aliases.alias_search_name LIKE ?search",
      "ORDER BY players.canonical_name ASC"
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

# Returns TRUE when player_match_stats is available in the connected database.
# The table is created by build_database.R; older DB builds won't have it.
has_player_match_stats <- function(conn) {
  isTRUE(tryCatch(
    DBI::dbExistsTable(conn, "player_match_stats"),
    error = function(e) FALSE
  ))
}

# Faster alternative to build_player_match_query that reads from the
# player_match_stats pre-aggregated table (one row per player per match per
# stat) instead of player_period_stats (one row per player per period per
# stat).  No GROUP BY required; threshold comparisons become WHERE clauses
# instead of HAVING, so the stat+value index can be used directly.
build_fast_player_match_query <- function(stat, seasons = NULL, player_id = NULL, opponent_id = NULL, comparison = NULL, threshold = NULL) {
  query <- paste(
    "SELECT pms.player_id, players.canonical_name AS player_name, pms.squad_name,",
    "CASE WHEN matches.home_squad_id = pms.squad_id THEN matches.away_squad_name ELSE matches.home_squad_name END AS opponent,",
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
      " AND (CASE WHEN matches.home_squad_id = pms.squad_id THEN matches.away_squad_id ELSE matches.home_squad_id END) = ?opponent_id"
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
    "MAX(CASE WHEN matches.home_squad_id = stats.squad_id THEN matches.away_squad_name ELSE matches.home_squad_name END) AS opponent,",
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
      " AND (CASE WHEN matches.home_squad_id = stats.squad_id THEN matches.away_squad_id ELSE matches.home_squad_id END) = ?opponent_id"
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

  query <- paste(
    "SELECT stats.player_id, players.canonical_name AS player_name, MAX(stats.squad_name) AS squad_name,",
    paste0("?stat AS stat, ROUND(CAST(SUM(stats.", value_col, ") AS numeric), 2) AS total_value,"),
    "COUNT(DISTINCT stats.match_id) AS matches_played,",
    paste0("ROUND(CAST(SUM(stats.", value_col, ") AS numeric) / NULLIF(COUNT(DISTINCT stats.match_id), 0), 2) AS average_value"),
    paste0("FROM ", stats_table, " AS stats"),
    "INNER JOIN players ON players.player_id = stats.player_id",
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

  query <- paste(
    "SELECT stats.player_id, players.canonical_name AS player_name, MAX(stats.squad_name) AS squad_name,",
    paste0("stats.season, ?stat AS stat, ROUND(CAST(SUM(stats.", value_col, ") AS numeric), 2) AS total_value,"),
    "COUNT(DISTINCT stats.match_id) AS matches_played,",
    paste0("ROUND(CAST(SUM(stats.", value_col, ") AS numeric) / NULLIF(COUNT(DISTINCT stats.match_id), 0), 2) AS average_value"),
    paste0("FROM ", stats_table, " AS stats"),
    "INNER JOIN players ON players.player_id = stats.player_id",
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

fetch_player_game_high_rows <- function(conn, seasons = NULL, team_id = NULL, round = NULL, stat = "points", search = "", limit = 10L) {
  # Single query over all requested seasons; avoids one round-trip per season.
  # When seasons is NULL (no filter), omit the IN clause so the planner can do
  # a straight index scan on stat without a large IN list covering every season.
  seasons_filter <- if (!is.null(seasons) && length(seasons)) as.integer(seasons) else NULL

  if (has_player_match_stats(conn)) {
    # Fast path: player_match_stats is pre-aggregated at match level — no
    # GROUP BY needed. ORDER BY + LIMIT uses idx_pms_stat_value directly.
    query <- paste(
      "SELECT pms.player_id, players.canonical_name AS player_name, pms.squad_name,",
      "CASE WHEN matches.home_squad_id = pms.squad_id THEN matches.away_squad_name ELSE matches.home_squad_name END AS opponent,",
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
    search_filters <- apply_player_search_filter(filters$query, filters$params, search, "pms.player_id")
    filters$query  <- paste0(search_filters$query, " ORDER BY pms.match_value DESC, pms.round_number DESC, players.canonical_name ASC LIMIT ?limit")
    filters$params <- search_filters$params
    filters$params$limit <- limit
    return(query_rows(conn, filters$query, filters$params))
  }

  # Fallback: aggregate period rows at query time (slower on B1ms)
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
    " GROUP BY stats.player_id, players.canonical_name, stats.squad_name, stats.season, stats.round_number, stats.match_id, matches.local_start_time",
    " ORDER BY total_value DESC, stats.round_number DESC, players.canonical_name ASC LIMIT ?limit"
  )
  filters$params <- search_filters$params
  filters$params$limit <- limit

  sort_query_result_rows(query_rows(conn, filters$query, filters$params), "list")
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
    builder <- build_team_match_query
    base_query <- builder(
      stat = intent$stat,
      seasons = seasons_filter,
      team_id = intent$team_id,
      opponent_id = intent$opponent_id,
      comparison = intent$comparison,
      threshold = intent$threshold
    )
    tbl_alias <- "stats"
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
