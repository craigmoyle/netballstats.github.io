#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(DBI)
  library(dplyr)
  library(purrr)
  library(superNetballR)
})

script_path <- function() {
  file_arg <- grep("^--file=", commandArgs(), value = TRUE)
  if (!length(file_arg)) {
    return(normalizePath(".", mustWork = FALSE))
  }

  normalizePath(sub("^--file=", "", file_arg[[1]]), mustWork = FALSE)
}

repo_root_path <- normalizePath(file.path(dirname(script_path()), ".."), mustWork = FALSE)
source(file.path(repo_root_path, "R", "database.R"), local = TRUE)
source(file.path(repo_root_path, "api", "R", "helpers.R"), local = TRUE)
config_path <- file.path(repo_root_path, "config", "competitions.csv")
sample_mode <- identical(tolower(Sys.getenv("NETBALL_STATS_SAMPLE", "false")), "true")

if (!nzchar(Sys.getenv("NETBALL_STATS_DB_STATEMENT_TIMEOUT_MS", ""))) {
  Sys.setenv(NETBALL_STATS_DB_STATEMENT_TIMEOUT_MS = "0")
}

parse_numeric_value <- function(value) {
  numeric <- suppressWarnings(as.numeric(as.character(value)))
  ifelse(is.na(numeric), NA_real_, numeric)
}

normalize_player_search_name <- function(value) {
  normalized <- iconv(as.character(value), to = "ASCII//TRANSLIT")
  normalized[is.na(normalized)] <- as.character(value)[is.na(normalized)]
  normalized <- tolower(normalized)
  gsub("[^a-z0-9]+", "", normalized)
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

  player_period_stats <- dplyr::bind_rows(player_stat_rows)
  players <- player_period_stats %>%
    dplyr::filter(!is.na(player_id), !is.na(player_name), nzchar(player_name)) %>%
    dplyr::arrange(player_id, dplyr::desc(season), dplyr::desc(round_number), dplyr::desc(game_number), dplyr::desc(match_id)) %>%
    dplyr::group_by(player_id) %>%
    dplyr::summarise(
      firstname = dplyr::first(firstname),
      surname = dplyr::first(surname),
      short_display_name = dplyr::first(short_display_name),
      player_name = dplyr::first(player_name),
      canonical_name = dplyr::first(player_name),
      search_name = dplyr::first(normalize_player_search_name(player_name)),
      .groups = "drop"
    ) %>%
    dplyr::arrange(canonical_name)

  player_aliases <- player_period_stats %>%
    dplyr::filter(!is.na(player_id), !is.na(player_name), nzchar(player_name)) %>%
    dplyr::transmute(
      player_id = player_id,
      alias_name = player_name,
      alias_search_name = normalize_player_search_name(player_name)
    ) %>%
    dplyr::filter(nzchar(alias_search_name)) %>%
    dplyr::distinct(player_id, alias_name, alias_search_name) %>%
    dplyr::arrange(player_id, alias_name)

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
    players = players,
    player_aliases = player_aliases,
    team_period_stats = dplyr::bind_rows(team_stat_rows),
    player_period_stats = player_period_stats
  )
}

validate_db_identifier <- function(value, name) {
  if (!grepl("^[A-Za-z][A-Za-z0-9_]*$", value)) {
    stop(
      name,
      " must start with a letter and contain only letters, digits, and underscores.",
      call. = FALSE
    )
  }
}

configure_postgres_api_user <- function(conn) {
  api_username <- trimws(Sys.getenv("NETBALL_STATS_API_DB_USERNAME", ""))
  api_password <- Sys.getenv("NETBALL_STATS_API_DB_PASSWORD", "")
  if (!nzchar(api_username) && !nzchar(api_password)) {
    return(invisible(NULL))
  }
  if (!nzchar(api_username) || !nzchar(api_password)) {
    stop(
      "NETBALL_STATS_API_DB_USERNAME and NETBALL_STATS_API_DB_PASSWORD must both be set for PostgreSQL API grants.",
      call. = FALSE
    )
  }

  validate_db_identifier(api_username, "NETBALL_STATS_API_DB_USERNAME")

  quoted_username <- DBI::dbQuoteIdentifier(conn, api_username)
  username_literal <- DBI::dbQuoteString(conn, api_username)
  password_literal <- DBI::dbQuoteString(conn, api_password)
  current_database <- DBI::dbGetQuery(conn, "SELECT current_database() AS db_name")$db_name[[1]]
  quoted_database <- DBI::dbQuoteIdentifier(conn, current_database)

  DBI::dbExecute(
    conn,
    paste0(
      "DO $$ BEGIN ",
      "IF EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = ", username_literal, ") THEN ",
      "ALTER ROLE ", quoted_username, " WITH LOGIN PASSWORD ", password_literal, "; ",
      "ELSE CREATE ROLE ", quoted_username, " LOGIN PASSWORD ", password_literal, "; ",
      "END IF; END $$;"
    )
  )

  DBI::dbExecute(conn, paste0("GRANT CONNECT ON DATABASE ", quoted_database, " TO ", quoted_username))
  DBI::dbExecute(conn, paste0("GRANT USAGE ON SCHEMA public TO ", quoted_username))

  for (table_name in c("competitions", "matches", "teams", "players", "player_aliases", "team_period_stats", "player_period_stats", "metadata")) {
    quoted_table <- DBI::dbQuoteIdentifier(conn, DBI::Id(schema = "public", table = table_name))
    DBI::dbExecute(conn, paste0("GRANT SELECT ON TABLE ", quoted_table, " TO ", quoted_username))
  }

  DBI::dbExecute(
    conn,
    paste0("ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO ", quoted_username)
  )
}

