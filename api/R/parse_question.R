# Parse natural language netball questions into structured query parameters
# Supports 4 question types: trend, comparison, game_record, count_threshold
# Extracts: subject (player/team), stat (goals, assists, etc.), operator, threshold, opponent, season
# Returns structured result: success (bool), error (string), parsed (list)
# If parsing fails, provides helpful error message with example patterns
# @param question_text Character: freeform question (e.g. "highest goals by a player 2023?")
# @param conn Optional DBI connection (for reference data validation; not currently used)
# @return List with: success (bool), error (string), parsed (list with subject, stat, operator, threshold, opponent_name, season)
parse_natural_language_question <- function(question_text, conn = NULL) {
  if (!is.character(question_text) || length(question_text) == 0L) {
    return(list(
      success = FALSE,
      error = "Question text must be a non-empty string.",
      parsed = NULL
    ))
  }

  text <- tolower(trimws(question_text[[1]]))
  if (!nzchar(text)) {
    return(list(
      success = FALSE,
      error = "Question text cannot be empty.",
      parsed = NULL
    ))
  }

  # Initialize parsed result structure
  parsed <- list(
    subject = NULL,
    stat = NULL,
    operator = NULL,
    threshold = NULL,
    opponent_name = NULL,
    season = NULL,
    raw_query = question_text
  )

  # Step 1: Detect operator type and extract threshold if applicable
  operator_result <- extract_operator(text)
  parsed$operator <- operator_result$operator
  parsed$threshold <- operator_result$threshold

  # Step 1b: For count_threshold operator, also try to extract numeric threshold
  if (parsed$operator == "count_threshold") {
    threshold_value <- extract_threshold(text)
    if (!is.null(threshold_value)) {
      parsed$threshold <- threshold_value
    }
  }

  if (is.null(parsed$operator)) {
    return(list(
      success = FALSE,
      error = "Could not identify question type. Try patterns like 'how many times', 'highest', 'which players', or 'vs'.",
      parsed = NULL
    ))
  }

  # Step 2: Extract stat
  stat_result <- extract_stat(text)
  parsed$stat <- stat_result$stat

  # For head_to_head comparisons without an explicit stat, default to "goals"
  if (is.null(parsed$stat) && parsed$operator == "head_to_head") {
    parsed$stat <- "goals"
  }

  if (is.null(parsed$stat)) {
    return(list(
      success = FALSE,
      error = "Could not identify stat. Try stat names like 'goals', 'intercepts', 'feeds', 'goal assists', 'gains', 'penalties'.",
      parsed = NULL
    ))
  }

  # Step 3: Extract subject (player name or "players"/"teams")
  subject_result <- extract_subject(text)
  parsed$subject <- subject_result$subject

  if (is.null(parsed$subject)) {
    return(list(
      success = FALSE,
      error = "Could not identify subject. Start with a player name or 'which players' / 'which teams'.",
      parsed = NULL
    ))
  }

  # Step 4: Extract opponent (optional)
  opponent_result <- extract_opponent(text)
  parsed$opponent_name <- opponent_result$opponent_name

  # Step 5: Extract season (optional, defaults to NULL which means current season)
  season_result <- extract_season(text)
  parsed$season <- season_result$season

  # Success!
  list(
    success = TRUE,
    error = NULL,
    parsed = parsed
  )
}

# Detect operator type from question text
# Extract operator type from question text
# Supports: "which/list" (list), "how many times" (count_threshold), "highest/most" (highest),
# "record" (highest), "lowest", "vs/versus" (head_to_head), "against", "at least/more than" (count_threshold)
# Defaults to "highest" if no clear operator found
# @param text Character: lowercased, trimmed question text
# @return List with operator (string) and threshold (NULL, set by extract_threshold separately)
extract_operator <- function(text) {
  # "which players|which teams|list players|list teams" → list (check FIRST, before "record")
  if (grepl("\\b(which|list)\\s+(players|teams|young players)\\b", text)) {
    return(list(operator = "list", threshold = NULL))
  }

  # "how many times" → count_threshold
  if (grepl("\\bhow\\s+many\\s+times?\\b", text)) {
    return(list(operator = "count_threshold", threshold = NULL))
  }

  # "how many" without "times" → count (treat as at least 1)
  if (grepl("\\bhow\\s+many\\b", text)) {
    return(list(operator = "count_threshold", threshold = NULL))
  }

  # "highest" or "most" → highest
  if (grepl("\\b(highest|most)\\b", text)) {
    return(list(operator = "highest", threshold = NULL))
  }

  # "record" implies highest (e.g., "career record", "season record", "record?")
  if (grepl("\\brecord\\b", text)) {
    return(list(operator = "highest", threshold = NULL))
  }

  # "lowest" → lowest
  if (grepl("\\blowest\\b", text)) {
    return(list(operator = "lowest", threshold = NULL))
  }

  # "vs|versus|compared to|against.*vs" → head_to_head or comparison
  # (for count_threshold with opponent)
  if (grepl("\\bvs\\b|\\bversus\\b|\\bcompared\\s+to\\b", text)) {
    return(list(operator = "head_to_head", threshold = NULL))
  }

  # "against" (used for head-to-head or count_threshold with opponent)
  if (grepl("\\bagainst\\b", text)) {
    return(list(operator = "count_threshold", threshold = NULL))
  }

  # "at least", "at most", "more than", "fewer than" → count_threshold
  # (threshold-based questions like "at least 10 goal assists")
  if (grepl("\\b(at\\s+least|at\\s+most|more\\s+than|fewer\\s+than)\\b", text)) {
    return(list(operator = "count_threshold", threshold = NULL))
  }

  # If no clear operator found but text contains a stat, default to "highest"
  # (e.g., "Team X stat?" or "Player Y stat per game?" → highest)
  return(list(operator = "highest", threshold = NULL))
}

