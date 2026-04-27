#!/usr/bin/env Rscript

assert_true <- function(condition, message) {
  if (!isTRUE(condition)) {
    stop(message, call. = FALSE)
  }
}

test_env <- new.env(parent = globalenv())
source("api/R/helpers.R", local = test_env)
rm(list = ls(envir = test_env$.round_summary_cache), envir = test_env$.round_summary_cache)

state <- new.env(parent = emptyenv())
state$selected_round <- data.frame(
  season = 2026L,
  competition_phase = "regular",
  round_number = 7L,
  total_matches = 1L,
  round_end_time = "2026-04-25T17:00:00+10:00",
  stringsAsFactors = FALSE
)
state$matches <- data.frame(
  match_id = 129490701L,
  season = 2026L,
  competition_phase = "regular",
  round_number = 7L,
  game_number = 1L,
  local_start_time = "2026-04-25T17:00:00+10:00",
  venue_name = "Ken Rosewall Arena",
  home_squad_id = 806L,
  home_squad_name = "NSW Swifts",
  home_score = 58,
  away_squad_id = 8118L,
  away_squad_name = "GIANTS Netball",
  away_score = 39,
  margin = 19,
  winner_name = "NSW Swifts",
  stringsAsFactors = FALSE
)

test_env$fetch_latest_completed_round <- function(conn, season = NULL, round = NULL) {
  state$selected_round
}

test_env$fetch_round_matches <- function(conn, season, competition_phase = "", round_number) {
  state$matches
}

test_env$build_round_match_summary <- function(matches) {
  list(
    total_matches = nrow(matches),
    total_goals = sum(matches$home_score + matches$away_score),
    biggest_margin = NULL,
    closest_margin = NULL,
    average_margin = NULL,
    round_high_team_score = max(c(matches$home_score, matches$away_score)),
    biggest_margin_match = NULL,
    closest_match = NULL
  )
}

test_env$fetch_team_points_high <- function(...) data.frame()
test_env$fetch_player_points_high <- function(...) data.frame()
test_env$fetch_player_spotlight_rows <- function(...) list()
test_env$fetch_team_spotlight_rows <- function(...) list(generalPlayTurnovers = data.frame())
test_env$fetch_spotlight_bests <- function(...) list()
test_env$fetch_spotlight_archive_data <- function(...) list(bests = list(), ranks = list())
test_env$points_record_badges <- function(...) character()
test_env$compute_archive_rank <- function(...) NA_integer_
test_env$spotlight_badges <- function(...) character()
test_env$margin_record_badges <- function(...) character()
test_env$format_round_label <- function(competition_phase, round_value) sprintf("Round %s", round_value)
test_env$rows_to_records <- function(df) {
  lapply(seq_len(nrow(df)), function(i) as.list(df[i, , drop = FALSE]))
}
test_env$extract_first_numeric <- function(row) {
  if (is.null(row) || !length(row) || !is.data.frame(row) || !nrow(row)) {
    return(NA_real_)
  }
  if ("total_value" %in% names(row)) {
    return(as.numeric(row$total_value[[1]]))
  }
  NA_real_
}

first_payload <- test_env$build_round_summary_payload(conn = NULL, season = NULL, round = NULL)
assert_true(length(first_payload$matches) == 1L, "Expected the initial cached recap payload to contain one match.")

state$selected_round$total_matches <- 4L
state$selected_round$round_end_time <- "2026-04-26T16:00:00+10:00"
state$matches <- data.frame(
  match_id = c(129490701L, 129490702L, 129490703L, 129490704L),
  season = rep(2026L, 4),
  competition_phase = rep("regular", 4),
  round_number = rep(7L, 4),
  game_number = c(1L, 2L, 3L, 4L),
  local_start_time = c(
    "2026-04-25T17:00:00+10:00",
    "2026-04-25T18:30:00+09:30",
    "2026-04-26T14:00:00+10:00",
    "2026-04-26T14:00:00+08:00"
  ),
  venue_name = c(
    "Ken Rosewall Arena",
    "Adelaide Entertainment Centre",
    "Nissan Arena",
    "RAC Arena"
  ),
  home_squad_id = c(806L, 804L, 8119L, 810L),
  home_squad_name = c("NSW Swifts", "Adelaide Thunderbirds", "Queensland Firebirds", "West Coast Fever"),
  home_score = c(72, 61, 57, 44),
  away_squad_id = c(8118L, 8117L, 8116L, 807L),
  away_squad_name = c("GIANTS Netball", "Sunshine Coast Lightning", "Melbourne Mavericks", "Melbourne Vixens"),
  away_score = c(59, 60, 58, 50),
  margin = c(13, 1, 1, 6),
  winner_name = c("NSW Swifts", "Adelaide Thunderbirds", "Melbourne Mavericks", "Melbourne Vixens"),
  stringsAsFactors = FALSE
)

second_payload <- test_env$build_round_summary_payload(conn = NULL, season = NULL, round = NULL)

assert_true(
  length(second_payload$matches) == 4L,
  "Expected round-summary cache invalidation when the same round gains more completed matches."
)
assert_true(
  identical(second_payload$matches[[1]]$home_score, 72),
  "Expected round-summary cache invalidation when an existing match score changes after review."
)

cat("round-summary cache refreshes when completed round data changes.\n")