write_database <- function(tables, build_mode) {
  conn <- open_database_connection()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  DBI::dbWithTransaction(conn, {
    DBI::dbWriteTable(conn, "competitions", tables$competitions, overwrite = TRUE)
    DBI::dbWriteTable(conn, "matches", tables$matches, overwrite = TRUE)
    DBI::dbWriteTable(conn, "teams", tables$teams, overwrite = TRUE)
    DBI::dbWriteTable(conn, "players", tables$players, overwrite = TRUE)
    DBI::dbWriteTable(conn, "player_aliases", tables$player_aliases, overwrite = TRUE)
    DBI::dbWriteTable(conn, "team_period_stats", tables$team_period_stats, overwrite = TRUE)
    DBI::dbWriteTable(conn, "player_period_stats", tables$player_period_stats, overwrite = TRUE)

    metadata <- dplyr::bind_rows(
      dplyr::tibble(
      key = c("refreshed_at", "build_mode", "season_count", "match_count"),
      value = c(
        format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
        build_mode,
        as.character(length(unique(tables$matches$season))),
        as.character(nrow(tables$matches))
      )
      ),
      stat_catalog_metadata_entries(
        tables$team_period_stats$stat[!is.na(tables$team_period_stats$value_number)],
        tables$player_period_stats$stat[!is.na(tables$player_period_stats$value_number)]
      )
    )
    DBI::dbWriteTable(conn, "metadata", metadata, overwrite = TRUE)

    # matches: unique on match_id for efficient JOIN lookups; season/round for list endpoints
    DBI::dbExecute(conn, "CREATE UNIQUE INDEX idx_matches_match_id ON matches(match_id)")
    DBI::dbExecute(conn, "CREATE INDEX idx_matches_season_round ON matches(season, round_number, local_start_time)")

    # team_period_stats: season/squad/stat for /stats and /trends endpoints
    DBI::dbExecute(conn, "CREATE INDEX idx_team_stats_lookup ON team_period_stats(season, squad_id, stat)")
    # match_id index speeds up the JOIN with matches in leaderboard queries
    DBI::dbExecute(conn, "CREATE INDEX idx_team_stats_match ON team_period_stats(match_id)")

    # player_period_stats: season/squad/player/stat for filtered leaderboard queries
    DBI::dbExecute(conn, "CREATE INDEX idx_player_stats_lookup ON player_period_stats(season, squad_id, player_id, stat)")
    # stat-first index for /query and /game-high endpoints that filter by stat across all seasons
    DBI::dbExecute(conn, "CREATE INDEX idx_player_stats_stat_season ON player_period_stats(stat, season, player_id)")
    # match_id index speeds up the JOIN with matches in game-high and query endpoints
    DBI::dbExecute(conn, "CREATE INDEX idx_player_stats_match ON player_period_stats(match_id)")

    DBI::dbExecute(conn, "CREATE INDEX idx_players_name ON players(player_name)")
    DBI::dbExecute(conn, "CREATE INDEX idx_players_search_name ON players(search_name)")
    DBI::dbExecute(conn, "CREATE INDEX idx_player_aliases_search_name ON player_aliases(alias_search_name, player_id)")

    configure_postgres_api_user(conn)

    # Analyse only our tables (system catalogs require superuser; skip them).
    for (tbl in c("competitions", "matches", "teams", "players", "player_aliases",
                  "team_period_stats", "player_period_stats", "metadata")) {
      DBI::dbExecute(conn, paste0("ANALYZE ", DBI::dbQuoteIdentifier(conn, tbl)))
    }
  })
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
invisible(write_database(tables, if (sample_mode) "sample" else "production"))
message(sprintf("Database written to %s with %s matches.", database_target_description(), nrow(tables$matches)))
