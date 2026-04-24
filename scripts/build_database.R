#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(DBI)
  library(dplyr)
  library(purrr)
  library(superNetballR)
  library(httr)
  library(jsonlite)
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
source(file.path(repo_root_path, "R", "player_reference.R"), local = TRUE)
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

extract_scoreflow_scores <- function(scoreflow_payload) {
  if (!is.list(scoreflow_payload)) {
    return(NULL)
  }

  score_entries <- scoreflow_payload$score
  if (is.null(score_entries) || length(score_entries) == 0) {
    return(NULL)
  }

  if (!is.list(score_entries)) {
    return(NULL)
  }

  score_entries
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
  score_flow_event_rows <- vector("list", length(entries))
  match_period_duration_rows <- vector("list", length(entries))

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

    # Score flow events -------------------------------------------------------
    # Super Netball (2017+) feeds are known to carry scoreFlow; pre-2017 ANZ
    # Championship feeds are known to omit it.  Absence in a 2017+ match is
    # unexpected and emits a named warning so it is visible in build logs.
    scoreflow_expected <- entry$season >= 2017L

    scoreflow_payload <- payload$scoreFlow
    scoreflow_scores <- extract_scoreflow_scores(scoreflow_payload)

    if (!is.null(scoreflow_payload)) {
      if (!is.list(scoreflow_payload)) {
        if (scoreflow_expected) {
          warning(sprintf(
            "scoreFlow present but malformed for season=%s competition_id=%s round=%s game=%s",
            entry$season, entry$competition_id,
            match_info$roundNumber, match_info$matchNumber
          ))
        }
      } else if (!is.null(scoreflow_scores)) {
        # Well-formed score list: extract events.
        score_flow_event_rows[[index]] <- tryCatch(
          {
            events_df <- dplyr::bind_rows(scoreflow_scores)
            dplyr::transmute(
              events_df,
              match_id      = match_info$matchId,
              season        = entry$season,
              competition_id = entry$competition_id,
              competition_phase = entry$phase,
              round_number  = match_info$roundNumber,
              game_number   = match_info$matchNumber,
              event_seq     = dplyr::row_number(),
              period        = as.integer(period),
              period_seconds = as.integer(periodSeconds),
              squad_id      = as.integer(squadId),
              player_id     = as.integer(playerId),
              distance_code = as.integer(distanceCode),
              position_code = as.integer(positionCode),
              score_points  = as.integer(scorepoints),
              score_name    = as.character(scoreName)
            )
          },
          error = function(e) {
            warning(sprintf(
              "scoreFlow extraction failed for season=%s competition_id=%s round=%s game=%s: %s",
              entry$season, entry$competition_id,
              match_info$roundNumber, match_info$matchNumber,
              conditionMessage(e)
            ))
            NULL
          }
        )
      } else if (scoreflow_expected) {
        # scoreFlow key is present but score list is NULL or empty in a season
        # where events are expected — warn so the gap is visible in build logs.
        warning(sprintf(
          "scoreFlow present but score list is empty for season=%s competition_id=%s round=%s game=%s",
          entry$season, entry$competition_id,
          match_info$roundNumber, match_info$matchNumber
        ))
      }
      # else: pre-2017 feed with empty score list — silently skip (known absent case)
    } else if (scoreflow_expected) {
      # scoreFlow key entirely absent in a season where it is expected.
      warning(sprintf(
        "scoreFlow key missing for season=%s competition_id=%s round=%s game=%s",
        entry$season, entry$competition_id,
        match_info$roundNumber, match_info$matchNumber
      ))
    }
    # else: pre-2017 feed with no scoreFlow key — silently skip (known absent case)

    # Period durations ---------------------------------------------------------
    # Extract actual period clock from periodInfo$qtr so match_lead_state has
    # exact period-end boundaries rather than truncating at the last scoring
    # event.  periodInfo is co-present with scoreFlow in 2017+ feeds.
    if (!is.null(payload$periodInfo) && !is.null(payload$periodInfo$qtr) &&
          length(payload$periodInfo$qtr) > 0) {
      match_period_duration_rows[[index]] <- tryCatch(
        {
          dplyr::bind_rows(payload$periodInfo$qtr) %>%
            dplyr::transmute(
              match_id   = match_info$matchId,
              period     = as.integer(period),
              # periodSeconds in periodInfo = actual clock duration of that period
              period_seconds = as.integer(periodSeconds)
            )
        },
        error = function(e) {
          warning(sprintf(
            "periodInfo extraction failed for season=%s competition_id=%s round=%s game=%s: %s",
            entry$season, entry$competition_id,
            match_info$roundNumber, match_info$matchNumber,
            conditionMessage(e)
          ))
          NULL
        }
      )
    } else if (scoreflow_expected) {
      # periodInfo absent or empty where it is expected — warn so lead-state
      # computations for this match will fall back to the last-score approximation.
      warning(sprintf(
        "periodInfo missing or empty for season=%s competition_id=%s round=%s game=%s",
        entry$season, entry$competition_id,
        match_info$roundNumber, match_info$matchNumber
      ))
    }
    # else: pre-2017 feed — periodInfo not expected, silently skip
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

  match_rows_bound <- dplyr::bind_rows(match_rows)
  reference_rows <- read_player_reference_csv(file.path(repo_root_path, "config", "player_reference.csv"))
  reference_tables <- build_player_reference_tables(
    players,
    player_period_stats,
    dplyr::mutate(match_rows_bound, match_date = as.Date(substr(dplyr::coalesce(local_start_time, utc_start_time), 1, 10))),
    reference_rows
  )

  list(
    competitions = competitions %>%
      dplyr::mutate(
        season = as.integer(season),
        competition_id = as.integer(competition_id)
      ),
    matches = match_rows_bound %>%
      dplyr::arrange(season, competition_phase, round_number, game_number),
    teams = dplyr::bind_rows(team_rows) %>%
      dplyr::distinct(squad_id, .keep_all = TRUE) %>%
      dplyr::arrange(squad_name),
    players = players,
    player_aliases = player_aliases,
    team_period_stats = dplyr::bind_rows(team_stat_rows),
    player_period_stats = player_period_stats,
    score_flow_events = dplyr::bind_rows(score_flow_event_rows),
    match_period_durations = dplyr::bind_rows(match_period_duration_rows),
    player_reference = reference_tables$player_reference,
    player_season_demographics = reference_tables$player_season_demographics,
    league_composition_summary = reference_tables$league_composition_summary,
    league_composition_debut_bands = reference_tables$league_composition_debut_bands
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

  for (table_name in c("competitions", "matches", "teams", "players", "player_aliases", "team_period_stats", "player_period_stats", "player_match_stats", "player_match_positions", "team_match_stats", "home_venue_impact_rows", "home_venue_breakdown_rows", "score_flow_events", "match_period_durations", "match_lead_state", "match_scoreflow_summary", "player_reference", "player_season_demographics", "league_composition_summary", "league_composition_debut_bands", "metadata")) {
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
    DBI::dbWriteTable(conn, "player_reference", tables$player_reference, overwrite = TRUE)
    DBI::dbWriteTable(conn, "player_season_demographics", tables$player_season_demographics, overwrite = TRUE)
    DBI::dbWriteTable(conn, "league_composition_summary", tables$league_composition_summary, overwrite = TRUE)
    DBI::dbWriteTable(conn, "league_composition_debut_bands", tables$league_composition_debut_bands, overwrite = TRUE)
    DBI::dbWriteTable(conn, "score_flow_events", tables$score_flow_events, overwrite = TRUE)
    # Actual period clock durations from periodInfo — used by match_lead_state to
    # determine exact period-end boundaries so lead/tied seconds are not truncated
    # at the timestamp of the last scoring event in each period.
    DBI::dbWriteTable(conn, "match_period_durations", tables$match_period_durations, overwrite = TRUE)

    # Index score_flow_events for time-ordered event lookups per match.
    DBI::dbExecute(conn, "CREATE INDEX idx_sfe_match_period ON score_flow_events(match_id, period, period_seconds)")

    # Derive match_lead_state: per-match running-score lead summary.
    #
    # Period boundaries come from match_period_durations (actual clock from
    # periodInfo), so the full period duration is counted rather than truncating
    # at the last scoring event.  For matches where periodInfo was absent (e.g.
    # pre-2017 seasons), the query falls back to MAX(period_seconds) from
    # score_flow_events — imprecise but visible via warnings emitted at extract
    # time.  Both paths are explicit in the period_maxes CTE.
    #
    # Includes one row for EVERY match (LEFT JOIN from matches), with 0 for all
    # metrics where no score_flow_events data exists.
    #
    # Lead changes: counts transitions between home-leading and away-leading
    # states; tied intervals are skipped when identifying the previous leader
    # so a home→tied→away sequence counts as exactly one lead change.
    DBI::dbExecute(conn, "DROP TABLE IF EXISTS match_lead_state")
    DBI::dbExecute(conn, paste(
      "CREATE TABLE match_lead_state AS",
      "WITH period_maxes AS (",
      "  -- Primary: actual period clock from periodInfo (exact period-end boundary).",
      "  SELECT match_id, period, period_seconds AS period_max_sec",
      "  FROM match_period_durations",
      "  UNION ALL",
      "  -- Fallback: MAX observed scoring timestamp when periodInfo was absent.",
      "  -- Undercounts by the dead time after the last goal in each period.",
      "  -- Triggered per (match_id, period) missing from match_period_durations.",
      "  -- Covers pre-2017 matches (no periodInfo at all) and any partially-covered match.",
      "  SELECT sfe.match_id, sfe.period, MAX(sfe.period_seconds) AS period_max_sec",
      "  FROM score_flow_events sfe",
      "  WHERE NOT EXISTS (",
      "    SELECT 1 FROM match_period_durations mpd",
      "    WHERE mpd.match_id = sfe.match_id AND mpd.period = sfe.period",
      "  )",
      "  GROUP BY sfe.match_id, sfe.period",
      "),",
      "period_offsets AS (",
      "  SELECT match_id, period,",
      "    COALESCE(SUM(period_max_sec) OVER (",
      "      PARTITION BY match_id ORDER BY period",
      "      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING",
      "    ), 0) AS period_offset_sec,",
      "    SUM(period_max_sec) OVER (PARTITION BY match_id) AS match_total_sec",
      "  FROM period_maxes",
      "),",
      "period_events AS (",
      "  SELECT sfe.match_id, m.home_squad_id, sfe.event_seq,",
      "    po.period_offset_sec + sfe.period_seconds AS match_seconds,",
      "    po.match_total_sec,",
      "    sfe.squad_id, sfe.score_points",
      "  FROM score_flow_events sfe",
      "  JOIN matches m ON m.match_id = sfe.match_id",
      "  JOIN period_offsets po ON po.match_id = sfe.match_id AND po.period = sfe.period",
      "),",
      "running_score AS (",
      "  SELECT match_id, event_seq, match_seconds, match_total_sec,",
      "    SUM(CASE WHEN squad_id = home_squad_id THEN score_points ELSE 0 END)",
      "      OVER (PARTITION BY match_id ORDER BY event_seq",
      "            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS home_score,",
      "    SUM(CASE WHEN squad_id != home_squad_id THEN score_points ELSE 0 END)",
      "      OVER (PARTITION BY match_id ORDER BY event_seq",
      "            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS away_score",
      "  FROM period_events",
      "),",
      "with_margin AS (",
      "  SELECT match_id, event_seq,",
      "    match_seconds AS state_from,",
      "    home_score - away_score AS margin,",
      "    COALESCE(",
      "      LEAD(match_seconds) OVER (PARTITION BY match_id ORDER BY event_seq),",
      "      match_total_sec",
      "    ) AS state_to",
      "  FROM running_score",
      "),",
      "all_states AS (",
      "  -- Synthetic pre-match tied state (event_seq=0, always before real events).",
      "  SELECT match_id, 0 AS margin, 0 AS state_from, MIN(state_from) AS state_to, 0 AS event_seq",
      "  FROM with_margin",
      "  GROUP BY match_id",
      "  UNION ALL",
      "  SELECT match_id, margin, state_from, state_to, event_seq",
      "  FROM with_margin",
      "),",
      "lead_changes_cte AS (",
      "  SELECT match_id, COUNT(*) AS lead_changes",
      "  FROM (",
      "    SELECT match_id, SIGN(margin) AS lead_sign,",
      "      -- Order by (state_from, event_seq) so concurrent-second events are stable.",
      "      LAG(SIGN(margin)) OVER (PARTITION BY match_id ORDER BY state_from, event_seq) AS prev_lead_sign",
      "    FROM all_states",
      "    WHERE margin != 0",
      "  ) t",
      "  WHERE prev_lead_sign IS NOT NULL",
      "    AND lead_sign != prev_lead_sign",
      "  GROUP BY match_id",
      "),",
      "match_summary AS (",
      "  SELECT",
      "    s.match_id,",
      "    SUM(CASE WHEN s.margin > 0 THEN GREATEST(s.state_to - s.state_from, 0) ELSE 0 END)::integer AS home_seconds_leading,",
      "    SUM(CASE WHEN s.margin < 0 THEN GREATEST(s.state_to - s.state_from, 0) ELSE 0 END)::integer AS away_seconds_leading,",
      "    SUM(CASE WHEN s.margin = 0 THEN GREATEST(s.state_to - s.state_from, 0) ELSE 0 END)::integer AS tied_seconds,",
      "    COALESCE(MAX(CASE WHEN s.margin < 0 THEN -s.margin END), 0)::integer AS home_deepest_deficit,",
      "    COALESCE(MAX(CASE WHEN s.margin > 0 THEN s.margin END), 0)::integer AS away_deepest_deficit,",
      "    COALESCE(MAX(lc.lead_changes), 0)::integer AS lead_changes",
      "  FROM all_states s",
      "  LEFT JOIN lead_changes_cte lc ON lc.match_id = s.match_id",
      "  GROUP BY s.match_id",
      ")",
      "SELECT",
      "  m.match_id,",
      "  COALESCE(ms.home_seconds_leading, 0)::integer AS home_seconds_leading,",
      "  COALESCE(ms.away_seconds_leading, 0)::integer AS away_seconds_leading,",
      "  COALESCE(ms.tied_seconds, 0)::integer AS tied_seconds,",
      "  COALESCE(ms.home_deepest_deficit, 0)::integer AS home_deepest_deficit,",
      "  COALESCE(ms.away_deepest_deficit, 0)::integer AS away_deepest_deficit,",
      "  COALESCE(ms.lead_changes, 0)::integer AS lead_changes",
      "FROM matches m",
      "LEFT JOIN match_summary ms ON ms.match_id = m.match_id",
      sep = "\n"
    ))
    DBI::dbExecute(conn, "CREATE INDEX idx_mls_match_id ON match_lead_state(match_id)")

    # Guard: every match with score events must produce positive total time in
    # match_lead_state.  Zero total time despite having events means the
    # period_offsets JOIN silently dropped all events — which can happen if the
    # NOT EXISTS fallback in period_maxes is gated per-match instead of per-period.
    mls_zero_time <- DBI::dbGetQuery(conn, paste(
      "SELECT COUNT(*) AS count",
      "FROM (SELECT DISTINCT match_id FROM score_flow_events) sfe",
      "JOIN match_lead_state mls ON mls.match_id = sfe.match_id",
      "WHERE mls.home_seconds_leading + mls.away_seconds_leading + mls.tied_seconds = 0"
    ))
    if (mls_zero_time$count > 0) {
      stop(sprintf(
        paste(
          "match_lead_state invariant: %d match(es) have score events but",
          "total time = 0 — events were dropped during period offset JOIN.",
          "Check the per-period NOT EXISTS clause in the period_maxes CTE."
        ),
        as.integer(mls_zero_time$count)
      ))
    }

    # Derive match_scoreflow_summary: per-team-per-match analytics layer.
    #
    # Provides one row per (team, match) for every completed match, giving later
    # API endpoints a stable, pre-computed surface for scoreflow-derived metrics
    # without re-reading raw score events.
    #
    # Metric semantics (explicit, not implicit):
    #
    #   seconds_leading / seconds_trailing / seconds_tied
    #     Time (in seconds) this team spent leading, trailing, or level during
    #     the match, derived from match_lead_state (which uses the home_score -
    #     away_score margin convention).  The three values always sum to
    #     match_total_seconds for rows with scoreflow coverage.
    #
    #   match_total_seconds
    #     Total timed match duration from match_lead_state
    #     (home_seconds_leading + away_seconds_leading + tied_seconds).
    #     0 for matches without scoreflow coverage.
    #
    #   largest_lead_points
    #     Maximum positive margin this team achieved at any moment during the
    #     match.  0 if the team never led.  For the home team this equals
    #     away_deepest_deficit in match_lead_state; for the away team it equals
    #     home_deepest_deficit (the margin viewed from the other side).
    #
    #   deepest_deficit_points
    #     Absolute magnitude of the worst negative margin this team faced.
    #     0 if the team was never behind.  For the home team this is
    #     home_deepest_deficit; for the away team, away_deepest_deficit.
    #
    #   lead_changes
    #     Match-level lead-change count from match_lead_state.  Symmetric:
    #     identical for both teams in a match.  Counts transitions between
    #     home-leading and away-leading states; tied intervals do not reset
    #     the previous leader (home→tied→away = one change).
    #
    #   match_has_scoreflow
    #     1 when match_total_seconds > 0 (timing data present), else 0.
    #     Pre-2017 ANZ Championship matches without scoreFlow events score 0.
    #     All derived flag and ratio columns are NULL when this is 0.
    #
    #   trailing_share
    #     seconds_trailing / match_total_seconds, rounded to 4 dp.
    #     NULL for no-scoreflow matches (denominator is 0; result is undefined).
    #
    #   trailed_most_of_match
    #     1 when seconds_trailing > match_total_seconds / 2 (strictly more than
    #     half the match spent trailing).  0 otherwise.  NULL for no-scoreflow
    #     matches.  The 50% threshold is an explicit design choice; it excludes
    #     teams that trailed for exactly half the match.
    #
    #   comeback_win
    #     1 when won = 1 AND deepest_deficit_points > 0.  Broad definition:
    #     any win where the team was ever behind by at least 1 point, regardless
    #     of how long they trailed.  NULL for no-scoreflow matches (a deficit of
    #     0 is ambiguous without timing data).
    #
    #   won_trailing_most
    #     Explicit combined analytic: 1 when won = 1 AND seconds_trailing >
    #     match_total_seconds / 2.  Encodes "won after trailing for most of the
    #     match" as a single stable field rather than requiring downstream code
    #     to recombine won + trailed_most_of_match.  NULL for no-scoreflow
    #     matches.  Uses the same strict 50% threshold as trailed_most_of_match.
    #
    #   comeback_deficit_points
    #     Explicit combined analytic: the size of the deficit overcome in a
    #     winning comeback.  Equals deepest_deficit_points when comeback_win = 1,
    #     else 0.  NULL for no-scoreflow matches.  Encodes "biggest comeback win"
    #     as a single rankable/filterable field — downstream callers do not need
    #     to join comeback_win and deepest_deficit_points to rank or filter on
    #     comeback magnitude.
    DBI::dbExecute(conn, "DROP TABLE IF EXISTS match_scoreflow_summary")
    DBI::dbExecute(conn, paste(
      "CREATE TABLE match_scoreflow_summary AS",
      "WITH base AS (",
      # Home team perspective: positive margin = home leading.
      "  SELECT",
      "    m.match_id, m.season, m.competition_id,",
      "    COALESCE(m.competition_phase, '') AS competition_phase,",
      "    m.round_number, m.game_number,",
      "    m.home_squad_id AS squad_id,",
      "    m.away_squad_id AS opponent_id,",
      "    1::integer AS is_home,",
      "    CASE WHEN m.home_score > m.away_score THEN 1 ELSE 0 END::integer AS won,",
      "    COALESCE(mls.home_seconds_leading, 0)::integer AS seconds_leading,",
      "    COALESCE(mls.away_seconds_leading, 0)::integer AS seconds_trailing,",
      "    COALESCE(mls.tied_seconds, 0)::integer AS seconds_tied,",
      "    (COALESCE(mls.home_seconds_leading, 0) +",
      "     COALESCE(mls.away_seconds_leading, 0) +",
      "     COALESCE(mls.tied_seconds, 0))::integer AS match_total_seconds,",
      # Home largest lead = how far ahead home got = away's deepest deficit.
      "    COALESCE(mls.away_deepest_deficit, 0)::integer AS largest_lead_points,",
      # Home deepest deficit = how far behind home got.
      "    COALESCE(mls.home_deepest_deficit, 0)::integer AS deepest_deficit_points,",
      "    COALESCE(mls.lead_changes, 0)::integer AS lead_changes",
      "  FROM matches m",
      "  LEFT JOIN match_lead_state mls ON mls.match_id = m.match_id",
      "  WHERE m.home_score IS NOT NULL AND m.away_score IS NOT NULL",
      "  UNION ALL",
      # Away team perspective: negative margin (from home view) = away leading.
      "  SELECT",
      "    m.match_id, m.season, m.competition_id,",
      "    COALESCE(m.competition_phase, '') AS competition_phase,",
      "    m.round_number, m.game_number,",
      "    m.away_squad_id AS squad_id,",
      "    m.home_squad_id AS opponent_id,",
      "    0::integer AS is_home,",
      "    CASE WHEN m.away_score > m.home_score THEN 1 ELSE 0 END::integer AS won,",
      "    COALESCE(mls.away_seconds_leading, 0)::integer AS seconds_leading,",
      "    COALESCE(mls.home_seconds_leading, 0)::integer AS seconds_trailing,",
      "    COALESCE(mls.tied_seconds, 0)::integer AS seconds_tied,",
      "    (COALESCE(mls.home_seconds_leading, 0) +",
      "     COALESCE(mls.away_seconds_leading, 0) +",
      "     COALESCE(mls.tied_seconds, 0))::integer AS match_total_seconds,",
      # Away largest lead = how far ahead away got = home's deepest deficit.
      "    COALESCE(mls.home_deepest_deficit, 0)::integer AS largest_lead_points,",
      # Away deepest deficit = how far behind away got.
      "    COALESCE(mls.away_deepest_deficit, 0)::integer AS deepest_deficit_points,",
      "    COALESCE(mls.lead_changes, 0)::integer AS lead_changes",
      "  FROM matches m",
      "  LEFT JOIN match_lead_state mls ON mls.match_id = m.match_id",
      "  WHERE m.home_score IS NOT NULL AND m.away_score IS NOT NULL",
      ")",
      "SELECT",
      "  match_id, season, competition_id, competition_phase,",
      "  round_number, game_number, squad_id, opponent_id,",
      "  is_home, won,",
      "  seconds_leading, seconds_trailing, seconds_tied, match_total_seconds,",
      "  largest_lead_points, deepest_deficit_points, lead_changes,",
      # match_has_scoreflow: 1 when real timing data is present.
      "  CASE WHEN match_total_seconds > 0 THEN 1 ELSE 0 END::integer AS match_has_scoreflow,",
      # trailing_share: fraction of match time spent trailing; NULL without timing data.
      "  CASE WHEN match_total_seconds > 0",
      "       THEN ROUND(seconds_trailing::numeric / match_total_seconds, 4)",
      "       ELSE NULL END AS trailing_share,",
      # trailed_most_of_match: strictly more than 50% of match time trailing.
      "  CASE WHEN match_total_seconds > 0",
      "       THEN (CASE WHEN seconds_trailing > match_total_seconds / 2.0 THEN 1 ELSE 0 END)::integer",
      "       ELSE NULL END AS trailed_most_of_match,",
      # comeback_win: won despite ever being behind (broad: any deficit > 0).
      "  CASE WHEN match_total_seconds > 0",
      "       THEN (CASE WHEN won = 1 AND deepest_deficit_points > 0 THEN 1 ELSE 0 END)::integer",
      "       ELSE NULL END AS comeback_win,",
      # won_trailing_most: explicit combined field — won after trailing > half the match.
      # Stable single-column equivalent of (won = 1 AND trailed_most_of_match = 1).
      "  CASE WHEN match_total_seconds > 0",
      "       THEN (CASE WHEN won = 1 AND seconds_trailing > match_total_seconds / 2.0 THEN 1 ELSE 0 END)::integer",
      "       ELSE NULL END AS won_trailing_most,",
      # comeback_deficit_points: explicit comeback-size field for ranking and filtering.
      # deepest_deficit_points when comeback_win = 1 (won with any deficit), else 0.
      # Encodes the "biggest comeback win" basis without requiring downstream recombination.
      "  CASE WHEN match_total_seconds > 0",
      "       THEN (CASE WHEN won = 1 AND deepest_deficit_points > 0 THEN deepest_deficit_points ELSE 0 END)::integer",
      "       ELSE NULL END AS comeback_deficit_points",
      "FROM base"
    ))
    DBI::dbExecute(conn, "CREATE INDEX idx_mss_squad_season ON match_scoreflow_summary(squad_id, season, match_id)")
    DBI::dbExecute(conn, "CREATE INDEX idx_mss_match_id ON match_scoreflow_summary(match_id, squad_id)")
    # Partial indexes for comeback/trailed-most queries — only cover rows with real data.
    DBI::dbExecute(conn, paste(
      "CREATE INDEX idx_mss_comeback ON match_scoreflow_summary(season, squad_id)",
      "WHERE comeback_win = 1"
    ))
    DBI::dbExecute(conn, paste(
      "CREATE INDEX idx_mss_trailed_most ON match_scoreflow_summary(season, squad_id)",
      "WHERE trailed_most_of_match = 1"
    ))
    DBI::dbExecute(conn, paste(
      "CREATE INDEX idx_mss_won_trailing_most ON match_scoreflow_summary(season, squad_id)",
      "WHERE won_trailing_most = 1"
    ))
    # comeback_deficit_points: range index for ranking biggest comebacks across seasons.
    DBI::dbExecute(conn, paste(
      "CREATE INDEX idx_mss_comeback_deficit ON match_scoreflow_summary(comeback_deficit_points DESC, season, squad_id)",
      "WHERE comeback_deficit_points > 0"
    ))

    # Build-time sanity checks for match_scoreflow_summary.
    mss_check <- DBI::dbGetQuery(conn, paste(
      "SELECT",
      "  COUNT(*) AS total_rows,",
      "  SUM(CASE WHEN match_has_scoreflow = 1 THEN 1 ELSE 0 END) AS scoreflow_rows,",
      # Each time component must not exceed match_total_seconds (catches sign-flip/overflow).
      "  SUM(CASE WHEN seconds_leading > match_total_seconds",
      "            OR seconds_trailing > match_total_seconds",
      "            OR seconds_tied > match_total_seconds",
      "            THEN 1 ELSE 0 END) AS time_component_overflow_rows,",
      # Comeback wins must have won=1 and a deficit.
      "  SUM(CASE WHEN comeback_win = 1 AND (won != 1 OR deepest_deficit_points <= 0)",
      "            THEN 1 ELSE 0 END) AS comeback_win_invalid_rows,",
      # trailed_most=1 must imply trailing > half the match.
      "  SUM(CASE WHEN trailed_most_of_match = 1",
      "            AND seconds_trailing <= match_total_seconds / 2.0",
      "            THEN 1 ELSE 0 END) AS trailed_most_invalid_rows,",
      # won_trailing_most=1 must imply both won=1 and trailing > half the match.
      "  SUM(CASE WHEN won_trailing_most = 1 AND (won != 1 OR seconds_trailing <= match_total_seconds / 2.0)",
      "            THEN 1 ELSE 0 END) AS won_trailing_most_invalid_rows,",
      # comeback_deficit_points must equal deepest_deficit_points when comeback_win=1,
      # and must be 0 when comeback_win=0 (for scoreflow rows).
      "  SUM(CASE WHEN match_has_scoreflow = 1",
      "            AND comeback_win = 1 AND comeback_deficit_points != deepest_deficit_points",
      "            THEN 1 ELSE 0 END) AS comeback_deficit_mismatch_rows,",
      "  SUM(CASE WHEN match_has_scoreflow = 1",
      "            AND COALESCE(comeback_win, 0) = 0 AND COALESCE(comeback_deficit_points, 0) != 0",
      "            THEN 1 ELSE 0 END) AS comeback_deficit_nonzero_when_no_win_rows,",
      # No negative values in any time or deficit column.
      "  SUM(CASE WHEN seconds_leading < 0 OR seconds_trailing < 0",
      "            OR seconds_tied < 0 OR largest_lead_points < 0",
      "            OR deepest_deficit_points < 0 THEN 1 ELSE 0 END) AS negative_value_rows",
      "FROM match_scoreflow_summary"
    ))
    # Accumulate all invariant violations and stop() once — inside dbWithTransaction,
    # a stop() rolls back the entire write so a corrupt table is never published.
    mss_violations <- character(0)
    if (mss_check$time_component_overflow_rows > 0) {
      mss_violations <- c(mss_violations, sprintf(
        "%d rows where a time component (seconds_leading/trailing/tied) exceeds match_total_seconds",
        as.integer(mss_check$time_component_overflow_rows)
      ))
    }
    if (mss_check$comeback_win_invalid_rows > 0) {
      mss_violations <- c(mss_violations, sprintf(
        "%d rows with comeback_win=1 but won!=1 or deepest_deficit_points<=0",
        as.integer(mss_check$comeback_win_invalid_rows)
      ))
    }
    if (mss_check$trailed_most_invalid_rows > 0) {
      mss_violations <- c(mss_violations, sprintf(
        "%d rows with trailed_most_of_match=1 but seconds_trailing <= match_total_seconds/2",
        as.integer(mss_check$trailed_most_invalid_rows)
      ))
    }
    if (mss_check$won_trailing_most_invalid_rows > 0) {
      mss_violations <- c(mss_violations, sprintf(
        "%d rows with won_trailing_most=1 but won!=1 or seconds_trailing <= match_total_seconds/2",
        as.integer(mss_check$won_trailing_most_invalid_rows)
      ))
    }
    if (mss_check$comeback_deficit_mismatch_rows > 0) {
      mss_violations <- c(mss_violations, sprintf(
        "%d rows where comeback_deficit_points != deepest_deficit_points when comeback_win=1",
        as.integer(mss_check$comeback_deficit_mismatch_rows)
      ))
    }
    if (mss_check$comeback_deficit_nonzero_when_no_win_rows > 0) {
      mss_violations <- c(mss_violations, sprintf(
        "%d rows with comeback_deficit_points > 0 but comeback_win != 1",
        as.integer(mss_check$comeback_deficit_nonzero_when_no_win_rows)
      ))
    }
    if (mss_check$negative_value_rows > 0) {
      mss_violations <- c(mss_violations, sprintf(
        "%d rows with negative timing or deficit values",
        as.integer(mss_check$negative_value_rows)
      ))
    }
    if (length(mss_violations) > 0) {
      stop(
        "match_scoreflow_summary invariant failures — aborting build:\n  ",
        paste(mss_violations, collapse = "\n  "),
        call. = FALSE
      )
    }
    message(sprintf(
      "match_scoreflow_summary built: %d rows (%d with scoreflow coverage).",
      as.integer(mss_check$total_rows),
      as.integer(mss_check$scoreflow_rows)
    ))

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
    # nWAR season-scoped aggregates filter by season without a leading stat
    # column, so keep a season-first index available for those lookups.
    DBI::dbExecute(conn, "CREATE INDEX idx_pms_season_player ON player_match_stats(season, player_id, match_id)")

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
      "WITH current_rows AS (",
      "  SELECT pps.player_id, pps.match_id, pps.season, pps.round_number, pps.squad_id,",
      "    MAX(pps.squad_name) AS squad_name",
      "  FROM player_period_stats pps",
      "  WHERE pps.stat = 'currentPositionCode'",
      "  GROUP BY pps.player_id, pps.match_id, pps.season, pps.round_number, pps.squad_id",
      "),",
      "current_counts AS (",
      "  SELECT pps.player_id, pps.match_id, pps.value_text AS current_position_code,",
      "    COUNT(*) AS position_count",
      "  FROM player_period_stats pps",
      "  WHERE pps.stat = 'currentPositionCode'",
      "    AND pps.value_text NOT IN ('I', 'S', '-')",
      "  GROUP BY pps.player_id, pps.match_id, pps.value_text",
      "),",
      "current_ranked AS (",
      "  SELECT current_counts.*,",
      "    ROW_NUMBER() OVER (",
      "      PARTITION BY current_counts.player_id, current_counts.match_id",
      "      ORDER BY current_counts.position_count DESC, current_counts.current_position_code ASC",
      "    ) AS rn",
      "  FROM current_counts",
      "),",
      "current_dom AS (",
      "  SELECT cr.player_id, cr.match_id, cr.season, cr.round_number, cr.squad_id, cr.squad_name,",
      "    current_ranked.current_position_code",
      "  FROM current_rows cr",
      "  LEFT JOIN current_ranked",
      "    ON current_ranked.player_id = cr.player_id",
      "   AND current_ranked.match_id = cr.match_id",
      "   AND current_ranked.rn = 1",
      "),",
      "start_code AS (",
      "  SELECT pps.player_id, pps.match_id,",
      "    MAX(CASE",
      "      WHEN pps.period = 1 AND pps.value_text NOT IN ('I', 'S', '-') THEN pps.value_text",
      "    END) AS starting_position_code",
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
    DBI::dbExecute(conn, "CREATE INDEX idx_pmp_season_player ON player_match_positions(season, player_id)")

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

    DBI::dbExecute(conn, "DROP TABLE IF EXISTS home_venue_impact_rows")
    DBI::dbExecute(conn, paste(
      "CREATE TABLE home_venue_impact_rows AS",
      "SELECT matches.match_id, matches.season, COALESCE(matches.competition_phase, '') AS competition_phase,",
      "  matches.round_number, matches.venue_name,",
      "  matches.home_squad_id AS team_id, matches.home_squad_name AS team_name,",
      "  matches.away_squad_id AS opponent_id, matches.away_squad_name AS opponent_name,",
      "  1 AS is_home,",
      "  matches.home_score AS team_score, matches.away_score AS opponent_score,",
      "  matches.home_score - matches.away_score AS margin,",
      "  CASE WHEN matches.home_score > matches.away_score THEN 1 ELSE 0 END AS won,",
      "  CASE WHEN matches.home_score = matches.away_score THEN 1 ELSE 0 END AS draw,",
      "  COALESCE(home_pen.match_value, 0) AS penalties_for,",
      "  COALESCE(away_pen.match_value, 0) AS penalties_against,",
      "  COALESCE(away_pen.match_value, 0) - COALESCE(home_pen.match_value, 0) AS penalty_advantage",
      "FROM matches",
      "LEFT JOIN team_match_stats home_pen",
      "  ON home_pen.match_id = matches.match_id",
      "  AND home_pen.squad_id = matches.home_squad_id",
      "  AND home_pen.stat = 'penalties'",
      "LEFT JOIN team_match_stats away_pen",
      "  ON away_pen.match_id = matches.match_id",
      "  AND away_pen.squad_id = matches.away_squad_id",
      "  AND away_pen.stat = 'penalties'",
      "WHERE matches.home_score IS NOT NULL AND matches.away_score IS NOT NULL",
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
      "  COALESCE(away_pen.match_value, 0) AS penalties_for,",
      "  COALESCE(home_pen.match_value, 0) AS penalties_against,",
      "  COALESCE(home_pen.match_value, 0) - COALESCE(away_pen.match_value, 0) AS penalty_advantage",
      "FROM matches",
      "LEFT JOIN team_match_stats home_pen",
      "  ON home_pen.match_id = matches.match_id",
      "  AND home_pen.squad_id = matches.home_squad_id",
      "  AND home_pen.stat = 'penalties'",
      "LEFT JOIN team_match_stats away_pen",
      "  ON away_pen.match_id = matches.match_id",
      "  AND away_pen.squad_id = matches.away_squad_id",
      "  AND away_pen.stat = 'penalties'",
      "WHERE matches.home_score IS NOT NULL AND matches.away_score IS NOT NULL"
    ))
    DBI::dbExecute(conn, "CREATE INDEX idx_hvir_team_season_venue ON home_venue_impact_rows(team_id, season, venue_name, is_home)")
    DBI::dbExecute(conn, "CREATE INDEX idx_hvir_venue_season ON home_venue_impact_rows(venue_name, season, is_home)")

    DBI::dbExecute(conn, "DROP TABLE IF EXISTS home_venue_breakdown_rows")
    DBI::dbExecute(conn, paste(
      "CREATE TABLE home_venue_breakdown_rows AS",
      "SELECT matches.match_id, matches.season, COALESCE(matches.competition_phase, '') AS competition_phase,",
      "  matches.round_number, matches.venue_name,",
      "  matches.home_squad_id AS team_id, matches.home_squad_name AS team_name,",
      "  matches.away_squad_id AS opponent_id, matches.away_squad_name AS opponent_name,",
      "  matches.home_score AS team_score, matches.away_score AS opponent_score,",
      "  matches.home_score - matches.away_score AS margin,",
      "  CASE WHEN matches.home_score > matches.away_score THEN 1 ELSE 0 END AS won,",
      "  CASE WHEN matches.home_score = matches.away_score THEN 1 ELSE 0 END AS draw,",
      "  COALESCE(gpt.match_value, 0) AS generalPlayTurnovers,",
      "  COALESCE(held.match_value, 0) AS turnoverHeld,",
      "  COALESCE(contact.match_value, 0) AS contactPenalties,",
      "  COALESCE(obstruction.match_value, 0) AS obstructionPenalties,",
      "  COALESCE(penalties.match_value, 0) AS penalties",
      "FROM matches",
      "LEFT JOIN team_match_stats gpt",
      "  ON gpt.match_id = matches.match_id",
      "  AND gpt.squad_id = matches.home_squad_id",
      "  AND gpt.stat = 'generalPlayTurnovers'",
      "LEFT JOIN team_match_stats held",
      "  ON held.match_id = matches.match_id",
      "  AND held.squad_id = matches.home_squad_id",
      "  AND held.stat = 'turnoverHeld'",
      "LEFT JOIN team_match_stats contact",
      "  ON contact.match_id = matches.match_id",
      "  AND contact.squad_id = matches.home_squad_id",
      "  AND contact.stat = 'contactPenalties'",
      "LEFT JOIN team_match_stats obstruction",
      "  ON obstruction.match_id = matches.match_id",
      "  AND obstruction.squad_id = matches.home_squad_id",
      "  AND obstruction.stat = 'obstructionPenalties'",
      "LEFT JOIN team_match_stats penalties",
      "  ON penalties.match_id = matches.match_id",
      "  AND penalties.squad_id = matches.home_squad_id",
      "  AND penalties.stat = 'penalties'",
      "WHERE matches.home_score IS NOT NULL AND matches.away_score IS NOT NULL"
    ))
    DBI::dbExecute(conn, "CREATE INDEX idx_hvbr_team_season_venue ON home_venue_breakdown_rows(team_id, season, venue_name)")
    DBI::dbExecute(conn, "CREATE INDEX idx_hvbr_venue_season ON home_venue_breakdown_rows(venue_name, season)")

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
                  "team_match_stats", "home_venue_impact_rows", "home_venue_breakdown_rows",
                  "score_flow_events", "match_period_durations", "match_lead_state",
                  "player_reference", "player_season_demographics", "league_composition_summary",
                  "league_composition_debut_bands",
                  "match_scoreflow_summary", "player_match_participation", "metadata")) {
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

# Bootstrap future season fixtures from netball.com.au API if not already in database
if (!sample_mode) {
  tryCatch({
    message("Bootstrapping future season fixtures from netball.com.au...")
    conn <- get_connection(database_target_description())
    
    # Check if we already have fixtures for a future season
    future_matches <- DBI::dbGetQuery(conn, "
      SELECT COUNT(*) as cnt FROM matches 
      WHERE extract(year from local_start_time) > extract(year from CURRENT_DATE)
    ")
    
    if (future_matches$cnt[[1]] == 0) {
      message("  No future season matches found. Attempting to fetch from netball.com.au API...")
      resp <- httr::GET("https://api.netball.com.au/v1/matches",
        query = list(competitionId = 291, season = format(Sys.Date(), "%Y") + 1),
        httr::timeout(20)
      )
      
      if (httr::status_code(resp) == 200) {
        data <- jsonlite::fromJSON(httr::content(resp, "text"), simplifyVector = FALSE)
        matches_raw <- data$data
        
        # Filter to upcoming
        now_utc <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
        upcoming <- Filter(function(m) m$utcStartTime > now_utc, matches_raw)
        
        if (length(upcoming) > 0) {
          # Map team names
          team_map <- list(
            "Swifts" = "NSW Swifts",
            "GIANTS" = "GIANTS Netball",
            "Thunderbirds" = "Queensland Thunderbirds",
            "Lightning" = "Sunshine Coast Lightning",
            "Firebirds" = "Brisbane Firebirds",
            "Mavericks" = "West Coast Mavericks",
            "Fever" = "Perth Fever",
            "Vixens" = "Melbourne Vixens"
          )
          
          inserts_done <- 0
          for (m in upcoming) {
            home_name <- team_map[[m$homeSquadName]] %||% m$homeSquadName
            away_name <- team_map[[m$awaySquadName]] %||% m$awaySquadName
            
            tryCatch({
              # Extract home_squad_id and away_squad_id from API (or use 0 as placeholder)
              home_squad_id <- if (!is.null(m$homeSquadId)) as.integer(m$homeSquadId) else 0L
              away_squad_id <- if (!is.null(m$awaySquadId)) as.integer(m$awaySquadId) else 0L
              game_number <- if (!is.null(m$gameNumber)) as.integer(m$gameNumber) else 1L
              season_year <- as.integer(format(Sys.Date(), "%Y")) + 1L
              
              DBI::dbExecute(conn, "
                INSERT INTO matches (
                  match_id, champion_data_match_id, season, round_number, game_number,
                  local_start_time, utc_start_time, venue_name, competition_phase,
                  home_squad_id, home_squad_name, away_squad_id, away_squad_name,
                  home_score, away_score, status
                ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
                ON CONFLICT (match_id) DO NOTHING
              ", list(
                paste0("netball_", m$matchId),
                m$matchId,
                season_year,
                m$roundNumber,
                game_number,
                m$localStartTime,
                m$utcStartTime,
                m$venueName,
                "",
                home_squad_id,
                home_name,
                away_squad_id,
                away_name,
                NA_integer_, NA_integer_, "upcoming"
              ))
              inserts_done <- inserts_done + 1
            }, error = function(e) {
              warning(sprintf("Failed to insert fixture %s: %s", m$matchId, conditionMessage(e)))
            })
          }
          
          message(sprintf("  ✓ Bootstrapped %d future season fixtures", inserts_done))
        }
      } else {
        message(sprintf("  ⚠ netball.com.au API returned %d", httr::status_code(resp)))
      }
    }
    
    DBI::dbDisconnect(conn)
  }, error = function(e) {
    warning(sprintf("Bootstrap fixtures failed (non-blocking): %s", conditionMessage(e)))
  })
}
