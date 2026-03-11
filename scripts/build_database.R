#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(DBI)
  library(RSQLite)
  library(dplyr)
  library(purrr)
  library(superNetballR)
})

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || all(is.na(x))) {
    return(y)
  }

  if (is.character(x) && !nzchar(x[1])) {
    return(y)
  }

  x
}

script_path <- function() {
  file_arg <- grep("^--file=", commandArgs(), value = TRUE)
  if (!length(file_arg)) {
    return(normalizePath(".", mustWork = FALSE))
  }

  normalizePath(sub("^--file=", "", file_arg[[1]]), mustWork = FALSE)
}

repo_root <- normalizePath(file.path(dirname(script_path()), ".."), mustWork = FALSE)
config_path <- file.path(repo_root, "config", "competitions.csv")
default_db_path <- file.path(repo_root, "storage", "netball_stats.sqlite")
db_path <- Sys.getenv("NETBALL_STATS_DB", default_db_path)
sample_mode <- identical(tolower(Sys.getenv("NETBALL_STATS_SAMPLE", "false")), "true")

parse_numeric_value <- function(value) {
  numeric <- suppressWarnings(as.numeric(as.character(value)))
  ifelse(is.na(numeric), NA_real_, numeric)
}

first_or_missing <- function(values, missing) {
  if (!length(values)) {
    return(missing)
  }

  value <- values[[1]]
  if (is.null(value) || length(value) == 0 || is.na(value)) {
    return(missing)
  }

  value
}

match_not_found <- function(error) {
  inherits(error, "netball_match_not_found")
}

is_played_match_payload <- function(payload) {
  is.list(payload) &&
    is.list(payload$teamPeriodStats) &&
    !is.null(payload$teamPeriodStats$team) &&
    length(payload$teamPeriodStats$team) > 0
}

fetch_match_payload <- function(comp_id, round_number, game_number) {
  tryCatch(
    superNetballR::downloadMatch(as.character(comp_id), round_number, game_number),
    error = function(error) {
      message_text <- conditionMessage(error)
      if (grepl("404", message_text, fixed = TRUE)) {
        structure(
          list(message = message_text),
          class = c("netball_match_not_found", "list")
        )
      } else {
        stop(error)
      }
    }
  )
}

load_sample_entries <- function() {
  data(round5_game3, package = "superNetballR")
  list(
    list(
      season = 2017L,
      phase = "regular",
      competition_id = 10083L,
      payload = round5_game3
    )
  )
}

collect_live_entries <- function(competitions) {
  entries <- list()
  entry_index <- 0L

  for (competition_index in seq_len(nrow(competitions))) {
    competition <- competitions[competition_index, , drop = FALSE]
    season <- as.integer(competition$season[[1]])
    phase <- competition$phase[[1]]
    competition_id <- as.integer(competition$competition_id[[1]])

    message(sprintf("Collecting season %s (%s, competition %s)", season, phase, competition_id))

    for (round_number in seq_len(25L)) {
      round_entries <- 0L

      for (game_number in seq_len(10L)) {
        payload <- fetch_match_payload(competition_id, round_number, game_number)
        if (match_not_found(payload)) {
          break
        }

        if (!is_played_match_payload(payload)) {
          next
        }

        entry_index <- entry_index + 1L
        round_entries <- round_entries + 1L
        entries[[entry_index]] <- list(
          season = season,
          phase = phase,
          competition_id = competition_id,
          payload = payload
        )
      }

      if (round_entries == 0L) {
        break
      }
    }
  }

  entries
}