# Extract numeric threshold from count-based questions
# Supports patterns: "50 goals or more", "5+", "at least N", "more than N", "fewer than N", "at most N"
# Used for count_threshold questions (e.g., "at least 10 goal assists per game")
# @param text Character: lowercased, trimmed question text
# @return Integer threshold or NULL if no threshold found
extract_threshold <- function(text) {
  # Pattern 1: "N [word(s)] or more", "N [word(s)] or greater" (e.g., "50 goals or more")
  m <- regexpr("\\b(\\d+)(?:\\s+\\w+)*\\s+or\\s+(more|greater)", text, perl = TRUE)
  if (m > 0) {
    match_str <- substr(text, m, m + attr(m, "match.length") - 1)
    # Extract just the leading number
    num_match <- regexpr("^\\d+", match_str)
    num_str <- substr(match_str, num_match, num_match + attr(num_match, "match.length") - 1)
    if (nzchar(num_str)) return(as.integer(num_str))
  }

  # Pattern 2: "N+" (e.g., "5+")
  m <- regexpr("\\b(\\d+)\\+", text)
  if (m > 0) {
    match_str <- substr(text, m, m + attr(m, "match.length") - 1)
    num_str <- gsub("\\+", "", match_str)
    if (nzchar(num_str)) return(as.integer(num_str))
  }

  # Pattern 3: "at least N"
  m <- regexpr("at\\s+least\\s+(\\d+)", text)
  if (m > 0) {
    match_str <- substr(text, m, m + attr(m, "match.length") - 1)
    num_str <- sub(".*\\s+", "", match_str)
    if (nzchar(num_str)) return(as.integer(num_str))
  }

  # Pattern 4: "more than N"
  m <- regexpr("more\\s+than\\s+(\\d+)", text)
  if (m > 0) {
    match_str <- substr(text, m, m + attr(m, "match.length") - 1)
    num_str <- sub(".*\\s+", "", match_str)
    if (nzchar(num_str)) return(as.integer(num_str))
  }

  # Pattern 5: "fewer than N"
  m <- regexpr("fewer\\s+than\\s+(\\d+)", text)
  if (m > 0) {
    match_str <- substr(text, m, m + attr(m, "match.length") - 1)
    num_str <- sub(".*\\s+", "", match_str)
    if (nzchar(num_str)) return(as.integer(num_str))
  }

  # Pattern 6: "at most N"
  m <- regexpr("at\\s+most\\s+(\\d+)", text)
  if (m > 0) {
    match_str <- substr(text, m, m + attr(m, "match.length") - 1)
    num_str <- sub(".*\\s+", "", match_str)
    if (nzchar(num_str)) return(as.integer(num_str))
  }

  NULL
}

