player_reference_default <- function(value, fallback) {
  if (is.null(value) || length(value) == 0) {
    return(fallback)
  }
  value
}

required_player_reference_columns <- function() {
  c("player_id", "date_of_birth", "nationality", "import_status", "source_label", "source_url", "verified_at", "notes")
}

normalize_import_status <- function(value) {
  if (is.null(value) || length(value) == 0L || all(is.na(value))) {
    return(NA_character_)
  }
  normalized <- tolower(trimws(as.character(player_reference_default(value, ""))))
  if (!nzchar(normalized)) {
    return(NA_character_)
  }
  if (!normalized %in% c("local", "import")) {
    stop("import_status must be either 'local' or 'import'.", call. = FALSE)
  }
  normalized
}

normalize_required_reference_text <- function(values) {
  normalized <- trimws(as.character(values))
  normalized[is.na(values)] <- NA_character_
  normalized
}

has_missing_reference_text <- function(values) {
  is.na(values) | !nzchar(values)
}

normalize_player_reference_id <- function(values) {
  normalized <- trimws(as.character(values))
  normalized[is.na(values)] <- NA_character_

  if (any(is.na(normalized) | !grepl("^[0-9]+$", normalized))) {
    stop("player_id must be an integer in every maintained row.", call. = FALSE)
  }

  as.integer(normalized)
}

debut_age_band <- function(age_years) {
  age_years <- suppressWarnings(as.numeric(age_years))
  if (is.na(age_years)) return(NA_character_)
  if (age_years < 20) return("19 and under")
  if (age_years < 23) return("20 to 22")
  if (age_years < 26) return("23 to 25")
  "26 and over"
}

season_anchor_dates <- function(matches_rows) {
  split_dates <- split(matches_rows$match_date, matches_rows$season)
  data.frame(
    season = as.integer(names(split_dates)),
    match_date = as.Date(vapply(
      split_dates,
      function(values) {
        observed_dates <- values[!is.na(values)]
        if (!length(observed_dates)) {
          return(NA_character_)
        }
        as.character(min(observed_dates))
      },
      character(1)
    )),
    stringsAsFactors = FALSE
  )
}

age_in_years_on <- function(date_of_birth, anchor_date) {
  floor(as.numeric(anchor_date - date_of_birth) / 365.25)
}

empty_summary_rows <- function(seasons, column_name, mode = c("numeric", "character")) {
  mode <- match.arg(mode)
  rows <- data.frame(season = seasons, stringsAsFactors = FALSE)
  rows[[column_name]] <- if (mode == "character") NA_character_ else NA_real_
  rows
}

