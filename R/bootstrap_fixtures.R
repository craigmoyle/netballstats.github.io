first_fixture_value <- function(value) {
  if (is.null(value) || !length(value) || all(is.na(value))) {
    return(NULL)
  }

  value[[1]]
}

normalize_fixture_round_number <- function(value) {
  raw_value <- first_fixture_value(value)
  normalized <- if (is.null(raw_value)) "" else trimws(as.character(raw_value))
  parsed <- suppressWarnings(as.integer(sub("^[Rr]", "", normalized)))

  if (is.na(parsed) || parsed < 1L) {
    stop("Fixture round number must be numeric or R-prefixed numeric.", call. = FALSE)
  }

  parsed
}

normalize_fixture_match_number <- function(match_number = NULL, game_number = NULL) {
  for (candidate in list(match_number, game_number)) {
    raw_value <- first_fixture_value(candidate)
    if (is.null(raw_value)) {
      next
    }
    parsed <- suppressWarnings(as.integer(raw_value))
    if (length(parsed) == 1L && !is.na(parsed) && parsed >= 1L) {
      return(parsed)
    }
  }

  1L
}

normalize_fixture_team_name <- function(value) {
  team_map <- c(
    "Swifts" = "NSW Swifts",
    "GIANTS" = "GIANTS Netball",
    "Thunderbirds" = "Adelaide Thunderbirds",
    "Lightning" = "Sunshine Coast Lightning",
    "Firebirds" = "Queensland Firebirds",
    "Mavericks" = "Melbourne Mavericks",
    "Fever" = "West Coast Fever",
    "Vixens" = "Melbourne Vixens"
  )

  raw_value <- first_fixture_value(value)
  normalized <- as.character(raw_value %||% "")
  mapped <- unname(team_map[[normalized]])
  if (!is.null(mapped) && nzchar(mapped)) {
    return(mapped)
  }

  normalized
}