# Extract netball stat name from question text
# Maps common aliases to canonical stat keys (goals, assists, gain, intercepts, etc.)
# Prefers longest matching alias to avoid "goal" matching when "goals" is intended
# Uses word boundaries to prevent partial matches ("goals" not matched in "goalAssists")
# @param text Character: lowercased, trimmed question text
# @return Character: canonical stat key (e.g., "goals", "goalAssists") or NULL if not found
extract_stat <- function(text) {
  # Define stat mappings: lowercase aliases → canonical stat key
  stat_mappings <- list(
    goals = c("goals", "scored", "score", "scoring", "goal total", "goal totals"),
    goalAttempts = c("goal attempts", "attempts", "shot attempts", "shots"),
    goalAssists = c("assists", "assist", "goal assists", "goal assist", "ga"),
    feeds = c("feeds", "feed", "feeds into circle"),
    gain = c("gains", "gain", "defensive gains"),
    intercepts = c("intercepts", "intercept", "interceptions", "interception", "int"),
    netPoints = c("net points", "netpoints"),
    obstructionPenalties = c("obstructions", "obstruction penalties", "obstruction penalty"),
    contactPenalties = c("contacts", "contact penalties", "contact penalty"),
    generalPlayTurnovers = c("general play turnovers", "general play turnover", "gpt"),
    unforcedTurnovers = c("unforced turnovers", "unforced turnover", "uto"),
    pickups = c("pickups", "pickup"),
    centrePassReceives = c("centre pass receives", "centre pass receive", "center pass receives"),
    deflections = c("deflections", "deflection"),
    rebounds = c("rebounds", "rebound"),
    goal1 = c("1 point goals", "one point goals", "1 point goal", "one point goal"),
    goal2 = c("2 point goals", "two point goals", "2 point goal", "two point goal"),
    attempts1 = c("1 point goal attempts", "one point goal attempts"),
    attempts2 = c("2 point goal attempts", "two point goal attempts"),
    disposals = c("disposals", "disposal"),
    penalties = c("penalties", "penalty", "pen"),
    possessions = c("possessions", "possession"),
    points = c("points", "pts")
  )

  # Search for each stat, order by longest match (to prefer longer aliases)
  best_match <- NULL
  best_length <- 0

  for (stat_key in names(stat_mappings)) {
    for (alias in stat_mappings[[stat_key]]) {
      # Use word boundaries to match only whole words
      pattern <- paste0("\\b", gsub(" ", "\\\\s+", alias), "\\b")
      if (grepl(pattern, text)) {
        if (nchar(alias) > best_length) {
          best_match <- stat_key
          best_length <- nchar(alias)
        }
      }
    }
  }

  list(stat = best_match)
}

# Extract subject (player or team name, or "players"/"teams")
extract_subject <- function(text) {
  # First check for "which players", "which teams", "list players", "who", etc.
  if (grepl("\\b(which|list|who)\\s+(players|teams|young players)?\\b", text) || grepl("^\\bwho\\b", text)) {
    if (grepl("teams", text)) {
      return(list(subject = "teams"))
    } else if (grepl("\\b(who|which players|young players)\\b", text)) {
      return(list(subject = "players"))
    }
  }

  # Core 8 Super Netball teams (2024/2025 season)
  # Note: Full team name resolution (aliases, abbreviations) happens in backend helpers.R (resolve_query_team)
  team_names <- c(
    "adelaide thunderbirds", "collingwood magpies", "gws giants",
    "melbourne vixens", "nsw swifts", "queensland firebirds",
    "sunshine coast lightning", "west coast fever",
    "vixens", "swifts", "firebirds", "magpies", "fever",
    "thunderbirds", "giants", "lightning"
  )
  teams_pattern <- paste0("\\b(", paste(gsub(" ", "\\\\s+", team_names), collapse = "|"), ")\\b")

  # Try matching "by a [subject]" (e.g., "by a team", "by a player")
  # Convert singular nouns to plural for consistency
  by_pattern <- "\\bby\\s+a\\s+([a-z]+)\\b"
  by_match <- regmatches(text, regexec(by_pattern, text))
  if (length(by_match[[1]]) > 1) {
    subject <- trimws(by_match[[1]][2])
    if (nzchar(subject)) {
      # Convert singular to plural for generic subjects
      if (subject == "team") subject <- "teams"
      if (subject == "player") subject <- "players"
      return(list(subject = subject))
    }
  }

  # Try matching "did [subject] have [stat]" (e.g., "did Caitlin Bassett have 5+ intercepts")
  did_pattern <- "\\bdid\\s+(.+?)\\s+have\\b"
  did_match <- regmatches(text, regexec(did_pattern, text))
  if (length(did_match[[1]]) > 1) {
    subject <- trimws(did_match[[1]][2])
    if (nzchar(subject)) {
      return(list(subject = subject))
    }
  }

  # Try matching "has [subject] scored/recorded/made/etc"
  # Use non-greedy match to capture up to the first action verb
  has_pattern <- "\\bhas\\s+(.+?)\\s+(?:scored|recorded|made|had|gotten|achieved|played|completed)"
  has_match <- regmatches(text, regexec(has_pattern, text))
  if (length(has_match[[1]]) > 1) {
    subject <- trimws(has_match[[1]][2])
    if (nzchar(subject)) {
      return(list(subject = subject))
    }
  }

  # Try matching "have [subject]" (plural)
  have_pattern <- "\\bhave\\s+(.+?)\\s+(?:scored|recorded|made|had|gotten|achieved|played|completed)"
  have_match <- regmatches(text, regexec(have_pattern, text))
  if (length(have_match[[1]]) > 1) {
    subject <- trimws(have_match[[1]][2])
    if (nzchar(subject)) {
      return(list(subject = subject))
    }
  }

  # Look for "[subject]'s" or "[subject]'s"
  possessive_pattern <- "\\b([A-Za-z]+)'s\\s+(?:highest|lowest|best|total)"
  possessive_match <- regmatches(text, regexec(possessive_pattern, text))
  if (length(possessive_match[[1]]) > 1) {
    subject <- trimws(possessive_match[[1]][2])
    if (nzchar(subject)) {
      return(list(subject = subject))
    }
  }

  # Look for team names at start of question (common Super Netball teams)
  for (team in team_names) {
    pattern <- paste0("^\\b", gsub(" ", "\\\\s+", team), "\\b")
    if (grepl(pattern, text)) {
      return(list(subject = team))
    }
  }

  # Try to extract a player name from the start (e.g., "Liz Watson ga record?", "Paige Van Der Schaaf feeds record?")
  # Pattern: multiple words followed by stat keyword
  # Include both abbreviated stats (ga, int, gpt, uto) and full stat names (feeds, goals, intercepts, etc.)
  # Skip if it starts with reserved words like "how", "which", "what", etc.
  name_pattern <- "^([a-z]+(?:\\s+[a-z]+)+)\\s+(?:feeds|goals|intercepts|assists|penalties|gains|deflections|rebounds|pickups|disposals|possessions|points|ga|int|gpt|uto)"
  name_match <- regmatches(text, regexec(name_pattern, text))
  if (length(name_match[[1]]) > 1) {
    subject <- trimws(name_match[[1]][2])
    # Reject if subject starts with reserved words
    if (nzchar(subject) && !grepl("^\\b(how|which|what|who|when|where|why|is|are|was|were)\\b", subject)) {
      return(list(subject = subject))
    }
  }

  # Default fallback: threshold-only questions default to "players"
  # (e.g., "At least 10 goal assists in a match?" → query players)
  if (grepl("\\b(at\\s+least|at\\s+most|more\\s+than|fewer\\s+than)\\b", text)) {
    return(list(subject = "players"))
  }

  # If no clear subject found, return NULL
  list(subject = NULL)
}