build_player_reference_tables <- function(players_rows, player_period_rows, matches_rows, reference_rows) {
  debut_rows <- aggregate(season ~ player_id, data = unique(player_period_rows[c("player_id", "season")]), FUN = min)
  names(debut_rows)[2] <- "debut_season"

  if (nrow(reference_rows) > 0L) {
    player_reference <- merge(players_rows, reference_rows, by = "player_id", all.x = TRUE, sort = FALSE)
  } else {
    player_reference <- data.frame(
      players_rows,
      date_of_birth = as.Date(rep(NA_character_, nrow(players_rows))),
      nationality = rep(NA_character_, nrow(players_rows)),
      import_status = rep(NA_character_, nrow(players_rows)),
      source_label = rep(NA_character_, nrow(players_rows)),
      source_url = rep(NA_character_, nrow(players_rows)),
      verified_at = as.Date(rep(NA_character_, nrow(players_rows))),
      notes = rep(NA_character_, nrow(players_rows)),
      stringsAsFactors = FALSE
    )
  }
  player_reference <- merge(player_reference, debut_rows, by = "player_id", all.x = TRUE, sort = FALSE)

  anchors <- season_anchor_dates(matches_rows)
  season_players <- unique(player_period_rows[c("player_id", "season")])
  season_players <- merge(season_players, player_reference, by = "player_id", all.x = TRUE, sort = FALSE)
  season_players <- merge(season_players, anchors, by = "season", all.x = TRUE, sort = FALSE)

  season_players$experience_seasons <- ifelse(
    is.na(season_players$debut_season),
    NA_integer_,
    as.integer(season_players$season - season_players$debut_season + 1L)
  )
  season_players$age_years <- ifelse(
    is.na(season_players$date_of_birth) | is.na(season_players$match_date),
    NA_real_,
    age_in_years_on(season_players$date_of_birth, season_players$match_date)
  )
  season_players$debut_age_band <- ifelse(
    season_players$season == season_players$debut_season,
    vapply(season_players$age_years, debut_age_band, character(1)),
    NA_character_
  )
  # Import classifications only map cleanly to the SSN-era roster rules.
  season_players$summary_import_status <- ifelse(
    season_players$season >= 2017L & season_players$season <= 2026L,
    season_players$import_status,
    NA_character_
  )

  players_per_season <- aggregate(player_id ~ season, data = season_players, FUN = length)
  names(players_per_season)[2] <- "players_with_matches"
  season_keys <- unique(players_per_season["season"])

  age_counts <- aggregate(!is.na(age_years) ~ season, data = season_players, FUN = sum)
  names(age_counts)[2] <- "players_with_birth_date"

  import_count_rows <- subset(season_players, season >= 2017L & season <= 2026L)
  if (nrow(import_count_rows) > 0L) {
    import_counts <- aggregate(!is.na(import_status) ~ season, data = import_count_rows, FUN = sum)
    names(import_counts)[2] <- "players_with_import_status"
  } else {
    import_counts <- empty_summary_rows(season_keys$season, "players_with_import_status")
  }

  avg_experience <- aggregate(experience_seasons ~ season, data = season_players, FUN = function(x) round(mean(x, na.rm = TRUE), 2))
  names(avg_experience)[2] <- "average_experience_seasons"

  avg_age_rows <- subset(season_players, !is.na(age_years))
  if (nrow(avg_age_rows) > 0L) {
    avg_age <- aggregate(age_years ~ season, data = avg_age_rows, FUN = function(x) round(mean(x, na.rm = TRUE), 2))
    names(avg_age)[2] <- "average_player_age"
  } else {
    avg_age <- empty_summary_rows(season_keys$season, "average_player_age")
  }

  avg_debut_age_rows <- subset(season_players, season == debut_season & !is.na(age_years))
  if (nrow(avg_debut_age_rows) > 0L) {
    avg_debut_age <- aggregate(age_years ~ season, data = avg_debut_age_rows, FUN = function(x) round(mean(x, na.rm = TRUE), 2))
    names(avg_debut_age)[2] <- "average_debut_age"
  } else {
    avg_debut_age <- empty_summary_rows(season_keys$season, "average_debut_age")
  }

  import_share_rows <- subset(season_players, !is.na(summary_import_status))
  if (nrow(import_share_rows) > 0L) {
    import_share <- aggregate(summary_import_status == "import" ~ season, data = import_share_rows, FUN = function(x) round(mean(x), 4))
    names(import_share)[2] <- "import_share"
  } else {
    import_share <- empty_summary_rows(season_keys$season, "import_share")
  }

  league_summary <- Reduce(function(left, right) merge(left, right, by = "season", all = TRUE), list(
    players_per_season, age_counts, import_counts, avg_age, avg_experience, avg_debut_age, import_share
  ))
  league_summary$age_coverage_share <- round(league_summary$players_with_birth_date / league_summary$players_with_matches, 4)
  league_summary$import_coverage_share <- round(league_summary$players_with_import_status / league_summary$players_with_matches, 4)

  debut_rows_only <- subset(season_players, season == debut_season & !is.na(debut_age_band))
  if (nrow(debut_rows_only) > 0L) {
    debut_band_counts <- aggregate(player_id ~ season + debut_age_band, data = debut_rows_only, FUN = length)
    names(debut_band_counts) <- c("season", "age_band", "players")
    debut_band_names <- aggregate(
      canonical_name ~ season + debut_age_band,
      data = debut_rows_only,
      FUN = function(values) {
        names <- sort(unique(as.character(values[!is.na(values) & nzchar(values)])))
        if (!length(names)) {
          return(NA_character_)
        }
        paste(names, collapse = ", ")
      }
    )
    names(debut_band_names) <- c("season", "age_band", "debut_player_names")
    debut_totals <- aggregate(players ~ season, data = debut_band_counts, FUN = sum)
    names(debut_totals)[2] <- "total_debut_players"
    debut_bands <- merge(debut_band_counts, debut_totals, by = "season", all.x = TRUE, sort = FALSE)
    debut_bands <- merge(debut_bands, debut_band_names, by = c("season", "age_band"), all.x = TRUE, sort = FALSE)
    debut_bands$share <- round(debut_bands$players / debut_bands$total_debut_players, 4)
  } else {
    debut_bands <- data.frame(
      season = integer(),
      age_band = character(),
      players = integer(),
      total_debut_players = integer(),
      debut_player_names = character(),
      share = numeric(),
      stringsAsFactors = FALSE
    )
  }

  list(
    player_reference = player_reference,
    player_season_demographics = season_players,
    league_composition_summary = league_summary,
    league_composition_debut_bands = debut_bands
  )
}

read_player_reference_csv <- function(path) {
  rows <- utils::read.csv(path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  missing_columns <- setdiff(required_player_reference_columns(), names(rows))
  if (length(missing_columns)) {
    stop("Missing player reference columns: ", paste(missing_columns, collapse = ", "), call. = FALSE)
  }

  rows <- rows[required_player_reference_columns()]
  rows$player_id <- normalize_player_reference_id(rows$player_id)
  if (anyDuplicated(rows$player_id)) {
    stop("player_id must be unique in the maintained player reference file.", call. = FALSE)
  }

  raw_date_of_birth <- rows$date_of_birth
  rows$date_of_birth <- as.Date(raw_date_of_birth)
  if (any(!is.na(raw_date_of_birth) & is.na(rows$date_of_birth))) {
    stop("date_of_birth must be ISO-8601 (YYYY-MM-DD) in every maintained row.", call. = FALSE)
  }

  rows$import_status <- vapply(rows$import_status, normalize_import_status, character(1))
  rows$nationality <- normalize_required_reference_text(rows$nationality)
  rows$source_label <- normalize_required_reference_text(rows$source_label)
  rows$source_url <- normalize_required_reference_text(rows$source_url)
  raw_verified_at <- rows$verified_at
  rows$verified_at <- as.Date(raw_verified_at)
  if (any(!is.na(raw_verified_at) & is.na(rows$verified_at))) {
    stop("verified_at must be ISO-8601 (YYYY-MM-DD) in every maintained row.", call. = FALSE)
  }

  rows$notes <- trimws(as.character(rows$notes))
  rows$notes[is.na(rows$notes)] <- ""
  rows
}