prepare_match_tables <- function(entries, competitions) {
  team_colours_lookup <- superNetballR::team_colours

  match_rows <- vector("list", length(entries))
  team_rows <- vector("list", length(entries))
  player_rows <- vector("list", length(entries))
  team_stat_rows <- vector("list", length(entries))
  player_stat_rows <- vector("list", length(entries))

  for (index in seq_along(entries)) {
    entry <- entries[[index]]
    payload <- entry$payload
    match_info <- payload$matchInfo

    team_info <- dplyr::bind_rows(payload$teamInfo$team) %>%
      dplyr::rename(
        squad_id = squadId,
        squad_name = squadName,
        squad_nickname = squadNickname,
        squad_code = squadCode
      ) %>%
      dplyr::left_join(
        team_colours_lookup %>%
          dplyr::rename(
            squad_id = squadId,
            squad_colour = squadColour
          ),
        by = "squad_id"
      ) %>%
      dplyr::distinct(squad_id, .keep_all = TRUE)

    team_stats <- superNetballR::tidyMatch(payload) %>%
      dplyr::filter(stat != "homeTeam") %>%
      dplyr::rename(
        squad_id = squadId,
        squad_name = squadName,
        squad_nickname = squadNickname,
        squad_code = squadCode,
        round_number = round,
        game_number = game
      ) %>%
      dplyr::mutate(
        match_id = match_info$matchId,
        season = entry$season,
        competition_phase = entry$phase,
        competition_id = entry$competition_id,
        value_text = as.character(value),
        value_number = parse_numeric_value(value)
      ) %>%
      dplyr::select(
        match_id,
        season,
        competition_phase,
        competition_id,
        round_number,
        game_number,
        period,
        squad_id,
        squad_name,
        squad_nickname,
        squad_code,
        stat,
        value_text,
        value_number
      )

    player_info <- dplyr::bind_rows(payload$playerInfo$player) %>%
      dplyr::rename(
        player_id = playerId,
        short_display_name = shortDisplayName
      ) %>%
      dplyr::mutate(player_name = trimws(paste(firstname, surname))) %>%
      dplyr::select(
        player_id,
        firstname,
        surname,
        short_display_name,
        player_name
      ) %>%
      dplyr::distinct(player_id, .keep_all = TRUE)

    player_stats <- superNetballR::tidyPlayers(payload) %>%
      dplyr::rename(
        player_id = playerId,
        squad_id = squadId,
        squad_name = squadName,
        short_display_name = shortDisplayName,
        round_number = round,
        game_number = game
      ) %>%
      dplyr::mutate(
        match_id = match_info$matchId,
        season = entry$season,
        competition_phase = entry$phase,
        competition_id = entry$competition_id,
        player_name = trimws(paste(firstname, surname)),
        value_text = as.character(value),
        value_number = parse_numeric_value(value)
      ) %>%
      dplyr::select(
        match_id,
        season,
        competition_phase,
        competition_id,
        round_number,
        game_number,
        period,
        squad_id,
        squad_name,
        player_id,
        player_name,
        short_display_name,
        firstname,
        surname,
        stat,
        value_text,
        value_number
      )

    scores <- team_stats %>%
      dplyr::filter(stat == "goals") %>%
      dplyr::group_by(squad_id) %>%
      dplyr::summarise(score = sum(value_number, na.rm = TRUE), .groups = "drop")

    home_team <- team_info %>%
      dplyr::filter(squad_id == match_info$homeSquadId) %>%
      dplyr::slice_head(n = 1)
    away_team <- team_info %>%
      dplyr::filter(squad_id == match_info$awaySquadId) %>%
      dplyr::slice_head(n = 1)

    match_rows[[index]] <- dplyr::tibble(
      match_id = match_info$matchId,
      season = entry$season,
      competition_phase = entry$phase,
      competition_id = entry$competition_id,
      round_number = match_info$roundNumber,
      game_number = match_info$matchNumber,
      match_type = match_info$matchType %||% NA_character_,
      match_status = match_info$matchStatus %||% NA_character_,
      venue_id = match_info$venueId %||% NA_integer_,
      venue_code = match_info$venueCode %||% NA_character_,
      venue_name = match_info$venueName %||% NA_character_,
      local_start_time = match_info$localStartTime %||% NA_character_,
      utc_start_time = match_info$utcStartTime %||% NA_character_,
      period_completed = match_info$periodCompleted %||% NA_integer_,
      home_squad_id = match_info$homeSquadId,
      away_squad_id = match_info$awaySquadId,
      home_squad_name = first_or_missing(home_team$squad_name, NA_character_),
      away_squad_name = first_or_missing(away_team$squad_name, NA_character_),
      home_score = first_or_missing(
        scores$score[match(match_info$homeSquadId, scores$squad_id)],
        NA_real_
      ),
      away_score = first_or_missing(
        scores$score[match(match_info$awaySquadId, scores$squad_id)],
        NA_real_
      )
    )

    team_rows[[index]] <- team_info
    player_rows[[index]] <- player_info
    team_stat_rows[[index]] <- team_stats
    player_stat_rows[[index]] <- player_stats
  }

  list(
    competitions = competitions %>%
      dplyr::mutate(
        season = as.integer(season),
        competition_id = as.integer(competition_id)
      ),
    matches = dplyr::bind_rows(match_rows) %>%
      dplyr::arrange(season, competition_phase, round_number, game_number),
    teams = dplyr::bind_rows(team_rows) %>%
      dplyr::distinct(squad_id, .keep_all = TRUE) %>%
      dplyr::arrange(squad_name),
    players = dplyr::bind_rows(player_rows) %>%
      dplyr::distinct(player_id, .keep_all = TRUE) %>%
      dplyr::arrange(player_name),
    team_period_stats = dplyr::bind_rows(team_stat_rows),
    player_period_stats = dplyr::bind_rows(player_stat_rows)
  )
}