# Extract opponent team name
extract_opponent <- function(text) {
  # Core 8 Super Netball teams (2024/2025 season)
  # Note: Full team name resolution (aliases, abbreviations) happens in backend helpers.R (resolve_query_team)
  team_names <- c(
    "adelaide thunderbirds", "collingwood magpies", "gws giants",
    "melbourne vixens", "nsw swifts", "queensland firebirds",
    "sunshine coast lightning", "west coast fever",
    "vixens", "swifts", "firebirds", "magpies", "fever",
    "thunderbirds", "giants", "lightning"
  )

  # Look for "against [team]", "vs [team]", "versus [team]"
  for (team in sort(team_names, decreasing = TRUE)) {  # Sort by length descending to match longer names first
    # against pattern
    against_pattern <- paste0("\\bagainst\\s+(?:the\\s+)?", gsub(" ", "\\\\s+", team), "\\b")
    if (grepl(against_pattern, text)) {
      return(list(opponent_name = team))
    }

    # vs pattern: "vs [team]" (with optional period after vs)
    vs_pattern <- paste0("\\bvs\\.?\\s+(?:the\\s+)?", gsub(" ", "\\\\s+", team), "\\b")
    if (grepl(vs_pattern, text)) {
      return(list(opponent_name = team))
    }

    # versus pattern
    versus_pattern <- paste0("\\bversus\\s+(?:the\\s+)?", gsub(" ", "\\\\s+", team), "\\b")
    if (grepl(versus_pattern, text)) {
      return(list(opponent_name = team))
    }
  }

  list(opponent_name = NULL)
}

# Extract season/year from text
extract_season <- function(text) {
  # Look for 4-digit year between 2008 and current year + 1
  year_pattern <- "\\b(20\\d{2})\\b"
  year_matches <- gregexpr(year_pattern, text)
  year_texts <- regmatches(text, year_matches)

  if (length(year_texts[[1]]) > 0) {
    # Take the first (or last) year mentioned
    year_str <- year_texts[[1]][1]
    year_int <- as.integer(year_str)

    # Validate it's in reasonable range (2008-2026)
    if (year_int >= 2008L && year_int <= 2026L) {
      return(list(season = year_int))
    }
  }

  list(season = NULL)
}
