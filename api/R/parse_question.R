# Natural language question parser for Ask the Stats.
# Extracts structured parameters (subject, stat, operator, threshold, opponent, season)
# from freeform netball questions.

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
extract_operator <- function(text) {
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

  # "lowest" → lowest
  if (grepl("\\blowest\\b", text)) {
    return(list(operator = "lowest", threshold = NULL))
  }

  # "which players|which teams|list players|list teams" → list
  if (grepl("\\b(which|list)\\s+(players|teams|young players)\\b", text)) {
    return(list(operator = "list", threshold = NULL))
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

  # Fall back if no clear pattern detected
  list(operator = NULL, threshold = NULL)
}

# Extract threshold number from text like "50 goals or more", "5+", "[threshold]+"
extract_threshold <- function(text) {
  # Look for "N or more", "N or greater", "N+"
  threshold_patterns <- list(
    "\\b(\\d+)\\s+(?:or\\s+)?(?:or\\s+)?(?:more|greater)" = 1,
    "\\b(\\d+)\\+" = 1,
    "at\\s+least\\s+(\\d+)" = 1,
    "more\\s+than\\s+(\\d+)" = 1,
    "fewer\\s+than\\s+(\\d+)" = 1,
    "at\\s+most\\s+(\\d+)" = 1
  )

  for (pattern in names(threshold_patterns)) {
    matches <- regmatches(text, gregexpr(pattern, text))
    if (length(matches[[1]]) > 0) {
      # Extract the number from the matched group
      nums <- gregexpr("\\d+", matches[[1]][[1]])
      num_str <- substr(matches[[1]][[1]], nums[[1]][1], nums[[1]][1] + attr(nums[[1]], "match.length")[1] - 1)
      if (nzchar(num_str)) {
        return(as.integer(num_str))
      }
    }
  }

  NULL
}

# Extract stat from text
extract_stat <- function(text) {
  # Define stat mappings: lowercase aliases → canonical stat key
  stat_mappings <- list(
    goals = c("goals", "scored", "score", "goal total", "goal totals"),
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

  # Known Super Netball teams (for matching)
  team_names <- c(
    "adelaide thunderbirds", "brisbane lions", "collingwood magpies",
    "suncorp vixens", "perth wildcats", "melbourne vixens",
    "vixens", "swifts", "firebirds", "magpies", "fever",
    "thunderbirds", "lions"
  )
  teams_pattern <- paste0("\\b(", paste(gsub(" ", "\\\\s+", team_names), collapse = "|"), ")\\b")

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

  # If no clear subject found, return NULL
  list(subject = NULL)
}

# Extract opponent team name
extract_opponent <- function(text) {
  # Known Super Netball teams
  team_names <- c(
    "vixens", "swifts", "firebirds", "magpies", "fever",
    "suncorp vixens", "perth wildcats", "melbourne vixens",
    "adelaide thunderbirds", "brisbane lions", "collingwood magpies"
  )

  # Look for "against [team]", "vs [team]", "versus [team]"
  for (team in sort(team_names, decreasing = TRUE)) {  # Sort by length descending to match longer names first
    # against pattern
    against_pattern <- paste0("\\bagainst\\s+(?:the\\s+)?", gsub(" ", "\\\\s+", team), "\\b")
    if (grepl(against_pattern, text)) {
      return(list(opponent_name = team))
    }

    # vs pattern
    vs_pattern <- paste0("\\bvs(?:\\.|\\s+)\\s+(?:the\\s+)?", gsub(" ", "\\\\s+", team), "\\b")
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