write_database <- function(tables, db_path, build_mode) {
  dir.create(dirname(db_path), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(db_path)) {
    file.remove(db_path)
  }

  conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  DBI::dbWriteTable(conn, "competitions", tables$competitions, overwrite = TRUE)
  DBI::dbWriteTable(conn, "matches", tables$matches, overwrite = TRUE)
  DBI::dbWriteTable(conn, "teams", tables$teams, overwrite = TRUE)
  DBI::dbWriteTable(conn, "players", tables$players, overwrite = TRUE)
  DBI::dbWriteTable(conn, "team_period_stats", tables$team_period_stats, overwrite = TRUE)
  DBI::dbWriteTable(conn, "player_period_stats", tables$player_period_stats, overwrite = TRUE)

  metadata <- dplyr::tibble(
    key = c("refreshed_at", "build_mode", "season_count", "match_count"),
    value = c(
      format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      build_mode,
      as.character(length(unique(tables$matches$season))),
      as.character(nrow(tables$matches))
    )
  )
  DBI::dbWriteTable(conn, "metadata", metadata, overwrite = TRUE)

  DBI::dbExecute(conn, "CREATE INDEX idx_matches_season_round ON matches(season, round_number, local_start_time)")
  DBI::dbExecute(conn, "CREATE INDEX idx_team_stats_lookup ON team_period_stats(season, squad_id, stat)")
  DBI::dbExecute(conn, "CREATE INDEX idx_player_stats_lookup ON player_period_stats(season, squad_id, player_id, stat)")
  DBI::dbExecute(conn, "CREATE INDEX idx_players_name ON players(player_name)")
}

competitions <- utils::read.csv(config_path, stringsAsFactors = FALSE)
entries <- if (sample_mode) {
  message("Using bundled sample data to build a local demo database.")
  load_sample_entries()
} else {
  collect_live_entries(competitions)
}

if (!length(entries)) {
  stop("No matches were collected. The database was not written.", call. = FALSE)
}

tables <- prepare_match_tables(entries, competitions)
write_database(tables, db_path, if (sample_mode) "sample" else "production")
message(sprintf("Database written to %s with %s matches.", db_path, nrow(tables$matches)))
