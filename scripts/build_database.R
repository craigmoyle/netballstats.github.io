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
        value_text = value,
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
      dplyr::filter(stat == "points") %>%
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

  for (table_name in c("competitions", "matches", "teams", "players", "player_aliases", "team_period_stats", "player_period_stats", "player_match_stats", "player_match_positions", "team_match_stats", "metadata")) {
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
        DEFAULT_TEAM_STATS,
        DEFAULT_PLAYER_STATS
      )
    )
    DBI::dbWriteTable(conn, "metadata", metadata, overwrite = TRUE)

    # matches: unique on match_id for efficient JOIN lookups; season/round for list endpoints
    DBI::dbExecute(conn, "CREATE UNIQUE INDEX idx_matches_match_id ON matches(match_id)")
    DBI::dbExecute(conn, "CREATE INDEX idx_matches_season_round ON matches(season, round_number, local_start_time)")
    # team filter: bitmap-OR of two indexes serves home_squad_id = ? OR away_squad_id = ? predicates
    DBI::dbExecute(conn, "CREATE INDEX idx_matches_home_squad ON matches(home_squad_id)")
    DBI::dbExecute(conn, "CREATE INDEX idx_matches_away_squad ON matches(away_squad_id)")
    # partial index for completed-match queries: fetch_latest_completed_round, fetch_round_matches,
    # fetch_team_points_high, margin_record_badges — avoids full scan of matches on every cache miss
    DBI::dbExecute(conn, paste(
      "CREATE INDEX idx_matches_completed ON matches(season DESC, round_number DESC, local_start_time DESC)",
      "WHERE home_score IS NOT NULL AND away_score IS NOT NULL"
    ))

    # team_period_stats: season/squad/stat for /stats and /trends endpoints
    DBI::dbExecute(conn, "CREATE INDEX idx_team_stats_lookup ON team_period_stats(season, squad_id, stat)")
    # stat-first covering index for archive bests/ranks and game-high queries; INCLUDE avoids heap
    # fetches for squad_name, season, and round_number columns projected in fetch_team_game_high_rows
    DBI::dbExecute(conn, paste(
      "CREATE INDEX idx_team_stats_stat ON team_period_stats(stat, value_number DESC, squad_id, match_id)",
      "INCLUDE (squad_name, season, round_number)"
    ))
    # match_id index speeds up the JOIN with matches in leaderboard queries
    DBI::dbExecute(conn, "CREATE INDEX idx_team_stats_match ON team_period_stats(match_id)")

    # player_period_stats: season/squad/player/stat for filtered leaderboard queries
    DBI::dbExecute(conn, "CREATE INDEX idx_player_stats_lookup ON player_period_stats(season, squad_id, player_id, stat)")
    # stat-first covering index for /query and /game-high endpoints that filter
    # by stat across all seasons; INCLUDE avoids heap lookups for the key columns
    DBI::dbExecute(conn, paste(
      "CREATE INDEX idx_player_stats_stat_cover ON player_period_stats(stat, player_id, match_id)",
      "INCLUDE (season, round_number, squad_id, squad_name, value_number)"
    ))
    # match_id index speeds up the JOIN with matches in game-high and query endpoints
    DBI::dbExecute(conn, "CREATE INDEX idx_player_stats_match ON player_period_stats(match_id)")

    DBI::dbExecute(conn, "CREATE INDEX idx_players_name ON players(player_name)")
    DBI::dbExecute(conn, "CREATE INDEX idx_players_search_name ON players(search_name)")
    DBI::dbExecute(conn, "CREATE INDEX idx_player_aliases_search_name ON player_aliases(alias_search_name, player_id)")
    # pg_trgm GIN indexes for LIKE '%foo%' player search queries — converts full-table scans to
    # sub-millisecond GIN lookups. pg_trgm is pre-loaded on Azure PostgreSQL Flexible Server.
    DBI::dbExecute(conn, "CREATE EXTENSION IF NOT EXISTS pg_trgm")
    DBI::dbExecute(conn, "CREATE INDEX idx_players_search_trgm ON players USING gin(search_name gin_trgm_ops)")
    DBI::dbExecute(conn, "CREATE INDEX idx_player_aliases_search_trgm ON player_aliases USING gin(alias_search_name gin_trgm_ops)")

    # Pre-aggregate period-level stats to match level.  Reduces per-stat row
    # count by ~4x and allows /query and /game-high endpoints to use simple JOINs
    # instead of GROUP BY across period rows — critical on the B1ms server.
    DBI::dbExecute(conn, "DROP TABLE IF EXISTS player_match_stats")
    DBI::dbExecute(conn, paste(
      "CREATE TABLE player_match_stats AS",
      "SELECT stats.player_id, stats.match_id, stats.season, stats.round_number,",
      "  stats.squad_id, MAX(stats.squad_name) AS squad_name, stats.stat,",
      "  ROUND(CAST(SUM(stats.value_number) AS numeric), 2) AS match_value",
      "FROM player_period_stats AS stats",
      "WHERE stats.value_number IS NOT NULL",
      "GROUP BY stats.player_id, stats.match_id, stats.season, stats.round_number, stats.squad_id, stats.stat"
    ))
    # Primary access path: stat filter with top-N sort by match_value
    DBI::dbExecute(conn, "CREATE INDEX idx_pms_stat_value ON player_match_stats(stat, match_value DESC, player_id, match_id)")
    # Player + season lookups (player-leaders, player-season-series)
    DBI::dbExecute(conn, "CREATE INDEX idx_pms_stat_player_season ON player_match_stats(stat, player_id, season, match_id)")
    # Player-profile lookup: index-only scan covering all projected columns for single-player queries
    DBI::dbExecute(conn, paste(
      "CREATE INDEX idx_pms_player ON player_match_stats(player_id)",
      "INCLUDE (match_id, season, squad_name, stat, match_value)",
      "WHERE match_value IS NOT NULL"
    ))
    # Round spotlight batch CTE: season+round filter per stat avoids scanning all historical values
    DBI::dbExecute(conn, paste(
      "CREATE INDEX idx_pms_stat_season_round ON player_match_stats(stat, season, round_number, match_value DESC)",
      "INCLUDE (player_id, squad_name, match_id)",
      "WHERE match_value IS NOT NULL"
    ))

    # Derive per-player per-match starting position from period-level position stats.
    #
    # Primary source: currentPositionCode (reported every period a player is on court).
    # Most common non-bench (not 'I'/'S') currentPositionCode across all periods in a
    # match gives the player's dominant playing role. This is the most reliable source
    # because Champion Data does not consistently report startingPositionCode in all
    # seasons (2022+ coverage is significantly lower than earlier seasons).
    #
    # Override: where startingPositionCode is available for period 1 and is a field
    # position (not 'I'/'S'), it takes precedence — it reflects the coach's deliberate
    # assignment at the start of the quarter.
    DBI::dbExecute(conn, "DROP TABLE IF EXISTS player_match_positions")
    DBI::dbExecute(conn, paste(
      "CREATE TABLE player_match_positions AS",
      "WITH current_dom AS (",
      "  SELECT pps.player_id, pps.match_id, pps.season, pps.round_number, pps.squad_id,",
      "    MAX(pps.squad_name) AS squad_name,",
      "    (SELECT pps2.value_text",
      "     FROM player_period_stats pps2",
      "     WHERE pps2.player_id = pps.player_id AND pps2.match_id = pps.match_id",
      "       AND pps2.stat = 'currentPositionCode'",
      "       AND pps2.value_text NOT IN ('I', 'S', '-')",
      "     GROUP BY pps2.value_text",
      "     ORDER BY COUNT(*) DESC",
      "     LIMIT 1) AS current_position_code",
      "  FROM player_period_stats pps",
      "  WHERE pps.stat = 'currentPositionCode'",
      "  GROUP BY pps.player_id, pps.match_id, pps.season, pps.round_number, pps.squad_id",
      "),",
      "start_code AS (",
      "  SELECT pps.player_id, pps.match_id,",
      "    MAX(CASE WHEN pps.period = 1 THEN pps.value_text END) AS starting_position_code",
      "  FROM player_period_stats pps",
      "  WHERE pps.stat = 'startingPositionCode'",
      "  GROUP BY pps.player_id, pps.match_id",
      ")",
      "SELECT cd.player_id, cd.match_id, cd.season, cd.round_number, cd.squad_id, cd.squad_name,",
      "  COALESCE(",
      "    CASE WHEN sc.starting_position_code NOT IN ('I', 'S', '-')",
      "          AND sc.starting_position_code IS NOT NULL",
      "         THEN sc.starting_position_code END,",
      "    cd.current_position_code",
      "  ) AS starting_position_code",
      "FROM current_dom cd",
      "LEFT JOIN start_code sc",
      "  ON sc.player_id = cd.player_id AND sc.match_id = cd.match_id"
    ))
    # nWAR JOIN access path: player_id + match_id lookup
    DBI::dbExecute(conn, "CREATE INDEX idx_pmp_player_match ON player_match_positions(player_id, match_id)")

    # Derive offensiveRebounds / defensiveRebounds via position heuristic.
    # Champion Data no longer provides these fields; we infer from startingPositionCode:
    #   GS, GA  -> offensiveRebounds (shooting-circle players)
    #   GK, GD  -> defensiveRebounds (defensive-circle players)
    #   C/WA/WD -> unclassified; 0 for both (strict — no arbitrary split)
    DBI::dbExecute(conn, paste(
      "INSERT INTO player_match_stats",
      "  (player_id, match_id, season, round_number, squad_id, squad_name, stat, match_value)",
      "SELECT pms.player_id, pms.match_id, pms.season, pms.round_number,",
      "  pms.squad_id, pms.squad_name, 'offensiveRebounds', pms.match_value",
      "FROM player_match_stats pms",
      "JOIN player_match_positions pmp",
      "  ON pms.player_id = pmp.player_id AND pms.match_id = pmp.match_id",
      "WHERE pms.stat = 'rebounds'",
      "  AND pmp.starting_position_code IN ('GS', 'GA')"
    ))
    DBI::dbExecute(conn, paste(
      "INSERT INTO player_match_stats",
      "  (player_id, match_id, season, round_number, squad_id, squad_name, stat, match_value)",
      "SELECT pms.player_id, pms.match_id, pms.season, pms.round_number,",
      "  pms.squad_id, pms.squad_name, 'defensiveRebounds', pms.match_value",
      "FROM player_match_stats pms",
      "JOIN player_match_positions pmp",
      "  ON pms.player_id = pmp.player_id AND pms.match_id = pmp.match_id",
      "WHERE pms.stat = 'rebounds'",
      "  AND pmp.starting_position_code IN ('GK', 'GD')"
    ))

    # Synthesise deflections = deflectionWithGain + deflectionWithNoGain for seasons
    # where Champion Data only provides the sub-components (e.g. ANZ Championship
    # 2008-2016). The NOT EXISTS guard prevents double-counting for Super Netball
    # seasons that already report the aggregate directly.
    DBI::dbExecute(conn, paste(
      "INSERT INTO player_match_stats",
      "  (player_id, match_id, season, round_number, squad_id, squad_name, stat, match_value)",
      "SELECT gain.player_id, gain.match_id, gain.season, gain.round_number,",
      "  gain.squad_id, gain.squad_name, 'deflections',",
      "  COALESCE(gain.match_value, 0) + COALESCE(nogain.match_value, 0)",
      "FROM player_match_stats gain",
      "LEFT JOIN player_match_stats nogain",
      "  ON gain.player_id = nogain.player_id AND gain.match_id = nogain.match_id",
      "  AND nogain.stat = 'deflectionWithNoGain'",
      "WHERE gain.stat = 'deflectionWithGain'",
      "  AND NOT EXISTS (",
      "    SELECT 1 FROM player_match_stats x",
      "    WHERE x.player_id = gain.player_id AND x.match_id = gain.match_id",
      "      AND x.stat = 'deflections'",
      "  )"
    ))

    # Pre-aggregate period-level team stats to match level. Reduces per-stat row count by ~4x,
    # eliminates GROUP BY in fetch_team_game_high_rows, and enables fast archive-rank range scans
    # analogous to the player_match_stats path.
    DBI::dbExecute(conn, "DROP TABLE IF EXISTS team_match_stats")
    DBI::dbExecute(conn, paste(
      "CREATE TABLE team_match_stats AS",
      "SELECT stats.squad_id, stats.match_id, stats.season, stats.round_number,",
      "  MAX(stats.squad_name) AS squad_name, stats.stat,",
      "  ROUND(CAST(SUM(stats.value_number) AS numeric), 2) AS match_value",
      "FROM team_period_stats AS stats",
      "WHERE stats.value_number IS NOT NULL",
      "GROUP BY stats.squad_id, stats.match_id, stats.season, stats.round_number, stats.stat"
    ))
    DBI::dbExecute(conn, "CREATE INDEX idx_tms_stat_value ON team_match_stats(stat, match_value DESC, squad_id, match_id)")
    DBI::dbExecute(conn, "CREATE INDEX idx_tms_stat_squad_season ON team_match_stats(stat, squad_id, season, match_id)")

    # Synthesise deflections for team_match_stats where only sub-components exist.
    DBI::dbExecute(conn, paste(
      "INSERT INTO team_match_stats",
      "  (squad_id, match_id, season, round_number, squad_name, stat, match_value)",
      "SELECT gain.squad_id, gain.match_id, gain.season, gain.round_number,",
      "  gain.squad_name, 'deflections',",
      "  COALESCE(gain.match_value, 0) + COALESCE(nogain.match_value, 0)",
      "FROM team_match_stats gain",
      "LEFT JOIN team_match_stats nogain",
      "  ON gain.squad_id = nogain.squad_id AND gain.match_id = nogain.match_id",
      "  AND nogain.stat = 'deflectionWithNoGain'",
      "WHERE gain.stat = 'deflectionWithGain'",
      "  AND NOT EXISTS (",
      "    SELECT 1 FROM team_match_stats x",
      "    WHERE x.squad_id = gain.squad_id AND x.match_id = gain.match_id",
      "      AND x.stat = 'deflections'",
      "  )"
    ))

    # Build player_match_participation: one row per player per match where
    # the player actually played at least 1 minute. Two cases:
    #
    # Case 1 (normal): minutesPlayed is properly tracked (>= 1). Used for
    #   Super Netball 2017+ and ANZC 2015-2016 where Champion Data provides
    #   real per-quarter minute values (e.g. 15 min per quarter played).
    #
    # Case 2 (fallback): the entire match has minutesPlayed = 0 for every
    #   player — ANZC 2008-2014 where Champion Data populated the field with
    #   zeros throughout historical seasons. In this case, include any player
    #   who recorded at least one non-zero stat value (they demonstrably played).
    DBI::dbExecute(conn, "DROP TABLE IF EXISTS player_match_participation")
    DBI::dbExecute(conn, paste(
      "CREATE TABLE player_match_participation AS",
      # Case 1: match has real minutesPlayed tracking — use it directly.
      "SELECT player_id, match_id, season, round_number, squad_id, squad_name",
      "FROM player_match_stats",
      "WHERE stat = 'minutesPlayed' AND match_value >= 1",
      "UNION",
      # Case 2: match has no real minutesPlayed data (all zeros for every player).
      # Fall back to: any player with at least one non-zero numeric stat played.
      "SELECT DISTINCT player_id, match_id, season, round_number, squad_id, squad_name",
      "FROM player_match_stats",
      "WHERE match_id NOT IN (",
      "  SELECT DISTINCT match_id FROM player_match_stats",
      "  WHERE stat = 'minutesPlayed' AND match_value >= 1",
      ")",
      "AND stat != 'minutesPlayed'",
      "AND match_value > 0"
    ))
    DBI::dbExecute(conn, "CREATE INDEX idx_pmpart_player_match ON player_match_participation(player_id, match_id)")
    DBI::dbExecute(conn, "CREATE INDEX idx_pmpart_season ON player_match_participation(season, squad_id, player_id)")

    # Synthesise gamesPlayed stat: value 1 per match actually played (>= 1 min).
    # Stored in player_match_stats so it flows through the standard leaderboard pipeline.
    DBI::dbExecute(conn, paste(
      "INSERT INTO player_match_stats",
      "  (player_id, match_id, season, round_number, squad_id, squad_name, stat, match_value)",
      "SELECT player_id, match_id, season, round_number, squad_id, squad_name, 'gamesPlayed', 1",
      "FROM player_match_participation"
    ))

    configure_postgres_api_user(conn)

    # Analyse only our tables (system catalogs require superuser; skip them).
    for (tbl in c("competitions", "matches", "teams", "players", "player_aliases",
                  "team_period_stats", "player_period_stats", "player_match_stats", "player_match_positions",
                  "team_match_stats", "player_match_participation", "metadata")) {
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
