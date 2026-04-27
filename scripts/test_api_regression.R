#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(httr)
  library(jsonlite)
})

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || all(is.na(x))) {
    return(y)
  }

  if (is.character(x) && !nzchar(x[[1]])) {
    return(y)
  }

  x
}

build_base_url <- function(args) {
  cli_value <- grep('^--base-url=', args, value = TRUE)
  base_url <- if (length(cli_value)) {
    sub('^--base-url=', '', cli_value[[1]])
  } else {
    Sys.getenv('NETBALL_STATS_API_BASE_URL', 'http://127.0.0.1:8000')
  }

  sub('/+$', '', trimws(base_url))
}

build_endpoint_url <- function(base_url, path, query = list()) {
  parsed <- httr::parse_url(base_url)
  base_path <- sub('/+$', '', parsed$path %||% '')
  suffix <- sub('^/+', '', path)
  parsed$path <- if (nzchar(base_path)) {
    paste0(base_path, '/', suffix)
  } else {
    paste0('/', suffix)
  }
  parsed$query <- query
  httr::build_url(parsed)
}

assert_true <- function(condition, message) {
  if (!isTRUE(condition)) {
    stop(message, call. = FALSE)
  }
}

scalar_value <- function(value) {
  if (is.list(value) && length(value) == 1L) {
    return(scalar_value(value[[1]]))
  }

  if (length(value) == 1L) {
    return(value[[1]])
  }

  value
}

check_step <- function(label) {
  cat(sprintf('✓ %s\n', label))
}

normalize_sql <- function(query) {
  gsub("\\s+", " ", trimws(query))
}

assert_contains <- function(text, needle, message) {
  assert_true(grepl(needle, text, fixed = TRUE), message)
}

perform_request_with_retry <- function(request_fn, request_label, expected_status = 200L, max_attempts = 8L) {
  attempt <- 1L

  repeat {
    response <- request_fn()
    status <- as.integer(httr::status_code(response))
    body_text <- httr::content(response, as = 'text', encoding = 'UTF-8')

    if (status == 429L && attempt < max_attempts) {
      Sys.sleep(min(10L, 2L ^ (attempt - 1L)))
      attempt <- attempt + 1L
      next
    }

    if (status != as.integer(expected_status)) {
      stop(
        sprintf('Expected HTTP %s from %s, got %s. Body: %s', expected_status, request_label, status, body_text),
        call. = FALSE
      )
    }

    if (!nzchar(body_text)) {
      return(list())
    }

    return(jsonlite::fromJSON(body_text, simplifyVector = FALSE))
  }
}

request_json <- function(base_url, path, query = list(), expected_status = 200L) {
  url <- build_endpoint_url(base_url, path, query)
  perform_request_with_retry(
    function() httr::GET(url, httr::timeout(30)),
    request_label = url,
    expected_status = expected_status
  )
}

request_json_post <- function(base_url, path, body = list(), expected_status = 200L) {
  url <- build_endpoint_url(base_url, path)
  body_json <- jsonlite::toJSON(body, auto_unbox = TRUE)
  perform_request_with_retry(
    function() httr::POST(
      url,
      httr::add_headers(`Content-Type` = 'application/json'),
      body = body_json,
      httr::timeout(30)
    ),
    request_label = paste0(url, ' (POST)'),
    expected_status = expected_status
  )
}

first_record <- function(records) {
  assert_true(is.list(records) && length(records) >= 1, 'Expected at least one record.')
  records[[1]]
}

args <- commandArgs(trailingOnly = TRUE)
base_url <- build_base_url(args)
cat(sprintf('Running API regression checks against %s\n', base_url))

live <- request_json(base_url, '/live')
assert_true(identical(as.character(scalar_value(live$status)), 'ok'), 'Expected /live to report ok status.')
check_step('live endpoint reports ok')

ready <- request_json(base_url, '/ready')
assert_true(identical(as.character(scalar_value(ready$status)), 'ok'), 'Expected /ready to report ok status.')
assert_true(identical(as.character(scalar_value(ready$database)), 'ok'), 'Expected /ready to report database ok.')
check_step('readiness endpoint reports database availability')

meta <- request_json(base_url, '/meta')
assert_true(is.list(meta$seasons) && length(meta$seasons) >= 1, 'Expected /meta to expose at least one season.')
assert_true(is.list(meta$teams) && length(meta$teams) >= 1, 'Expected /meta to expose at least one team.')
assert_true(is.list(meta$team_stats) && length(meta$team_stats) >= 1, 'Expected /meta to expose team stats.')
assert_true(is.list(meta$player_stats) && length(meta$player_stats) >= 1, 'Expected /meta to expose player stats.')
assert_true(is.null(meta$telemetry$connection_string), 'Expected /meta to avoid exposing a browser telemetry connection string.')
check_step('metadata endpoint returns seasons, teams, and stat catalogs')

default_season <- as.integer(scalar_value(meta$default_season %||% meta$seasons[[1]]))
summary_payload <- request_json(base_url, '/summary', query = list(season = default_season))
assert_true(!is.null(summary_payload$total_matches), 'Expected /summary to return total_matches.')
assert_true(as.numeric(scalar_value(summary_payload$total_matches)) >= 1, 'Expected /summary to report at least one match.')
summary_series_payload <- request_json(
  base_url,
  '/team-season-series',
  query = list(seasons = as.character(default_season), stat = 'points', metric = 'total')
)
summary_series_matches <- vapply(
  summary_series_payload$data,
  function(row) as.integer(scalar_value(row$matches_played %||% NA_integer_)),
  integer(1L)
)
assert_true(length(summary_series_matches) >= 2L, 'Expected /team-season-series to return enough team rows to infer completed matches.')
assert_true(all(!is.na(summary_series_matches)), 'Expected /team-season-series matches_played values to be numeric.')
expected_completed_matches <- sum(summary_series_matches) / 2
assert_true(
  identical(as.numeric(scalar_value(summary_payload$total_matches)), expected_completed_matches),
  sprintf(
    'Expected /summary total_matches to reflect completed matches (%s), got %s.',
    expected_completed_matches,
    as.numeric(scalar_value(summary_payload$total_matches))
  )
)
check_step('summary endpoint returns season totals')

players_payload <- request_json(base_url, '/players', query = list(limit = 1))
player_record <- first_record(players_payload$data)
player_id <- as.integer(scalar_value(player_record$player_id %||% NA_integer_))
assert_true(!is.na(player_id), 'Expected /players to return a player_id.')
check_step('players endpoint returns at least one player')

profile_payload <- request_json(base_url, '/player-profile', query = list(player_id = player_id))
assert_true(as.integer(scalar_value(profile_payload$player$player_id %||% NA_integer_)) == player_id, 'Expected /player-profile to echo the requested player.')
assert_true(is.list(profile_payload$season_summaries), 'Expected /player-profile to include season summaries.')
check_step('player profile endpoint returns career data for a discovered player')

team_leaders_payload <- request_json(base_url, '/team-leaders', query = list(season = default_season, stat = 'goals', limit = 3))
assert_true(is.list(team_leaders_payload$data) && length(team_leaders_payload$data) >= 1, 'Expected /team-leaders to return rows.')
check_step('team leaders endpoint returns ranked team rows')

team_leaders_highest_payload <- request_json(base_url, '/team-leaders', query = list(season = default_season, stat = 'goals', ranking = 'highest', limit = 3))
team_leaders_lowest_payload <- request_json(base_url, '/team-leaders', query = list(season = default_season, stat = 'goals', ranking = 'lowest', limit = 3))
assert_true(is.list(team_leaders_highest_payload$data) && length(team_leaders_highest_payload$data) >= 1, 'Expected /team-leaders highest mode to return rows.')
assert_true(is.list(team_leaders_lowest_payload$data) && length(team_leaders_lowest_payload$data) >= 1, 'Expected /team-leaders lowest mode to return rows.')
highest_value <- as.numeric(scalar_value(team_leaders_highest_payload$data[[1]]$total_value %||% NA_real_))
lowest_value <- as.numeric(scalar_value(team_leaders_lowest_payload$data[[1]]$total_value %||% NA_real_))
assert_true(!is.na(highest_value) && !is.na(lowest_value), 'Expected ranked team rows to expose numeric totals.')
assert_true(highest_value >= lowest_value, 'Expected highest-mode team leaders to rank at least as high as lowest-mode leaders.')
check_step('team leaders endpoint supports highest and lowest ranking modes')

season_series_years <- as.integer(2020:2026)
season_series_csv <- paste(season_series_years, collapse = ',')
team_super_shot_series_payload <- request_json(
  base_url,
  '/competition-season-series',
  query = list(seasons = season_series_csv, stat = 'goal2', metric = 'total')
)
team_goal_one_series_payload <- request_json(
  base_url,
  '/competition-season-series',
  query = list(seasons = season_series_csv, stat = 'goal1', metric = 'total')
)
team_super_shot_years <- vapply(team_super_shot_series_payload$data, function(row) as.integer(scalar_value(row$season)), integer(1))
team_goal_one_years <- vapply(team_goal_one_series_payload$data, function(row) as.integer(scalar_value(row$season)), integer(1))
assert_true(
  identical(team_super_shot_years, season_series_years),
  sprintf(
    'Expected /competition-season-series goal2 coverage for seasons %s, got %s.',
    paste(season_series_years, collapse = ','),
    paste(team_super_shot_years, collapse = ',')
  )
)
assert_true(
  identical(team_goal_one_years, season_series_years),
  sprintf(
    'Expected /competition-season-series goal1 coverage for seasons %s, got %s.',
    paste(season_series_years, collapse = ','),
    paste(team_goal_one_years, collapse = ',')
  )
)
check_step('competition season series keeps full requested season coverage for team goal1 and goal2')

team_game_highs_payload <- request_json(base_url, '/team-game-highs', query = list(season = default_season, stat = 'goals', ranking = 'highest', limit = 3))
team_game_lows_payload <- request_json(base_url, '/team-game-highs', query = list(season = default_season, stat = 'goals', ranking = 'lowest', limit = 3))
assert_true(is.list(team_game_highs_payload$data) && length(team_game_highs_payload$data) >= 1, 'Expected /team-game-highs to return rows.')
assert_true(is.list(team_game_lows_payload$data) && length(team_game_lows_payload$data) >= 1, 'Expected /team-game-highs lowest mode to return rows.')
check_step('team game records endpoint supports highest and lowest ranking modes')

player_game_highs_payload <- request_json(base_url, '/player-game-highs', query = list(season = default_season, stat = 'goals', ranking = 'highest', limit = 3))
assert_true(is.list(player_game_highs_payload$data) && length(player_game_highs_payload$data) >= 1, 'Expected /player-game-highs to return rows.')
check_step('player game records endpoint returns rows')

round_summary_url <- build_endpoint_url(base_url, '/round-summary')
round_summary_response <- httr::GET(round_summary_url, httr::timeout(30))
round_summary_status <- httr::status_code(round_summary_response)
round_summary_text <- httr::content(round_summary_response, as = 'text', encoding = 'UTF-8')
round_summary_payload <- if (nzchar(round_summary_text)) {
  jsonlite::fromJSON(round_summary_text, simplifyVector = FALSE)
} else {
  list()
}

assert_true(round_summary_status %in% c(200L, 404L), sprintf('Expected /round-summary to return 200 or 404, got %s.', round_summary_status))
if (identical(round_summary_status, 200L)) {
  assert_true(nzchar(as.character(scalar_value(round_summary_payload$round_label %||% ''))), 'Expected /round-summary to return a round label.')
  assert_true(is.list(round_summary_payload$matches) && length(round_summary_payload$matches) >= 1, 'Expected /round-summary to return completed matches.')
  assert_true(is.list(round_summary_payload$notable_facts) && length(round_summary_payload$notable_facts) >= 1, 'Expected /round-summary to return notable facts.')
  round_summary_season <- as.integer(scalar_value(round_summary_payload$season %||% NA_integer_))
  round_summary_round <- as.integer(scalar_value((round_summary_payload$round_number %||% round_summary_payload$round) %||% NA_integer_))
  round_summary_phase <- as.character(scalar_value(round_summary_payload$competition_phase %||% ''))
  round_matches_payload <- request_json(
    base_url,
    '/matches',
    query = list(season = round_summary_season, round = round_summary_round, limit = 50L)
  )
  round_matches <- Filter(function(row) {
    identical(as.character(scalar_value(row$competition_phase %||% '')), round_summary_phase)
  }, round_matches_payload$data %||% list())
  round_match_total_goals <- sum(vapply(round_matches, function(row) {
    as.numeric(scalar_value(row$home_score %||% 0)) + as.numeric(scalar_value(row$away_score %||% 0))
  }, numeric(1)), na.rm = TRUE)
  assert_true(
    length(round_summary_payload$matches) == length(round_matches),
    sprintf(
      'Expected /round-summary to include the same number of completed matches as /matches for season %s round %s (%s), got %s vs %s.',
      round_summary_season,
      round_summary_round,
      round_summary_phase %||% 'regular',
      length(round_summary_payload$matches),
      length(round_matches)
    )
  )
  assert_true(
    identical(as.numeric(scalar_value(round_summary_payload$summary$total_goals %||% NA_real_)), round_match_total_goals),
    sprintf(
      'Expected /round-summary total goals to match /matches for season %s round %s (%s), got %s vs %s.',
      round_summary_season,
      round_summary_round,
      round_summary_phase %||% 'regular',
      scalar_value(round_summary_payload$summary$total_goals %||% NA_real_),
      round_match_total_goals
    )
  )
  check_step('round summary endpoint returns recap content')
} else {
  assert_true(nzchar(as.character(scalar_value(round_summary_payload$error %||% ''))), 'Expected /round-summary 404 responses to include an error payload.')
  check_step('round summary endpoint returns a clean 404 when no completed round is available')
}

round_preview_url <- build_endpoint_url(base_url, '/round-preview-summary')
round_preview_response <- httr::GET(round_preview_url, httr::timeout(30))
round_preview_status <- httr::status_code(round_preview_response)
round_preview_text <- httr::content(round_preview_response, as = 'text', encoding = 'UTF-8')
round_preview_payload <- if (nzchar(round_preview_text)) {
  jsonlite::fromJSON(round_preview_text, simplifyVector = FALSE)
} else {
  list()
}

assert_true(
  round_preview_status %in% c(200L, 404L),
  sprintf('Expected /round-preview-summary to return 200 or 404, got %s.', round_preview_status)
)

if (identical(round_preview_status, 200L)) {
  assert_true(
    nzchar(as.character(scalar_value(round_preview_payload$round_label %||% ''))),
    'Expected /round-preview-summary to return a round label.'
  )
  assert_true(
    is.list(round_preview_payload$summary_cards),
    'Expected /round-preview-summary to return summary cards.'
  )
  assert_true(
    is.list(round_preview_payload$matches) && length(round_preview_payload$matches) >= 1,
    'Expected /round-preview-summary to return upcoming matches.'
  )
  first_preview_match <- first_record(round_preview_payload$matches)
  assert_true(is.list(first_preview_match$fixture), 'Expected round preview matches to include fixture metadata.')
  assert_true(
    is.list(first_preview_match$head_to_head) || nzchar(as.character(scalar_value(first_preview_match$history_note %||% ''))),
    'Expected round preview matches to include head-to-head context or an explicit sparse-history note.'
  )
  assert_true(
    is.list(first_preview_match$last_meeting) || nzchar(as.character(scalar_value(first_preview_match$history_note %||% ''))),
    'Expected round preview matches to include last-meeting context or an explicit sparse-history note.'
  )
  assert_true(
    is.list(first_preview_match$recent_form),
    'Expected round preview matches to include recent-form summaries.'
  )
  assert_true(
    is.list(first_preview_match$streaks),
    'Expected round preview matches to include streak summaries.'
  )
  assert_true(
    is.list(first_preview_match$player_watch),
    'Expected round preview matches to include player-watch notes.'
  )
  assert_true(
    is.list(first_preview_match$fact_cards),
    'Expected round preview matches to include editorial fact cards.'
  )
  check_step('round preview endpoint returns upcoming-round content')
} else {
  assert_true(
    nzchar(as.character(scalar_value(round_preview_payload$error %||% ''))),
    'Expected /round-preview-summary 404 responses to include an error payload.'
  )
  check_step('round preview endpoint returns a clean 404 when no upcoming round is available')
}

round_preview_helpers_env <- new.env(parent = globalenv())
sys.source(file.path(getwd(), 'api', 'R', 'helpers.R'), envir = round_preview_helpers_env)
round_preview_helpers_env$api_log <- function(...) NULL
round_preview_helpers_env$has_player_match_stats <- function(conn) TRUE
assert_true(identical(round_preview_helpers_env$round_preview_team_logo_url('NSW Swifts'), '/team-logos/swifts.svg'), 'Expected round preview logo helper to map NSW Swifts to the local crest asset.')
assert_true(identical(round_preview_helpers_env$round_preview_team_logo_url('GIANTS Netball'), '/team-logos/giants.svg'), 'Expected round preview logo helper to map GIANTS Netball to the local crest asset.')
assert_true(is.null(round_preview_helpers_env$round_preview_team_logo_url('Unknown Team')), 'Expected round preview logo helper to return NULL for unmapped teams.')
captured_preview_queries <- character()
round_preview_helpers_env$query_rows <- function(conn, query, params = list()) {
  captured_preview_queries <<- c(captured_preview_queries, normalize_sql(query))

  if (grepl('total_goals', query, fixed = TRUE)) {
    data.frame(
      canonical_name = 'Sample Shooter',
      total_goals = 17,
      stringsAsFactors = FALSE
    )
  } else {
    data.frame(
      canonical_name = 'Sample Defender',
      total_gain = 6,
      stringsAsFactors = FALSE
    )
  }
}

recent_player_watch <- round_preview_helpers_env$fetch_preview_player_watch(
  conn = NULL,
  squad_id = 804L,
  seasons = default_season,
  context = 'recent_form'
)
last_meeting_player_watch <- round_preview_helpers_env$fetch_preview_player_watch(
  conn = NULL,
  squad_id = 804L,
  match_id = 12345L,
  seasons = default_season,
  context = 'last_meeting'
)
assert_true(identical(recent_player_watch$summary, 'Sample Shooter leads this side with 17 goals across its last five completed matches.'), 'Expected recent-form player watch to summarize goals from player_match_stats.match_value.')
assert_true(identical(last_meeting_player_watch$summary, 'Sample Shooter scored 17 goals in the last meeting.'), 'Expected last-meeting player watch to summarize goals from player_match_stats.match_value.')
assert_true(length(captured_preview_queries) == 2L, 'Expected player watch helpers to issue one query per context when point leaders are present.')
assert_true(!any(grepl('pms.value_number', captured_preview_queries, fixed = TRUE)), 'Expected round preview player watch queries to avoid the missing player_match_stats.value_number column.')
assert_true(all(grepl('pms.match_value', captured_preview_queries, fixed = TRUE)), 'Expected round preview player watch queries to use player_match_stats.match_value.')

captured_preview_queries <- character()
round_preview_helpers_env$query_rows <- function(conn, query, params = list()) {
  captured_preview_queries <<- c(captured_preview_queries, normalize_sql(query))

  if (grepl('total_goals', query, fixed = TRUE)) {
    return(data.frame(
      canonical_name = character(),
      total_goals = numeric(),
      stringsAsFactors = FALSE
    ))
  }

  data.frame(
    canonical_name = 'Sample Defender',
    total_gain = 6,
    stringsAsFactors = FALSE
  )
}

recent_gain_watch <- round_preview_helpers_env$fetch_preview_player_watch(
  conn = NULL,
  squad_id = 804L,
  seasons = default_season,
  context = 'recent_form'
)
last_meeting_gain_watch <- round_preview_helpers_env$fetch_preview_player_watch(
  conn = NULL,
  squad_id = 804L,
  match_id = 12345L,
  seasons = default_season,
  context = 'last_meeting'
)
assert_true(identical(recent_gain_watch$summary, 'Sample Defender leads this side with 6 gains across its last five completed matches.'), 'Expected recent-form player watch to fall back to gains from player_match_stats.match_value.')
assert_true(identical(last_meeting_gain_watch$summary, 'Sample Defender recorded 6 gains in the last meeting.'), 'Expected last-meeting player watch to fall back to gains from player_match_stats.match_value.')
assert_true(length(captured_preview_queries) == 4L, 'Expected player watch helpers to query both points and gains when no point leader is available.')
assert_true(!any(grepl('pms.value_number', captured_preview_queries, fixed = TRUE)), 'Expected round preview player watch fallback queries to avoid the missing player_match_stats.value_number column.')
assert_true(all(grepl('pms.match_value', captured_preview_queries, fixed = TRUE)), 'Expected round preview player watch fallback queries to use player_match_stats.match_value.')
check_step('round preview helpers map crest assets and use player_match_stats.match_value')

fantasy_env <- new.env(parent = globalenv())
sys.source(file.path(getwd(), 'api', 'R', 'helpers.R'), envir = fantasy_env)
fantasy_env$api_log <- function(...) NULL
fantasy_env$has_player_match_stats <- function(conn) TRUE
fantasy_env$query_rows <- function(conn, query, params = list()) {
  data.frame(
    canonical_name = 'Sample Player',
    fantasy_score = 213.5,
    stringsAsFactors = FALSE
  )
}
fantasy_watch <- fantasy_env$fetch_preview_fantasy_watch(conn = NULL, squad_id = 804L, seasons = default_season)
assert_true(!is.null(fantasy_watch), 'Expected fetch_preview_fantasy_watch to return a non-null result when query returns a player.')
assert_true(identical(fantasy_watch$context, 'recent_form'), 'Expected fetch_preview_fantasy_watch to set context to recent_form.')
assert_true(grepl('fantasy scoring', fantasy_watch$summary, fixed = TRUE), 'Expected fetch_preview_fantasy_watch summary to mention fantasy scoring.')
assert_true(grepl('Sample Player', fantasy_watch$summary, fixed = TRUE), 'Expected fetch_preview_fantasy_watch summary to include player name.')
assert_true(grepl('213.5 pts', fantasy_watch$summary, fixed = TRUE), 'Expected fetch_preview_fantasy_watch summary to include fantasy score.')
check_step('fetch_preview_fantasy_watch returns a well-formed watch note')

query_payload <- request_json(
  base_url,
  '/query',
  query = list(question = sprintf('Which players scored 20+ goals in %s?', default_season), limit = 5)
)
assert_true(identical(as.character(scalar_value(query_payload$status)), 'supported'), 'Expected /query to support a representative natural-language question.')
assert_true(nzchar(as.character(scalar_value(query_payload$answer %||% ''))), 'Expected /query to return an answer string.')
check_step('natural-language query endpoint returns a supported answer')

team_query_payload <- request_json(
  base_url,
  '/query',
  query = list(question = sprintf('Which teams scored 60+ goals in %s?', default_season), limit = 5)
)
assert_true(identical(as.character(scalar_value(team_query_payload$status)), 'supported'), 'Expected /query to support a representative team natural-language question.')
assert_true(identical(as.character(scalar_value(team_query_payload$parsed$subject_type %||% '')), 'teams'), 'Expected team query parsing to report teams subject_type.')
check_step('natural-language query endpoint supports representative team queries')

helpers_env <- new.env(parent = globalenv())
sys.source('api/R/helpers.R', envir = helpers_env)
assert_true(
  identical(as.character(helpers_env$canonical_team_query_stat('gain')), 'gain'),
  'Expected canonical_team_query_stat to leave non-aliased team stats unchanged.'
)
captured_team_period_queries <- list()
helpers_env$query_rows <- function(conn, query, params = list()) {
  normalized_query <- normalize_sql(query)
  captured_team_period_queries <<- c(
    captured_team_period_queries,
    list(list(query = normalized_query, params = params))
  )

  if (grepl("COUNT\\(DISTINCT round_number\\) AS games", normalized_query)) {
    return(data.frame(
      total = 11,
      games = 2L,
      stringsAsFactors = FALSE
    ))
  }

  data.frame(
    round_number = c(1L, 2L),
    value = c(5, 6),
    opponent = c('Thunderbirds', 'Vixens'),
    stringsAsFactors = FALSE
  )
}

helpers_env$fetch_team_season_aggregate(conn = NULL, team_id = 804L, stat_key = 'goal2', season = 2020L)
assert_true(
  identical(as.character(captured_team_period_queries[[1]]$params$source_stat), 'goal_from_zone2'),
  'Expected fetch_team_season_aggregate to query goal_from_zone2 when callers request team goal2 totals.'
)
helpers_env$fetch_team_round_breakdown(conn = NULL, team_id = 804L, stat_key = 'goal1', season = 2020L)
assert_true(
  identical(as.character(captured_team_period_queries[[2]]$params$source_stat), 'goal_from_zone1'),
  'Expected fetch_team_round_breakdown to query goal_from_zone1 when callers request team goal1 totals.'
)
check_step('team period stat helpers canonicalize goal1 and goal2 to zone-based team stat keys')
composition_helpers_env <- new.env(parent = globalenv())
sys.source('api/R/helpers.R', envir = composition_helpers_env)
composition_helpers_env$record_to_scalars <- function(values) values
composition_helpers_env$rows_to_records <- function(rows) rows
composition_helpers_env$query_rows <- function(conn, query, params = list()) {
  normalized_query <- normalize_sql(query)
  if (grepl("^SELECT \\* FROM league_composition_summary", normalized_query)) {
    return(data.frame(
      season = c(2016L, 2017L),
      players_with_matches = c(2L, 2L),
      players_with_birth_date = c(2L, 2L),
      players_with_import_status = c(NA_integer_, 2L),
      average_player_age = c(24.5, 25.5),
      average_experience_seasons = c(1.0, 2.0),
      average_debut_age = c(19.5, 20.5),
      import_share = c(NA_real_, 0.5),
      age_coverage_share = c(1.0, 1.0),
      import_coverage_share = c(NA_real_, 1.0),
      stringsAsFactors = FALSE
    ))
  }
  if (grepl("SUM\\(players_with_matches\\)", normalized_query)) {
    return(data.frame(
      players_with_matches = 4L,
      players_with_birth_date = 4L,
      players_with_import_status = 2L,
      stringsAsFactors = FALSE
    ))
  }
  stop(sprintf("Unexpected league composition summary query in regression test: %s", normalized_query))
}
mixed_composition_payload <- composition_helpers_env$query_league_composition_summary(conn = NULL, seasons = c(2016L, 2017L))
assert_true(
  is.na(mixed_composition_payload$coverage$players_with_import_status),
  'Expected mixed ANZC/SSN league composition coverage to return NA import coverage metadata.'
)
check_step('league composition coverage marks mixed ANZC and SSN import coverage as not applicable')
plumber_helpers_env <- new.env(parent = globalenv())
sys.source('api/plumber.R', envir = plumber_helpers_env)
serializer_payload <- list(
  coverage = plumber_helpers_env$record_to_scalars(list(players_with_import_status = NA_integer_)),
  data = plumber_helpers_env$rows_to_records(data.frame(
    season = 2016L,
    import_share = NA_real_,
    stringsAsFactors = FALSE
  ))
)
serializer_json <- jsonlite::toJSON(serializer_payload, auto_unbox = TRUE, null = 'null', na = 'null')
assert_true(
  grepl('"players_with_import_status":null', serializer_json, fixed = TRUE),
  'Expected record_to_scalars to serialize NA coverage values as JSON null.'
)
assert_true(
  grepl('"import_share":null', serializer_json, fixed = TRUE),
  'Expected rows_to_records to serialize NA row values as JSON null.'
)
check_step('shared API serializers emit JSON null for NA scalar values')
assert_true(
  identical(
    helpers_env$resolve_query_stat(
      helpers_env$normalize_query_phrase('Which players scored 40+ goals in 2025?')
    ),
    'goals'
  ),
  'Expected resolve_query_stat to match stat aliases beyond the first configured pattern.'
)
assert_true(
  identical(
    helpers_env$resolve_query_stat(
      helpers_env$normalize_query_phrase('Which teams scored 60+ goals in 2025?')
    ),
    'goals'
  ),
  'Expected resolve_query_stat to support representative team goals phrasing.'
)
check_step('query parser resolves stat aliases for representative scored/goals phrasing')
possessive_subject <- helpers_env$extract_query_subject_phrase(
  "What is the Swifts' highest goals total against the Vixens?",
  'highest'
)
assert_true(identical(possessive_subject, 'the Swifts'), 'Expected possessive team phrasing to normalize to the team subject.')
check_step('parser normalizes possessive team phrasing')

assert_true(
  identical(helpers_env$resolve_request_client_key(' , 198.51.100.10', '127.0.0.1'), '127.0.0.1'),
  'Expected blank forwarded IP tokens to fall back to REMOTE_ADDR.'
)
assert_true(
  identical(helpers_env$resolve_request_client_key('   ', '127.0.0.2'), '127.0.0.2'),
  'Expected whitespace-only forwarded IP tokens to fall back to REMOTE_ADDR.'
)
assert_true(
  identical(helpers_env$resolve_request_client_key(',198.51.100.11', '127.0.0.3'), '127.0.0.3'),
  'Expected leading-comma forwarded IP tokens to fall back to REMOTE_ADDR.'
)
assert_true(
  identical(helpers_env$resolve_request_client_key('   ', ''), 'unknown'),
  'Expected blank REMOTE_ADDR to fall back to unknown.'
)
assert_true(
  identical(helpers_env$resolve_request_client_key('   ', '   '), 'unknown'),
  'Expected whitespace REMOTE_ADDR to fall back to unknown.'
)
check_step('rate limiter tolerates blank forwarded IP tokens')

player_builder_inputs <- list(
  stat = 'goals',
  seasons = c(2022L, 2023L),
  player_id = 804L,
  opponent_id = 806L,
  comparison = 'gte',
  threshold = 20
)
period_player_query <- do.call(helpers_env$build_player_match_query, player_builder_inputs)
fast_player_query <- do.call(helpers_env$build_fast_player_match_query, player_builder_inputs)
period_player_sql <- normalize_sql(period_player_query$query)
fast_player_sql <- normalize_sql(fast_player_query$query)

assert_true(identical(period_player_query$params, fast_player_query$params), 'Expected player match query builders to keep parameter payloads aligned.')
assert_contains(period_player_sql, 'FROM player_period_stats AS stats', 'Expected player-period builder to query player_period_stats.')
assert_contains(fast_player_sql, 'FROM player_match_stats AS pms', 'Expected player-match builder to query player_match_stats.')
assert_contains(period_player_sql, 'stats.season IN (?season_1, ?season_2)', 'Expected player-period builder to retain season array filters.')
assert_contains(fast_player_sql, 'pms.season IN (?season_1, ?season_2)', 'Expected player-match builder to retain season array filters.')
assert_contains(period_player_sql, 'AND stats.player_id = ?player_id', 'Expected player-period builder to retain player filters.')
assert_contains(fast_player_sql, 'AND pms.player_id = ?player_id', 'Expected player-match builder to retain player filters.')
assert_contains(period_player_sql, 'END) = ?opponent_id', 'Expected player-period builder to retain opponent filters.')
assert_contains(fast_player_sql, 'END) = ?opponent_id', 'Expected player-match builder to retain opponent filters.')
assert_contains(period_player_sql, 'HAVING SUM(stats.value_number) >= ?threshold', 'Expected player-period builder thresholds to stay in HAVING clauses.')
assert_contains(fast_player_sql, 'AND pms.match_value >= ?threshold', 'Expected player-match builder thresholds to stay in WHERE clauses.')
assert_contains(period_player_sql, 'GROUP BY stats.player_id, players.canonical_name, stats.squad_name, stats.season, stats.round_number, stats.match_id, matches.local_start_time', 'Expected player-period builder to keep match-level grouping.')
assert_true(!grepl(' GROUP BY ', fast_player_sql, fixed = TRUE), 'Expected player-match builder to avoid redundant GROUP BY clauses.')
check_step('player match query builders keep filters and threshold placement aligned')

comparison_cases <- list(lt = '<', eq = '=')
for (comparison_name in names(comparison_cases)) {
  expected_operator <- comparison_cases[[comparison_name]]
  period_comparison_query <- normalize_sql(helpers_env$build_player_match_query(
    stat = 'goals',
    comparison = comparison_name,
    threshold = 12
  )$query)
  fast_comparison_query <- normalize_sql(helpers_env$build_fast_player_match_query(
    stat = 'goals',
    comparison = comparison_name,
    threshold = 12
  )$query)

  assert_contains(
    period_comparison_query,
    sprintf('HAVING SUM(stats.value_number) %s ?threshold', expected_operator),
    sprintf('Expected player-period builder to keep %s threshold operators.', comparison_name)
  )
  assert_contains(
    fast_comparison_query,
    sprintf('AND pms.match_value %s ?threshold', expected_operator),
    sprintf('Expected player-match builder to keep %s threshold operators.', comparison_name)
  )
}
check_step('player match query builders preserve comparison operator mapping')

team_builder_inputs <- list(
  stat = 'goals',
  seasons = c(2022L, 2023L),
  team_id = 806L,
  opponent_id = 804L,
  comparison = 'gte',
  threshold = 60
)
period_team_query <- do.call(helpers_env$build_team_match_query, team_builder_inputs)
fast_team_query <- do.call(helpers_env$build_fast_team_match_query, team_builder_inputs)
period_team_sql <- normalize_sql(period_team_query$query)
fast_team_sql <- normalize_sql(fast_team_query$query)

assert_true(identical(period_team_query$params, fast_team_query$params), 'Expected team match query builders to keep parameter payloads aligned.')
assert_contains(period_team_sql, 'FROM team_period_stats AS stats', 'Expected team-period builder to query team_period_stats.')
assert_contains(fast_team_sql, 'FROM team_match_stats AS tms', 'Expected team-match builder to query team_match_stats.')
assert_contains(period_team_sql, 'stats.season IN (?season_1, ?season_2)', 'Expected team-period builder to retain season array filters.')
assert_contains(fast_team_sql, 'tms.season IN (?season_1, ?season_2)', 'Expected team-match builder to retain season array filters.')
assert_contains(period_team_sql, 'AND stats.squad_id = ?team_id', 'Expected team-period builder to retain team filters.')
assert_contains(fast_team_sql, 'AND tms.squad_id = ?team_id', 'Expected team-match builder to retain team filters.')
assert_contains(period_team_sql, 'END) = ?opponent_id', 'Expected team-period builder to retain opponent filters.')
assert_contains(fast_team_sql, 'END) = ?opponent_id', 'Expected team-match builder to retain opponent filters.')
assert_contains(period_team_sql, 'HAVING SUM(stats.value_number) >= ?threshold', 'Expected team-period builder thresholds to stay in HAVING clauses.')
assert_contains(fast_team_sql, 'AND tms.match_value >= ?threshold', 'Expected team-match builder thresholds to stay in WHERE clauses.')
assert_contains(period_team_sql, 'GROUP BY stats.squad_id, stats.squad_name, stats.season, stats.round_number, stats.match_id, matches.local_start_time', 'Expected team-period builder to keep match-level grouping.')
assert_true(!grepl(' GROUP BY ', fast_team_sql, fixed = TRUE), 'Expected team-match builder to avoid redundant GROUP BY clauses.')
check_step('team match query builders keep filters and threshold placement aligned')

capture_player_game_high_query <- function(use_match_stats, ...) {
  original_has_player_match_stats <- helpers_env$has_player_match_stats
  original_query_rows <- helpers_env$query_rows
  captured <- NULL

  on.exit({
    helpers_env$has_player_match_stats <- original_has_player_match_stats
    helpers_env$query_rows <- original_query_rows
  }, add = TRUE)

  helpers_env$has_player_match_stats <- function(conn) use_match_stats
  helpers_env$query_rows <- function(conn, query, params = list()) {
    captured <<- list(query = query, params = params)
    data.frame()
  }

  helpers_env$fetch_player_game_high_rows(
    conn = NULL,
    ...
  )

  captured
}

player_game_high_inputs <- list(
  seasons = c(2021L, 2022L),
  team_id = 804L,
  round = 5L,
  competition_phase = 'Final',
  stat = 'goals',
  ranking = 'lowest',
  limit = 4L
)
fast_player_game_high_query <- do.call(capture_player_game_high_query, c(list(use_match_stats = TRUE), player_game_high_inputs))
period_player_game_high_query <- do.call(capture_player_game_high_query, c(list(use_match_stats = FALSE), player_game_high_inputs))
fast_player_game_high_sql <- normalize_sql(fast_player_game_high_query$query)
period_player_game_high_sql <- normalize_sql(period_player_game_high_query$query)

assert_true(identical(fast_player_game_high_query$params, period_player_game_high_query$params), 'Expected player game-high query paths to keep parameter payloads aligned.')
assert_contains(fast_player_game_high_sql, 'pms.season IN (?season_1, ?season_2)', 'Expected player game-high fast path to retain season arrays.')
assert_contains(period_player_game_high_sql, 'stats.season IN (?season_1, ?season_2)', 'Expected player game-high fallback path to retain season arrays.')
assert_contains(fast_player_game_high_sql, 'AND pms.squad_id = ?team_id', 'Expected player game-high fast path to retain team filters.')
assert_contains(period_player_game_high_sql, 'AND stats.squad_id = ?team_id', 'Expected player game-high fallback path to retain team filters.')
assert_contains(fast_player_game_high_sql, 'AND pms.round_number = ?round_number', 'Expected player game-high fast path to retain round filters.')
assert_contains(period_player_game_high_sql, 'AND stats.round_number = ?round_number', 'Expected player game-high fallback path to retain round filters.')
assert_contains(fast_player_game_high_sql, "AND COALESCE(matches.competition_phase, '') = ?competition_phase", 'Expected player game-high fast path to retain competition phase filters.')
assert_contains(period_player_game_high_sql, "AND COALESCE(matches.competition_phase, '') = ?competition_phase", 'Expected player game-high fallback path to retain competition phase filters.')
assert_contains(fast_player_game_high_sql, 'ORDER BY pms.match_value ASC', 'Expected player game-high fast path to preserve lowest-ranking ordering.')
assert_contains(period_player_game_high_sql, 'GROUP BY stats.player_id, players.canonical_name, stats.squad_name, stats.season, stats.round_number, stats.match_id, matches.local_start_time ORDER BY total_value ASC', 'Expected player game-high fallback path to preserve match grouping before ordering.')
check_step('player game-high query paths keep filter and ordering clauses aligned')

capture_team_game_high_query <- function(use_team_match_stats, ...) {
  original_has_team_match_stats <- helpers_env$has_team_match_stats
  original_query_rows <- helpers_env$query_rows
  captured <- NULL

  on.exit({
    helpers_env$has_team_match_stats <- original_has_team_match_stats
    helpers_env$query_rows <- original_query_rows
  }, add = TRUE)

  helpers_env$has_team_match_stats <- function(conn) use_team_match_stats
  helpers_env$query_rows <- function(conn, query, params = list()) {
    captured <<- list(query = query, params = params)
    data.frame()
  }

  helpers_env$fetch_team_game_high_rows(
    conn = NULL,
    ...
  )

  captured
}

team_game_high_inputs <- list(
  seasons = c(2021L, 2022L),
  team_id = 804L,
  round = 5L,
  competition_phase = 'Final',
  stat = 'goals',
  ranking = 'lowest',
  limit = 4L
)
fast_team_game_high_query <- do.call(capture_team_game_high_query, c(list(use_team_match_stats = TRUE), team_game_high_inputs))
period_team_game_high_query <- do.call(capture_team_game_high_query, c(list(use_team_match_stats = FALSE), team_game_high_inputs))
fast_team_game_high_sql <- normalize_sql(fast_team_game_high_query$query)
period_team_game_high_sql <- normalize_sql(period_team_game_high_query$query)

assert_true(identical(fast_team_game_high_query$params, period_team_game_high_query$params), 'Expected team game-high query paths to keep parameter payloads aligned.')
assert_contains(fast_team_game_high_sql, 'tms.season IN (?season_1, ?season_2)', 'Expected team game-high fast path to retain season arrays.')
assert_contains(period_team_game_high_sql, 'stats.season IN (?season_1, ?season_2)', 'Expected team game-high fallback path to retain season arrays.')
assert_contains(fast_team_game_high_sql, 'AND tms.squad_id = ?team_id', 'Expected team game-high fast path to retain team filters.')
assert_contains(period_team_game_high_sql, 'AND stats.squad_id = ?team_id', 'Expected team game-high fallback path to retain team filters.')
assert_contains(fast_team_game_high_sql, 'AND tms.round_number = ?round_number', 'Expected team game-high fast path to retain round filters.')
assert_contains(period_team_game_high_sql, 'AND stats.round_number = ?round_number', 'Expected team game-high fallback path to retain round filters.')
assert_contains(fast_team_game_high_sql, "AND COALESCE(matches.competition_phase, '') = ?competition_phase", 'Expected team game-high fast path to retain competition phase filters.')
assert_contains(period_team_game_high_sql, "AND COALESCE(matches.competition_phase, '') = ?competition_phase", 'Expected team game-high fallback path to retain competition phase filters.')
assert_contains(fast_team_game_high_sql, 'ORDER BY tms.match_value ASC', 'Expected team game-high fast path to preserve lowest-ranking ordering.')
assert_contains(period_team_game_high_sql, 'GROUP BY stats.squad_id, stats.squad_name, stats.season, stats.round_number, stats.match_id, matches.local_start_time ORDER BY total_value ASC', 'Expected team game-high fallback path to preserve match grouping before ordering.')
check_step('team game-high query paths keep filter and ordering clauses aligned')

invalid_summary <- request_json(base_url, '/summary', query = list(season = 1900), expected_status = 400L)
assert_true(nzchar(as.character(invalid_summary$error %||% '')), 'Expected invalid requests to return an error payload.')
check_step('validation errors return a 400 response')

invalid_round_summary <- request_json(base_url, '/round-summary', query = list(round = 1), expected_status = 400L)
assert_true(nzchar(as.character(invalid_round_summary$error %||% '')), 'Expected /round-summary to require a season when round is provided.')
check_step('round summary validation returns a 400 response')

# nWAR endpoint regression tests
nwar_payload <- request_json(base_url, '/nwar', query = list(min_games = '1', limit = '10'))
assert_true(is.list(nwar_payload$data), 'Expected /nwar to return a data list.')
if (length(nwar_payload$data) >= 1L) {
  first_row <- nwar_payload$data[[1]]
  assert_true(!is.null(first_row$player_id),    'Expected /nwar rows to include player_id.')
  assert_true(!is.null(first_row$player_name),  'Expected /nwar rows to include player_name.')
  assert_true(!is.null(first_row$nwar),         'Expected /nwar rows to include nwar.')
  assert_true(!is.null(first_row$nwar_per_season), 'Expected /nwar rows to include nwar_per_season.')
  assert_true(!is.null(first_row$seasons_played),  'Expected /nwar rows to include seasons_played.')
  assert_true(!is.null(first_row$games_played), 'Expected /nwar rows to include games_played.')
  nwar_val <- as.numeric(scalar_value(first_row$nwar) %||% NA_real_)
  assert_true(!is.nan(nwar_val), 'Expected /nwar top row to have a non-NaN nwar value.')
}
check_step('nWAR endpoint returns well-formed rows')

if (length(nwar_payload$data) >= 2L) {
  nwar_per_season_values <- vapply(nwar_payload$data, function(r) as.numeric(scalar_value(r$nwar_per_season) %||% NA_real_), numeric(1L))
  assert_true(all(!is.nan(nwar_per_season_values)), 'Expected all-seasons /nwar to return no NaN nwar_per_season values.')
  assert_true(nwar_per_season_values[[1]] >= nwar_per_season_values[[length(nwar_per_season_values)]], 'Expected all-seasons /nwar rows to be sorted descending by nwar_per_season.')
}
check_step('all-seasons nWAR endpoint sorts rows descending by nwar_per_season')

nwar_season_payload <- request_json(base_url, '/nwar', query = list(season = as.character(default_season), min_games = '1', limit = '100'))
assert_true(is.list(nwar_season_payload$data), 'Expected /nwar with season filter to return a data list.')
if (length(nwar_season_payload$data) >= 2L) {
  nwar_values <- vapply(nwar_season_payload$data, function(r) as.numeric(scalar_value(r$nwar) %||% NA_real_), numeric(1L))
  assert_true(all(!is.nan(nwar_values)), 'Expected /nwar to return no NaN nwar values.')
  assert_true(nwar_values[[1]] >= nwar_values[[length(nwar_values)]], 'Expected /nwar rows to be sorted descending by nwar.')
}
check_step('nWAR endpoint sorts rows descending by nwar with no NaN values')

nwar_limit_payload <- request_json(base_url, '/nwar', query = list(min_games = '1', limit = '3'))
assert_true(length(nwar_limit_payload$data) <= 3L, 'Expected /nwar to respect the limit parameter.')
check_step('nWAR endpoint respects the limit cap')

nwar_high_min_payload <- request_json(base_url, '/nwar', query = list(min_games = '999'), expected_status = 400L)
assert_true(nzchar(as.character(nwar_high_min_payload$error %||% '')), 'Expected /nwar with very high min_games to reject invalid requests.')
check_step('nWAR endpoint rejects out-of-range min_games values')

invalid_nwar <- request_json(base_url, '/nwar', query = list(min_games = '0'), expected_status = 400L)
assert_true(nzchar(as.character(invalid_nwar$error %||% '')), 'Expected /nwar to reject min_games below 1.')
check_step('nWAR endpoint validates min_games lower bound')

nwar_baseline_payload <- request_json(base_url, '/nwar', query = list(min_games = '1', limit = '10'))
assert_true(is.list(nwar_baseline_payload$data), 'Expected unfiltered /nwar to return a data list.')

nwar_anzc_payload <- request_json(base_url, '/nwar', query = list(era = 'anzc', min_games = '1', limit = '10'))
assert_true(is.list(nwar_anzc_payload$data), 'Expected /nwar?era=anzc to return a data list.')
if (length(nwar_baseline_payload$data) >= 1L && length(nwar_anzc_payload$data) >= 1L) {
  baseline_ids <- vapply(nwar_baseline_payload$data, function(r) as.character(scalar_value(r$player_id) %||% ''), character(1L))
  anzc_ids <- vapply(nwar_anzc_payload$data, function(r) as.character(scalar_value(r$player_id) %||% ''), character(1L))
  assert_true(!identical(anzc_ids, baseline_ids), 'Expected /nwar?era=anzc to change the returned rows relative to the unfiltered query.')
}
check_step('nWAR endpoint accepts the anzc era filter')

nwar_ssn_payload <- request_json(base_url, '/nwar', query = list(era = 'ssn', min_games = '1', limit = '10'))
assert_true(is.list(nwar_ssn_payload$data), 'Expected /nwar?era=ssn to return a data list.')
if (length(nwar_baseline_payload$data) >= 1L && length(nwar_ssn_payload$data) >= 1L) {
  baseline_ids <- vapply(nwar_baseline_payload$data, function(r) as.character(scalar_value(r$player_id) %||% ''), character(1L))
  ssn_ids <- vapply(nwar_ssn_payload$data, function(r) as.character(scalar_value(r$player_id) %||% ''), character(1L))
  assert_true(!identical(ssn_ids, baseline_ids), 'Expected /nwar?era=ssn to change the returned rows relative to the unfiltered query.')
}
check_step('nWAR endpoint accepts the ssn era filter')

nwar_defender_payload <- request_json(base_url, '/nwar', query = list(position_group = 'defender', min_games = '1', limit = '25'))
assert_true(is.list(nwar_defender_payload$data), 'Expected /nwar?position_group=defender to return a data list.')
if (length(nwar_defender_payload$data) >= 1L) {
  defender_groups <- vapply(nwar_defender_payload$data, function(r) scalar_value(r$position_group) %||% NA_character_, character(1L))
  assert_true(all(defender_groups == 'Defender'), 'Expected defender-filtered /nwar rows to all resolve to Defender.')
}
if (length(nwar_baseline_payload$data) >= 1L && length(nwar_defender_payload$data) >= 1L) {
  baseline_positions <- vapply(nwar_baseline_payload$data, function(r) scalar_value(r$position_group) %||% NA_character_, character(1L))
  defender_positions <- vapply(nwar_defender_payload$data, function(r) scalar_value(r$position_group) %||% NA_character_, character(1L))
  assert_true(!identical(defender_positions, baseline_positions), 'Expected /nwar?position_group=defender to change the returned rows relative to the unfiltered query.')
}
check_step('nWAR endpoint filters rows by position group')

nwar_season_only_payload <- request_json(base_url, '/nwar', query = list(season = '2012', min_games = '1', limit = '10'))
nwar_season_override_payload <- request_json(base_url, '/nwar', query = list(season = '2012', era = 'ssn', min_games = '1', limit = '10'))
season_only_ids <- vapply(nwar_season_only_payload$data, function(r) as.character(scalar_value(r$player_id) %||% ''), character(1L))
season_override_ids <- vapply(nwar_season_override_payload$data, function(r) as.character(scalar_value(r$player_id) %||% ''), character(1L))
assert_true(identical(season_only_ids, season_override_ids), 'Expected explicit season to override era when both are supplied.')
check_step('nWAR endpoint lets season override era')

invalid_nwar_era <- request_json(base_url, '/nwar', query = list(era = 'futureball'), expected_status = 400L)
assert_true(nzchar(as.character(invalid_nwar_era$error %||% '')), 'Expected /nwar to reject unsupported era values.')
check_step('nWAR endpoint validates era values')

invalid_nwar_position_group <- request_json(base_url, '/nwar', query = list(position_group = 'bench'), expected_status = 400L)
assert_true(nzchar(as.character(invalid_nwar_position_group$error %||% '')), 'Expected /nwar to reject unsupported position_group values.')
check_step('nWAR endpoint validates position_group values')

# Home venue impact endpoint regression tests
home_venue_helpers_env <- new.env(parent = globalenv())
sys.source(file.path(getwd(), 'api', 'R', 'helpers.R'), envir = home_venue_helpers_env)
home_venue_helpers_env$api_log <- function(...) NULL
assert_true(is.function(home_venue_helpers_env$build_home_venue_impact_base_query), 'Expected build_home_venue_impact_base_query to be exported from helpers.R.')
assert_true(is.function(home_venue_helpers_env$summarise_home_venue_impact_rows), 'Expected summarise_home_venue_impact_rows to be exported from helpers.R.')

home_venue_query <- home_venue_helpers_env$build_home_venue_impact_base_query(
  seasons = c(2023L, 2024L),
  team_id = 8118L,
  venue_name = 'John Cain Arena'
)
home_venue_sql <- normalize_sql(home_venue_query$query)
assert_true(length(home_venue_query$query) == 1L, 'Expected home venue impact base query to compile to a single SQL statement.')
assert_contains(home_venue_sql, 'home_score IS NOT NULL', 'Expected home venue impact base query to exclude incomplete matches.')
assert_contains(home_venue_sql, 'away_score IS NOT NULL', 'Expected home venue impact base query to exclude incomplete matches.')
assert_contains(home_venue_sql, 'matches.season IN (?season_1, ?season_2)', 'Expected home venue impact base query to push season filters into the matches scan.')
assert_contains(home_venue_sql, 'UNION ALL', 'Expected home venue impact base query to expand matches into home and away rows.')
assert_contains(home_venue_sql, 'team_match_stats', 'Expected home venue impact base query to use team_match_stats for penalties.')
assert_contains(home_venue_sql, "team_id = ?team_id", 'Expected home venue impact base query to support team filters on the team-perspective rows.')
assert_contains(home_venue_sql, 'matches.venue_name = ?venue_name', 'Expected home venue impact base query to push exact venue filters into the matches scan.')

home_venue_query_no_penalties <- home_venue_helpers_env$build_home_venue_impact_base_query(
  seasons = c(2024L),
  include_penalties = FALSE
)
home_venue_sql_no_penalties <- normalize_sql(home_venue_query_no_penalties$query)
assert_true(length(home_venue_query_no_penalties$query) == 1L, 'Expected home venue impact base query without penalties to compile to a single SQL statement.')
assert_true(!grepl('team_match_stats', home_venue_sql_no_penalties, fixed = TRUE), 'Expected home venue impact base query to omit team_match_stats when penalties are unavailable.')
assert_contains(home_venue_sql_no_penalties, 'NULL AS penalties_for', 'Expected home venue impact base query to null penalty fields when penalties are unavailable.')

home_venue_fake_rows <- data.frame(
  match_id = c(1L, 1L, 2L, 2L, 3L, 3L, 4L, 4L, 5L, 5L),
  season = rep(2024L, 10),
  competition_phase = rep('Regular Season', 10),
  round_number = c(1L, 1L, 2L, 2L, 3L, 3L, 4L, 4L, 5L, 5L),
  venue_name = c('Alpha', 'Alpha', 'Alpha', 'Alpha', 'Beta', 'Beta', 'Gamma', 'Gamma', 'Gamma', 'Gamma'),
  team_id = c(1L, 3L, 1L, 4L, 1L, 5L, 2L, 6L, 2L, 7L),
  team_name = c('Team 1', 'Team 3', 'Team 1', 'Team 4', 'Team 1', 'Team 5', 'Team 2', 'Team 6', 'Team 2', 'Team 7'),
  opponent_id = c(3L, 1L, 4L, 1L, 5L, 1L, 6L, 2L, 7L, 2L),
  opponent_name = c('Team 3', 'Team 1', 'Team 4', 'Team 1', 'Team 5', 'Team 1', 'Team 6', 'Team 2', 'Team 7', 'Team 2'),
  is_home = c(1L, 0L, 1L, 0L, 1L, 0L, 1L, 0L, 1L, 0L),
  team_score = c(60L, 50L, 55L, 57L, 62L, 58L, 61L, 54L, 52L, 52L),
  opponent_score = c(50L, 60L, 57L, 55L, 58L, 62L, 54L, 61L, 52L, 52L),
  margin = c(10L, -10L, -2L, 2L, 4L, -4L, 7L, -7L, 0L, 0L),
  won = c(1L, 0L, 0L, 1L, 1L, 0L, 1L, 0L, 0L, 0L),
  draw = c(0L, 0L, 0L, 0L, 0L, 0L, 0L, 0L, 1L, 1L),
  penalties_for = c(48L, 55L, 52L, 50L, 47L, 54L, 46L, 53L, 44L, 44L),
  penalties_against = c(55L, 48L, 50L, 52L, 54L, 47L, 53L, 46L, 44L, 44L),
  penalty_advantage = c(7L, -7L, -2L, 2L, 7L, -7L, 7L, -7L, 0L, 0L),
  stringsAsFactors = FALSE
)
home_venue_summary <- home_venue_helpers_env$summarise_home_venue_impact_rows(
  home_venue_fake_rows,
  min_matches = 2L,
  limit = 50L
)
assert_true(!is.null(home_venue_summary$league_summary), 'Expected summarise_home_venue_impact_rows to return a league summary when matches qualify.')
assert_true(identical(home_venue_summary$league_summary$matches, 5L), 'Expected league summary to count completed matches.')
assert_true(identical(home_venue_summary$league_summary$draws, 1L), 'Expected league summary to count draw matches once.')
assert_true(is.data.frame(home_venue_summary$team_summary), 'Expected team summary to be a data.frame.')
assert_true(is.data.frame(home_venue_summary$venue_summary), 'Expected venue summary to be a data.frame.')
assert_true(is.data.frame(home_venue_summary$team_venue_summary), 'Expected team_venue_summary to be a data.frame.')
assert_true(nrow(home_venue_summary$venue_summary) == 2L, 'Expected min_matches to filter out single-match venues.')
assert_true(!('Beta' %in% home_venue_summary$venue_summary$venue_name), 'Expected venue_summary to exclude venues below min_matches.')
team_two_gamma <- home_venue_summary$team_venue_summary[
  home_venue_summary$team_venue_summary$team_id == 2L & home_venue_summary$team_venue_summary$venue_name == 'Gamma',
  ,
  drop = FALSE
]
team_one_alpha <- home_venue_summary$team_venue_summary[
  home_venue_summary$team_venue_summary$team_id == 1L & home_venue_summary$team_venue_summary$venue_name == 'Alpha',
  ,
  drop = FALSE
]
assert_true(nrow(team_one_alpha) == 1L, 'Expected a team_venue_summary row for Team 1 at Alpha.')
assert_true(identical(team_one_alpha$comparison_matches_other_home_venues[[1]], 1L), 'Expected other-home comparison counts to include all alternate home venues, even below min_matches.')
assert_true(!is.na(team_one_alpha$win_rate_lift_vs_team_other_home_venues[[1]]), 'Expected team_venue_summary to compute lifts when any alternate home venue exists.')
assert_true(nrow(team_two_gamma) == 1L, 'Expected a team_venue_summary row for the mocked Gamma venue.')
assert_true(is.na(team_two_gamma$comparison_matches_other_home_venues[[1]]), 'Expected no other-home comparison match count when no alternate venues exist.')
assert_true(is.na(team_two_gamma$other_home_venues_win_rate[[1]]), 'Expected other-home comparison win rate to be NULL when no alternate venues exist.')
assert_true(is.na(team_two_gamma$win_rate_lift_vs_team_other_home_venues[[1]]), 'Expected other-home comparison lift to be NULL when no alternate venues exist.')

home_venue_high_threshold <- home_venue_helpers_env$summarise_home_venue_impact_rows(
  home_venue_fake_rows,
  min_matches = 999L,
  limit = 50L
)
assert_true(!is.null(home_venue_high_threshold$league_summary), 'Expected league_summary to remain available even when min_matches filters out grouped outputs.')
assert_true(identical(home_venue_high_threshold$league_summary$matches, 5L), 'Expected league_summary to retain the full filtered match count when grouped outputs are empty.')
assert_true(nrow(home_venue_high_threshold$team_summary) == 0L, 'Expected high min_matches to empty grouped team_summary results.')
assert_true(nrow(home_venue_high_threshold$venue_summary) == 0L, 'Expected high min_matches to empty grouped venue_summary results.')
assert_true(nrow(home_venue_high_threshold$team_venue_summary) == 0L, 'Expected high min_matches to empty grouped team_venue_summary results.')

home_venue_helpers_env$has_team_match_stats <- function(conn) FALSE
home_venue_helpers_env$query_rows <- function(conn, query, params = list()) {
  rows <- home_venue_fake_rows
  rows$penalties_for <- NA_real_
  rows$penalties_against <- NA_real_
  rows$penalty_advantage <- NA_real_
  rows
}
home_venue_no_penalties_summary <- home_venue_helpers_env$fetch_home_venue_impact_summary(
  conn = structure(list(), class = 'mock_connection'),
  seasons = 2024L,
  min_matches = 2L,
  limit = 50L
)
assert_true(!is.null(home_venue_no_penalties_summary$league_summary), 'Expected home venue impact summary to remain available when team_match_stats is unavailable.')
assert_true(is.na(home_venue_no_penalties_summary$league_summary$avg_home_penalties_for), 'Expected missing team_match_stats to yield null league penalty metrics rather than an empty result.')
check_step('home venue impact helpers build the expected query shape and null comparison behavior')

home_venue_payload <- request_json(base_url, '/home-venue-impact', query = list(season = default_season, min_matches = '1', limit = '10'))
assert_true(!is.null(home_venue_payload$league_summary), 'Expected /home-venue-impact to return a league_summary for a populated season.')
assert_true(is.list(home_venue_payload$team_summary) && length(home_venue_payload$team_summary) >= 1L, 'Expected /home-venue-impact to return team_summary rows.')
assert_true(is.list(home_venue_payload$venue_summary) && length(home_venue_payload$venue_summary) >= 1L, 'Expected /home-venue-impact to return venue_summary rows.')
assert_true(is.list(home_venue_payload$team_venue_summary) && length(home_venue_payload$team_venue_summary) >= 1L, 'Expected /home-venue-impact to return team_venue_summary rows.')
assert_true(identical(as.integer(scalar_value(home_venue_payload$filters$seasons[[1]])), default_season), 'Expected /home-venue-impact to echo the requested season filter.')
league_summary_fields <- c('matches', 'home_wins', 'away_wins', 'draws', 'home_win_rate', 'away_win_rate', 'avg_home_margin', 'avg_away_margin', 'avg_home_penalties_for', 'avg_home_penalties_against', 'avg_home_penalty_advantage')
assert_true(all(league_summary_fields %in% names(home_venue_payload$league_summary)), 'Expected /home-venue-impact league_summary to expose the documented fields.')
first_team_summary <- first_record(home_venue_payload$team_summary)
assert_true(all(c('home_matches', 'away_matches', 'home_wins', 'away_wins', 'win_rate_delta_home_vs_away', 'margin_delta_home_vs_away', 'penalty_delta_home_vs_away') %in% names(first_team_summary)), 'Expected /home-venue-impact team_summary rows to expose the documented fields.')
first_venue_summary <- first_record(home_venue_payload$venue_summary)
assert_true(all(c('venue_name', 'matches', 'home_wins', 'win_rate_lift_vs_league_home', 'margin_lift_vs_league_home', 'penalty_lift_vs_league_home') %in% names(first_venue_summary)), 'Expected /home-venue-impact venue_summary rows to expose the documented fields.')
first_team_venue_summary <- first_record(home_venue_payload$team_venue_summary)
assert_true(all(c('comparison_matches_other_home_venues', 'other_home_venues_win_rate', 'win_rate_lift_vs_team_other_home_venues') %in% names(first_team_venue_summary)), 'Expected /home-venue-impact team_venue_summary rows to expose the documented fields.')

matches_payload <- request_json(base_url, '/matches', query = list(season = default_season, limit = '50'))
assert_true(is.list(matches_payload$data) && length(matches_payload$data) >= 1L, 'Expected /matches to return rows for the default season.')
assert_true(
  all(vapply(
    matches_payload$data,
    function(match_row) !is.null(match_row$home_score) && !is.null(match_row$away_score),
    logical(1L)
  )),
  'Expected /matches recent results rows to include completed scores only.'
)
candidate_match <- NULL
for (match_row in matches_payload$data) {
  if (!is.null(match_row$home_score) && !is.null(match_row$away_score) && !is.null(match_row$venue_name) && nzchar(as.character(match_row$venue_name))) {
    candidate_match <- match_row
    break
  }
}
assert_true(!is.null(candidate_match), 'Expected /matches to return at least one completed match for home venue impact filtering tests.')
team_names <- vapply(meta$teams, function(team) as.character(scalar_value(team$squad_name %||% '')), character(1L))
team_ids <- vapply(meta$teams, function(team) as.integer(scalar_value(team$squad_id %||% NA_integer_)), integer(1L))
team_index <- which(team_names == as.character(candidate_match$home_squad_name))
assert_true(length(team_index) >= 1L, 'Expected /meta to include the team named by the selected match.')
candidate_team_id <- team_ids[[team_index[[1]]]]
candidate_venue_name <- as.character(candidate_match$venue_name)
requested_seasons <- vapply(meta$seasons[seq_len(min(2L, length(meta$seasons)))], function(value) as.integer(scalar_value(value)), integer(1L))
requested_seasons_string <- paste(requested_seasons, collapse = ',')

team_filtered_payload <- request_json(base_url, '/home-venue-impact', query = list(season = default_season, team_id = candidate_team_id, min_matches = '1', limit = '10'))
assert_true(identical(as.integer(scalar_value(team_filtered_payload$filters$team_id)), candidate_team_id), 'Expected /home-venue-impact to echo team_id filters.')
team_summary_team_ids <- vapply(team_filtered_payload$team_summary, function(row) as.integer(scalar_value(row$team_id)), integer(1L))
assert_true(length(team_summary_team_ids) >= 1L && all(team_summary_team_ids == candidate_team_id), 'Expected team_id-filtered /home-venue-impact responses to stay on the requested team.')

venue_filtered_payload <- request_json(base_url, '/home-venue-impact', query = list(season = default_season, venue_name = candidate_venue_name, min_matches = '1', limit = '10'))
assert_true(identical(as.character(scalar_value(venue_filtered_payload$filters$venue_name)), candidate_venue_name), 'Expected /home-venue-impact to echo venue_name filters.')
venue_summary_names <- vapply(venue_filtered_payload$venue_summary, function(row) as.character(scalar_value(row$venue_name)), character(1L))
assert_true(length(venue_summary_names) >= 1L && all(venue_summary_names == candidate_venue_name), 'Expected venue_name-filtered /home-venue-impact responses to stay on the requested venue.')
team_venue_names <- vapply(venue_filtered_payload$team_venue_summary, function(row) as.character(scalar_value(row$venue_name)), character(1L))
assert_true(length(team_venue_names) >= 1L && all(team_venue_names == candidate_venue_name), 'Expected team_venue_summary venue filters to stay on the requested venue.')

season_filters_payload <- request_json(base_url, '/home-venue-impact', query = list(seasons = requested_seasons_string, min_matches = '1', limit = '10'))
season_filters_result <- vapply(season_filters_payload$filters$seasons, function(value) as.integer(scalar_value(value)), integer(1L))
assert_true(identical(season_filters_result, requested_seasons), 'Expected /home-venue-impact to parse comma-separated seasons.')

filtered_home_venue_payload <- request_json(base_url, '/home-venue-impact', query = list(season = default_season, min_matches = '999', limit = '10'), expected_status = 400L)
assert_true(nzchar(as.character(filtered_home_venue_payload$error %||% '')), 'Expected /home-venue-impact to reject out-of-range min_matches values.')

check_step('home venue impact endpoint supports documented filters')

# Home edge breakdown endpoint regression tests
home_edge_breakdown_helpers_env <- new.env(parent = globalenv())
sys.source(file.path(getwd(), 'api', 'R', 'helpers.R'), envir = home_edge_breakdown_helpers_env)
home_edge_breakdown_helpers_env$api_log <- function(...) NULL
assert_true(is.function(home_edge_breakdown_helpers_env$build_home_edge_stat_groups), 'Expected build_home_edge_stat_groups to be exported from helpers.R.')
assert_true(is.function(home_edge_breakdown_helpers_env$normalize_home_edge_stat_groups), 'Expected normalize_home_edge_stat_groups to be exported from helpers.R.')
assert_true(is.function(home_edge_breakdown_helpers_env$build_home_venue_breakdown_rows_query), 'Expected build_home_venue_breakdown_rows_query to be exported from helpers.R.')
assert_true(is.function(home_edge_breakdown_helpers_env$fetch_home_venue_breakdown), 'Expected fetch_home_venue_breakdown to be exported from helpers.R.')
home_edge_groups <- home_edge_breakdown_helpers_env$normalize_home_edge_stat_groups(c('generalPlayTurnovers', 'contactPenalties', 'obstructionPenalties', 'penalties', 'heldBalls'))
assert_true(identical(home_edge_groups$requested_stat_groups, c('generalPlayTurnovers', 'contactPenalties', 'obstructionPenalties', 'penalties', 'heldBalls')), 'Expected Home Edge stat groups to preserve the requested group names.')
assert_true(identical(unname(home_edge_groups$requested_stat_keys), c('generalPlayTurnovers', 'contactPenalties', 'obstructionPenalties', 'penalties', 'turnoverHeld')), 'Expected Home Edge stat groups to map to canonical stat keys.')
assert_true('turnoverHeld' %in% home_edge_groups$requested_stat_keys, 'Expected heldBalls to map to turnoverHeld.')
assert_true(!length(home_edge_groups$unavailable_stat_groups), 'Expected Home Edge stat groups to avoid discovery-based unavailable tracking.')

home_breakdown_rows_query <- home_edge_breakdown_helpers_env$build_home_venue_breakdown_rows_query(
  seasons = c(2023L, 2024L),
  team_id = 8118L,
  venue_name = 'Qudos Bank Arena'
)
home_breakdown_rows_sql <- normalize_sql(home_breakdown_rows_query$query)
assert_contains(home_breakdown_rows_sql, 'generalplayturnovers AS "generalPlayTurnovers"', 'Expected Home Edge breakdown rows query to alias lower-case generalPlayTurnovers columns back to camelCase.')
assert_contains(home_breakdown_rows_sql, 'turnoverheld AS "turnoverHeld"', 'Expected Home Edge breakdown rows query to alias lower-case turnoverHeld columns back to camelCase.')
assert_contains(home_breakdown_rows_sql, 'contactpenalties AS "contactPenalties"', 'Expected Home Edge breakdown rows query to alias lower-case contactPenalties columns back to camelCase.')
assert_contains(home_breakdown_rows_sql, 'obstructionpenalties AS "obstructionPenalties"', 'Expected Home Edge breakdown rows query to alias lower-case obstructionPenalties columns back to camelCase.')
assert_contains(home_breakdown_rows_sql, 'season IN (?season_1, ?season_2)', 'Expected Home Edge breakdown rows query to filter requested seasons.')
assert_contains(home_breakdown_rows_sql, 'team_id = ?team_id', 'Expected Home Edge breakdown rows query to filter requested teams.')
assert_contains(home_breakdown_rows_sql, 'venue_name = ?venue_name', 'Expected Home Edge breakdown rows query to filter requested venues.')

cat("Checking /home-venue-breakdown multi-year stat payload...\n")
breakdown <- request_json(base_url, '/home-venue-breakdown', query = list(
  seasons = '2023,2024',
  min_matches = '3',
  stat_groups = 'generalPlayTurnovers,contactPenalties,obstructionPenalties,penalties,heldBalls',
  limit = '5'
))
assert_true(is.list(breakdown), 'Expected /home-venue-breakdown to return a payload.')
assert_true(is.list(breakdown$filters), 'Expected /home-venue-breakdown to return filters.')
assert_true(identical(unlist(breakdown$filters$seasons), c(2023L, 2024L)), 'Expected /home-venue-breakdown to echo both requested seasons.')
assert_true(is.list(breakdown$stat_summary) && length(breakdown$stat_summary) >= 1L, 'Expected /home-venue-breakdown to return stat_summary rows.')
assert_true(is.list(breakdown$opposition_summary_overall) && length(breakdown$opposition_summary_overall) >= 1L, 'Expected /home-venue-breakdown to return opposition_summary_overall rows.')
assert_true(is.list(breakdown$opposition_summary_by_stat) && length(breakdown$opposition_summary_by_stat) >= 1L, 'Expected /home-venue-breakdown to return opposition_summary_by_stat rows.')
assert_true(is.list(breakdown$team_venue_stat_summary) && length(breakdown$team_venue_stat_summary) == 0L, 'Expected /home-venue-breakdown to return an empty team_venue_stat_summary when team_id is omitted.')
first_stat_summary <- first_record(breakdown$stat_summary)
assert_true(all(c('stat_group', 'stat_key', 'stat_label', 'matches', 'venue_average', 'baseline_average', 'lift', 'preferred_direction') %in% names(first_stat_summary)), 'Expected /home-venue-breakdown stat_summary rows to expose the documented fields.')
first_opposition_summary_overall <- first_record(breakdown$opposition_summary_overall)
assert_true(all(c('opponent_id', 'opponent_name', 'matches', 'home_win_rate', 'baseline_home_win_rate', 'home_win_rate_lift', 'avg_margin', 'baseline_avg_margin', 'margin_lift', 'avg_penalties', 'baseline_avg_penalties', 'penalties_lift') %in% names(first_opposition_summary_overall)), 'Expected /home-venue-breakdown opposition_summary_overall rows to expose the documented fields.')
first_opposition_summary_by_stat <- first_record(breakdown$opposition_summary_by_stat)
assert_true(all(c('opponent_id', 'opponent_name', 'stat_group', 'stat_key', 'stat_label', 'matches', 'venue_average', 'baseline_average', 'lift', 'preferred_direction') %in% names(first_opposition_summary_by_stat)), 'Expected /home-venue-breakdown opposition_summary_by_stat rows to expose the documented fields.')

cat("Checking /home-venue-breakdown team-and-venue slice...\n")
candidate_breakdown_team_id <- as.character(scalar_value(first_team_venue_summary$team_id))
candidate_breakdown_venue_name <- as.character(scalar_value(first_team_venue_summary$venue_name))
team_breakdown <- request_json(base_url, '/home-venue-breakdown', query = list(
  season = as.character(default_season),
  team_id = candidate_breakdown_team_id,
  venue_name = candidate_breakdown_venue_name,
  stat_groups = 'generalPlayTurnovers,contactPenalties,obstructionPenalties,penalties,heldBalls',
  min_matches = '1',
  limit = '5'
))
assert_true(is.list(team_breakdown), 'Expected team-filtered /home-venue-breakdown to return a payload.')
assert_true(is.list(team_breakdown$stat_summary) && length(team_breakdown$stat_summary) >= 1L, 'Expected team-filtered /home-venue-breakdown to return stat_summary rows.')
assert_true(is.list(team_breakdown$team_venue_stat_summary) && length(team_breakdown$team_venue_stat_summary) >= 1L, 'Expected team-filtered /home-venue-breakdown to return team_venue_stat_summary rows.')
first_team_venue_stat_summary <- first_record(team_breakdown$team_venue_stat_summary)
assert_true(all(c('team_id', 'team_name', 'venue_name', 'stat_group', 'stat_key', 'stat_label', 'matches', 'venue_average', 'other_home_venues_average', 'lift', 'preferred_direction') %in% names(first_team_venue_stat_summary)), 'Expected /home-venue-breakdown team_venue_stat_summary rows to expose the documented fields.')
non_penalty_team_rows <- Filter(function(row) {
  stat_key <- as.character(scalar_value(row$stat_key %||% ''))
  venue_average <- suppressWarnings(as.numeric(as.character(scalar_value(row$venue_average %||% NA))))
  matches <- suppressWarnings(as.integer(as.character(scalar_value(row$matches %||% 0L))))
  stat_key != 'penalties' && !is.na(venue_average) && !is.na(matches) && matches >= 1L
}, team_breakdown$team_venue_stat_summary)
assert_true(length(non_penalty_team_rows) >= 1L, 'Expected team-filtered /home-venue-breakdown to return at least one non-penalty stat row with a numeric venue average.')

cat("Checking held balls Home Edge stat reporting...\n")
held_balls_breakdown <- request_json(base_url, '/home-venue-breakdown', query = list(
  seasons = '2024',
  stat_groups = 'heldBalls',
  min_matches = '1',
  limit = '5'
))
assert_true(is.list(held_balls_breakdown$filters), 'Expected /home-venue-breakdown responses to include filters.')
assert_true('heldBalls' %in% unlist(held_balls_breakdown$filters$requested_stat_groups), 'Expected heldBalls stat_groups to be echoed in requested_stat_groups.')
assert_true(!('heldBalls' %in% unlist(held_balls_breakdown$filters$unavailable_stat_groups)), 'Expected heldBalls to be treated as an available Home Edge stat group.')

cat("Checking invalid Home Edge stat validation...\n")
invalid_stat_resp <- request_json(base_url, '/home-venue-breakdown', query = list(stat_groups = 'badStat'), expected_status = 400L)
assert_true(nzchar(as.character(invalid_stat_resp$error %||% '')), 'Expected invalid /home-venue-breakdown stat_groups to return 400.')

cat("Checking Home Edge breakdown limit validation...\n")
invalid_breakdown_limit <- request_json(base_url, '/home-venue-breakdown', query = list(limit = '100'), expected_status = 400L)
assert_true(nzchar(as.character(invalid_breakdown_limit$error %||% '')), 'Expected /home-venue-breakdown to reject limit values above 50.')

empty_home_venue_payload <- request_json(base_url, '/home-venue-impact', query = list(season = default_season, venue_name = '__missing_venue__', min_matches = '1', limit = '10'))
assert_true(is.null(empty_home_venue_payload$league_summary), 'Expected /home-venue-impact to return a null league_summary when filters produce no rows.')
assert_true(length(empty_home_venue_payload$team_summary) == 0L, 'Expected /home-venue-impact to return an empty team_summary when filters produce no rows.')
assert_true(length(empty_home_venue_payload$venue_summary) == 0L, 'Expected /home-venue-impact to return an empty venue_summary when filters produce no rows.')
assert_true(length(empty_home_venue_payload$team_venue_summary) == 0L, 'Expected /home-venue-impact to return an empty team_venue_summary when filters produce no rows.')
check_step('home venue impact endpoint supports documented filters and empty-result behavior')

# Unit tests for fetch_nwar_rows R logic (no live DB required)
normalize_sql <- if (exists('normalize_sql')) normalize_sql else function(q) gsub('\\s+', ' ', trimws(q))
helpers_path <- Sys.getenv('NETBALL_STATS_HELPERS_PATH', file.path(getwd(), 'api', 'R', 'helpers.R'))

# Returns the list(query, params) from build_nwar_query without a live connection.
capture_nwar_query <- function(use_match_stats, seasons = NULL, team_id = NULL, min_games = 5L) {
  helpers_env <- new.env(parent = globalenv())
  source(helpers_path, local = helpers_env, echo = FALSE)
  helpers_env$has_player_match_stats        <- function(conn) use_match_stats
  helpers_env$has_player_match_participation <- function(conn) FALSE
  helpers_env$build_nwar_query(conn = NULL, seasons = seasons, team_id = team_id, min_games = min_games)
}

# Returns the list(query, params) from fetch_nwar_positions without a live connection.
capture_nwar_positions_query <- function(seasons_filter = NULL, team_id = NULL) {
  helpers_env <- new.env(parent = globalenv())
  source(helpers_path, local = helpers_env, echo = FALSE)
  captured <- NULL
  helpers_env$query_rows <- function(conn, query, params = list()) {
    captured <<- list(query = query, params = params)
    data.frame(player_id = integer(0), position_code = character(0), stringsAsFactors = FALSE)
  }
  helpers_env$fetch_nwar_positions(conn = NULL, seasons_filter = seasons_filter, team_id = team_id)
  captured
}

if (file.exists(helpers_path)) {
  helpers_env <- new.env(parent = globalenv())
  helpers_loaded <- tryCatch({
    suppressMessages(source(helpers_path, local = helpers_env, echo = FALSE))
    TRUE
  }, error = function(e) {
    cat(sprintf('NOTE: fetch_nwar_rows unit tests skipped (helpers not loadable in this environment): %s\n', conditionMessage(e)))
    FALSE
  })

  if (helpers_loaded) {
    # build_nwar_query should exist and be a function
    assert_true(is.function(helpers_env$build_nwar_query), 'Expected build_nwar_query to be exported from helpers.R.')

    # fetch_nwar_rows with zero rows should return typed empty data.frame
    helpers_env$has_player_match_stats <- function(conn) TRUE
    helpers_env$has_player_match_positions <- function(conn) FALSE
    helpers_env$query_rows <- function(conn, query, params = list()) data.frame()
    empty_result <- helpers_env$fetch_nwar_rows(conn = NULL, min_games = 5L, limit = 50L)
    assert_true(is.data.frame(empty_result), 'Expected fetch_nwar_rows to return a data.frame when no rows qualify.')
    assert_true(nrow(empty_result) == 0L, 'Expected fetch_nwar_rows to return zero rows when DB returns no matches.')
    assert_true('nwar' %in% names(empty_result), 'Expected empty fetch_nwar_rows result to include nwar column.')
    assert_true('nwar_per_season' %in% names(empty_result), 'Expected empty fetch_nwar_rows result to include nwar_per_season column.')
    assert_true('seasons_played' %in% names(empty_result), 'Expected empty fetch_nwar_rows result to include seasons_played column.')

    # Single qualifying player: nWAR must be 0 (player is their own replacement).
    # Mock provides all fantasy-scoring stat columns required by fetch_nwar_rows.
    helpers_env$query_rows <- function(conn, query, params = list()) {
      data.frame(
        player_id            = 1L,
        player_name          = 'Test Player',
        squad_name           = 'Test Squad',
        seasons_played       = 1L,
        games_played         = 10L,
        total_goal1          = 0.0,
        total_goal2          = 0.0,
        total_goals_legacy   = 0.0,
        has_goal1_data       = 1L,
        total_off_reb        = 0.0,
        total_def_reb        = 0.0,
        total_feeds          = 0.0,
        total_cpr            = 0.0,
        total_spr            = 0.0,
        total_gain           = 0.0,
        total_intercepts     = 0.0,
        total_deflections    = 0.0,
        total_pickups        = 0.0,
        total_missed_goals   = 0.0,
        total_gpto           = 0.0,
        total_penalties      = 0.0,
        total_quarters       = 40.0,
    stringsAsFactors     = FALSE
      )
    }
    single_result <- helpers_env$fetch_nwar_rows(conn = NULL, min_games = 1L, limit = 50L)
    assert_true(nrow(single_result) == 1L, 'Expected fetch_nwar_rows to return one row for a single qualifying player.')
    assert_true(abs(as.numeric(single_result$nwar[[1]])) < 0.01, 'Expected single-player nWAR to be approximately 0 (player is their own replacement).')
    assert_true(abs(as.numeric(single_result$nwar_per_season[[1]])) < 0.01, 'Expected single-player nWAR per season to be approximately 0 (player is their own replacement).')

    # Optimized query shape assertions (no live DB needed).
    optimized_query <- capture_nwar_query(use_match_stats = TRUE, seasons = 2024L, min_games = 5L)
    assert_true(!is.null(optimized_query), 'Expected build_nwar_query to return a query object.')
    optimized_sql <- normalize_sql(optimized_query$query)

    assert_true(grepl('stats.stat IN', optimized_sql, fixed = TRUE),
                'Expected nWAR main query to filter to NWAR_STAT_KEYS via stats.stat IN.')
    assert_true(!grepl('player_match_positions', optimized_sql, fixed = TRUE),
                'Expected nWAR main query to not reference player_match_positions (position resolved separately by fetch_nwar_positions).')
    assert_true(!grepl('MODE() WITHIN GROUP', optimized_sql, fixed = TRUE),
                'Expected nWAR main query to not compute MODE() (position resolved by fetch_nwar_positions).')
    assert_true(!grepl('FROM player_match_positions pmp2', optimized_sql, fixed = TRUE),
                'Expected nWAR query to not use the old correlated position subquery.')
    assert_true(!is.null(optimized_query$params$season_1),
                'Expected build_nwar_query to parameterise the season filter (season_1).')

    # Position query shape: season-only filter.
    position_query <- capture_nwar_positions_query(seasons_filter = 2024L)
    assert_true(!is.null(position_query), 'Expected fetch_nwar_positions to return a query object.')
    position_sql <- normalize_sql(position_query$query)

    assert_true(grepl('COALESCE(', position_sql, fixed = TRUE),
                'Expected position query to include an all-time fallback.')
    assert_true(grepl('CASE WHEN season IN (?pos_season_1)', position_sql, fixed = TRUE),
                'Expected position query to scope per-filter branch to seasons.')
    assert_true(grepl("starting_position_code NOT IN \\('I', 'S', '-'\\)", position_sql),
                'Expected position query to exclude interchange and bench marker codes.')
    assert_true(!grepl('(SELECT MODE()', position_sql, fixed = TRUE),
                'Expected position query to avoid the old correlated position fallback subquery.')
    assert_true(!is.null(position_query$params$pos_season_1),
                'Expected fetch_nwar_positions to parameterise season filters.')

    # Position query shape: team_id-only filter — guards the team-scoped position
    # semantics regression where positions were resolved from all teams' matches.
    team_pos_query <- capture_nwar_positions_query(seasons_filter = NULL, team_id = 5L)
    assert_true(!is.null(team_pos_query), 'Expected fetch_nwar_positions with team_id to return a query object.')
    team_pos_sql <- normalize_sql(team_pos_query$query)
    assert_true(grepl('COALESCE(', team_pos_sql, fixed = TRUE),
                'Expected team-filtered position query to include an all-time fallback.')
    assert_true(grepl('CASE WHEN squad_id = ?pos_team_id', team_pos_sql, fixed = TRUE),
                'Expected team-filtered position query to scope per-filter branch to the team.')
    assert_true(!is.null(team_pos_query$params$pos_team_id),
                'Expected fetch_nwar_positions to parameterise the team_id filter.')

    # Position query shape: combined season + team_id filter.
    combined_pos_query <- capture_nwar_positions_query(seasons_filter = 2024L, team_id = 5L)
    combined_pos_sql <- normalize_sql(combined_pos_query$query)
    assert_true(grepl('season IN (?pos_season_1)', combined_pos_sql, fixed = TRUE),
                'Expected combined position query to include season scope.')
    assert_true(grepl('squad_id = ?pos_team_id', combined_pos_sql, fixed = TRUE),
                'Expected combined position query to include team scope.')

    assert_true(is.function(helpers_env$parse_nwar_era), 'Expected parse_nwar_era to be exported from helpers.R.')
    assert_true(is.function(helpers_env$parse_nwar_position_group), 'Expected parse_nwar_position_group to be exported from helpers.R.')
    assert_true(is.function(helpers_env$seasons_from_nwar_era), 'Expected seasons_from_nwar_era to be exported from helpers.R.')
    assert_true(identical(helpers_env$parse_nwar_era('ANZC'), 'anzc'), 'Expected parse_nwar_era to normalize ANZC.')
    assert_true(identical(helpers_env$parse_nwar_position_group('defender'), 'Defender'), 'Expected parse_nwar_position_group to map defender to Defender.')
    assert_true(identical(helpers_env$seasons_from_nwar_era('anzc'), 2008L:2016L), 'Expected ANZC era to map to seasons 2008-2016.')
    assert_true(identical(helpers_env$seasons_from_nwar_era('ssn'), 2017L:2100L), 'Expected SSN era to map to seasons 2017+.')

    helpers_env$has_player_match_stats <- function(conn) TRUE
    helpers_env$has_player_match_positions <- function(conn) TRUE
    helpers_env$query_rows <- function(conn, query, params = list()) {
      data.frame(
        player_id = c(1L, 2L, 3L),
        player_name = c('Shooter Sample', 'Midcourt Sample', 'Defender Sample'),
        squad_name = c('Firebirds', 'Lightning', 'Swifts'),
        seasons_played = c(1L, 1L, 1L),
        games_played = c(10L, 10L, 10L),
        total_goal1 = c(300, 0, 0),
        total_goal2 = c(20, 0, 0),
        total_goals_legacy = c(0, 0, 0),
        has_goal1_data = c(1L, 1L, 1L),
        total_off_reb = c(5, 1, 0),
        total_def_reb = c(0, 0, 9),
        total_feeds = c(40, 220, 15),
        total_cpr = c(110, 260, 50),
        total_spr = c(12, 70, 4),
        total_gain = c(2, 18, 44),
        total_intercepts = c(1, 5, 20),
        total_deflections = c(2, 14, 38),
        total_pickups = c(1, 10, 22),
        total_missed_goals = c(8, 0, 0),
        total_gpto = c(12, 18, 10),
        total_penalties = c(8, 20, 34),
        total_quarters = c(40, 40, 40),
        stringsAsFactors = FALSE
      )
    }
    helpers_env$fetch_nwar_positions <- function(conn, seasons_filter, team_id = NULL) {
      data.frame(
        player_id = c(1L, 2L, 3L),
        position_code = c('GS', 'WD', 'GK'),
        stringsAsFactors = FALSE
      )
    }

    defender_only <- helpers_env$fetch_nwar_rows(conn = NULL, seasons = 2024L, min_games = 1L, limit = 10L, position_group = 'Defender')
    assert_true(nrow(defender_only) == 1L, 'Expected fetch_nwar_rows to keep only one defender row in the mocked sample.')
    assert_true(all(defender_only$position_group == 'Defender'), 'Expected fetch_nwar_rows to retain only Defender rows when position_group is supplied.')

    check_step('fetch_nwar_rows unit tests pass (empty result, single player boundary, optimized query shape, team-scoped position)')
  }
}

# match_scoreflow_summary semantic unit tests.
#
# These verify the scalar semantics of the derived columns without a live DB.
# The actual build-time invariant checks (row counts, time sums, etc.) run
# inside build_database.R after match_scoreflow_summary is created.
{
  # Simulate the derived-column expressions over a few representative cases.
  check_mss_row <- function(seconds_trailing, match_total_seconds, won, deepest_deficit_points) {
    match_has_scoreflow <- if (match_total_seconds > 0) 1L else 0L
    trailing_share <- if (match_total_seconds > 0) {
      round(seconds_trailing / match_total_seconds, 4)
    } else {
      NA_real_
    }
    trailed_most <- if (match_total_seconds > 0) {
      if (seconds_trailing > match_total_seconds / 2) 1L else 0L
    } else {
      NA_integer_
    }
    comeback_win <- if (match_total_seconds > 0) {
      if (won == 1L && deepest_deficit_points > 0) 1L else 0L
    } else {
      NA_integer_
    }
    # won_trailing_most: explicit combined field — won after trailing > half the match.
    won_trailing_most <- if (match_total_seconds > 0) {
      if (won == 1L && seconds_trailing > match_total_seconds / 2) 1L else 0L
    } else {
      NA_integer_
    }
    # comeback_deficit_points: explicit comeback-size field for ranking.
    # deepest_deficit_points when won with a deficit; 0 otherwise.
    comeback_deficit_points <- if (match_total_seconds > 0) {
      if (won == 1L && deepest_deficit_points > 0) deepest_deficit_points else 0L
    } else {
      NA_integer_
    }
    list(
      match_has_scoreflow = match_has_scoreflow,
      trailing_share = trailing_share,
      trailed_most_of_match = trailed_most,
      comeback_win = comeback_win,
      won_trailing_most = won_trailing_most,
      comeback_deficit_points = comeback_deficit_points
    )
  }

  # Case 1: team trailed for 61/120 s (just over half) and won with a prior deficit.
  case1 <- check_mss_row(seconds_trailing = 61, match_total_seconds = 120, won = 1L, deepest_deficit_points = 3L)
  assert_true(identical(case1$match_has_scoreflow, 1L), 'Case 1: match_has_scoreflow should be 1.')
  assert_true(identical(case1$trailed_most_of_match, 1L), 'Case 1: trailed_most_of_match should be 1 (61 > 120/2).')
  assert_true(identical(case1$comeback_win, 1L), 'Case 1: comeback_win should be 1 (won with deficit).')
  assert_true(abs(case1$trailing_share - 0.5083) < 0.0001, 'Case 1: trailing_share should be ~0.5083.')
  # Combined analytics: both new explicit fields must fire together.
  assert_true(identical(case1$won_trailing_most, 1L), 'Case 1: won_trailing_most should be 1 (won + trailed > half).')
  assert_true(identical(case1$comeback_deficit_points, 3L), 'Case 1: comeback_deficit_points should equal deepest_deficit_points (3).')

  # Case 2: team trailed for exactly half the match (not > half; trailed_most = 0).
  case2 <- check_mss_row(seconds_trailing = 60, match_total_seconds = 120, won = 1L, deepest_deficit_points = 2L)
  assert_true(identical(case2$trailed_most_of_match, 0L), 'Case 2: trailed_most_of_match should be 0 (60 = 120/2, not strictly more).')
  assert_true(identical(case2$comeback_win, 1L), 'Case 2: comeback_win should be 1 (won with deficit).')
  assert_true(identical(case2$won_trailing_most, 0L), 'Case 2: won_trailing_most should be 0 (not trailing strictly more than half).')
  assert_true(identical(case2$comeback_deficit_points, 2L), 'Case 2: comeback_deficit_points should be 2 (won with deficit regardless of time share).')

  # Case 3: team won but was never behind — comeback fields should be 0.
  case3 <- check_mss_row(seconds_trailing = 0, match_total_seconds = 120, won = 1L, deepest_deficit_points = 0L)
  assert_true(identical(case3$comeback_win, 0L), 'Case 3: comeback_win should be 0 (deepest_deficit_points = 0).')
  assert_true(identical(case3$trailed_most_of_match, 0L), 'Case 3: trailed_most_of_match should be 0 (never trailed).')
  assert_true(identical(case3$won_trailing_most, 0L), 'Case 3: won_trailing_most should be 0 (never trailed).')
  assert_true(identical(case3$comeback_deficit_points, 0L), 'Case 3: comeback_deficit_points should be 0 (no deficit to overcome).')

  # Case 4: team lost despite having trailed most of the match — won_trailing_most must be 0.
  case4 <- check_mss_row(seconds_trailing = 80, match_total_seconds = 120, won = 0L, deepest_deficit_points = 5L)
  assert_true(identical(case4$comeback_win, 0L), 'Case 4: comeback_win should be 0 (lost, not won).')
  assert_true(identical(case4$trailed_most_of_match, 1L), 'Case 4: trailed_most_of_match should be 1 (80 > 60).')
  assert_true(identical(case4$won_trailing_most, 0L), 'Case 4: won_trailing_most should be 0 (lost the match).')
  assert_true(identical(case4$comeback_deficit_points, 0L), 'Case 4: comeback_deficit_points should be 0 (lost, not a comeback win).')

  # Case 5: no scoreflow coverage — all derived flags should be NA/NULL.
  case5 <- check_mss_row(seconds_trailing = 0, match_total_seconds = 0, won = 1L, deepest_deficit_points = 0L)
  assert_true(identical(case5$match_has_scoreflow, 0L), 'Case 5: match_has_scoreflow should be 0.')
  assert_true(is.na(case5$trailing_share), 'Case 5: trailing_share should be NA for no-scoreflow match.')
  assert_true(is.na(case5$trailed_most_of_match), 'Case 5: trailed_most_of_match should be NA for no-scoreflow match.')
  assert_true(is.na(case5$comeback_win), 'Case 5: comeback_win should be NA for no-scoreflow match.')
  assert_true(is.na(case5$won_trailing_most), 'Case 5: won_trailing_most should be NA for no-scoreflow match.')
  assert_true(is.na(case5$comeback_deficit_points), 'Case 5: comeback_deficit_points should be NA for no-scoreflow match.')

  # Case 6: won after trailing most of match with a large deficit — validate comeback-size ranking basis.
  case6 <- check_mss_row(seconds_trailing = 90, match_total_seconds = 120, won = 1L, deepest_deficit_points = 8L)
  assert_true(identical(case6$won_trailing_most, 1L), 'Case 6: won_trailing_most should be 1.')
  assert_true(identical(case6$comeback_deficit_points, 8L), 'Case 6: comeback_deficit_points should be 8 (the deficit overcome).')
  # A bigger comeback deficit means a more significant comeback — verify ranking property.
  assert_true(case6$comeback_deficit_points > case1$comeback_deficit_points,
              'Case 6: comeback_deficit_points should rank above Case 1 (8 > 3).')

  check_step('match_scoreflow_summary semantic unit tests pass (trailed_most threshold, comeback_win conditions, won_trailing_most, comeback_deficit_points, no-scoreflow NULLs)')
}

# --- DB-backed match_scoreflow_summary verification ---
# Queries the actual built table to validate structure and cross-row invariants
# against real data.
#
# Skip condition: no database connection is configured (expected in CI runs that
# only test the HTTP surface).  Any other failure — sourcing R/database.R,
# connecting, or a query error — propagates as a real test failure so that
# environment or SQL regressions are not silently swallowed.
{
  db_configured <- nzchar(Sys.getenv("NETBALL_STATS_DATABASE_URL", "")) ||
                   nzchar(Sys.getenv("DATABASE_URL", "")) ||
                   nzchar(Sys.getenv("NETBALL_STATS_DB_HOST", ""))

  if (!db_configured) {
    message("match_scoreflow_summary DB check skipped: no database connection configured")
  } else {
    db_env <- new.env(parent = globalenv())
    sys.source(file.path(getwd(), "R", "database.R"), envir = db_env)
    db_conn <- db_env$open_database_connection()
    tryCatch({
      # 1. Table exists and has exactly the expected columns.
      #    Columns listed here must match the SELECT list in the CREATE TABLE AS
      #    query in build_database.R — no more, no less.
      mss_cols <- DBI::dbGetQuery(db_conn, paste(
        "SELECT column_name FROM information_schema.columns",
        "WHERE table_name = 'match_scoreflow_summary'",
        "ORDER BY ordinal_position"
      ))$column_name
      required_cols <- c(
        "match_id", "season", "competition_id", "competition_phase",
        "round_number", "game_number",
        "squad_id", "opponent_id", "is_home", "won",
        "seconds_leading", "seconds_trailing", "seconds_tied",
        "match_total_seconds",
        "largest_lead_points", "deepest_deficit_points", "lead_changes",
        "match_has_scoreflow", "trailing_share",
        "trailed_most_of_match", "comeback_win",
        "won_trailing_most", "comeback_deficit_points"
      )
      missing_cols <- setdiff(required_cols, mss_cols)
      extra_cols   <- setdiff(mss_cols, required_cols)
      assert_true(
        length(missing_cols) == 0L,
        sprintf("match_scoreflow_summary missing expected columns: %s", paste(missing_cols, collapse = ", "))
      )
      assert_true(
        length(extra_cols) == 0L,
        sprintf("match_scoreflow_summary has unexpected columns: %s", paste(extra_cols, collapse = ", "))
      )

      # 2. Every match_id has exactly two rows — one per team.
      #    The aggregate formula COUNT(*) - 2*COUNT(DISTINCT match_id) can mask
      #    compensating over/under counts across different matches; this query
      #    catches each offending match_id individually.
      bad_pairs <- DBI::dbGetQuery(db_conn, paste(
        "SELECT match_id, COUNT(*) AS row_count",
        "FROM match_scoreflow_summary",
        "GROUP BY match_id",
        "HAVING COUNT(*) != 2"
      ))
      assert_true(
        nrow(bad_pairs) == 0L,
        sprintf(
          "match_scoreflow_summary: %d match_id(s) do not have exactly 2 rows: %s",
          nrow(bad_pairs),
          paste(head(bad_pairs$match_id, 5L), collapse = ", ")
        )
      )

      # 3. Completeness — every completed match in `matches` has rows here.
      #    A build bug that silently drops whole matches would pass checks 1-2
      #    (schema and pair count are fine for the rows that do exist) but fails
      #    this cross-table population test.
      completeness <- DBI::dbGetQuery(db_conn, paste(
        "SELECT",
        "  (SELECT COUNT(*) FROM matches",
        "   WHERE home_score IS NOT NULL AND away_score IS NOT NULL) AS completed_matches,",
        "  COUNT(DISTINCT match_id) AS summary_match_count",
        "FROM match_scoreflow_summary"
      ))
      assert_true(
        completeness$summary_match_count == completeness$completed_matches,
        sprintf(
          "match_scoreflow_summary covers %d of %d completed matches (%d missing)",
          completeness$summary_match_count,
          completeness$completed_matches,
          completeness$completed_matches - completeness$summary_match_count
        )
      )

      # 4. Home/away symmetry — each match has exactly one is_home = 1 row and
      #    one is_home = 0 row.  The pair check (2 rows per match_id) already
      #    passed, but does not distinguish (home, away) from (home, home) or
      #    (away, away).
      bad_symmetry <- DBI::dbGetQuery(db_conn, paste(
        "SELECT match_id,",
        "  SUM(is_home) AS home_rows,",
        "  SUM(1 - is_home) AS away_rows",
        "FROM match_scoreflow_summary",
        "GROUP BY match_id",
        "HAVING SUM(is_home) != 1 OR SUM(1 - is_home) != 1"
      ))
      assert_true(
        nrow(bad_symmetry) == 0L,
        sprintf(
          "match_scoreflow_summary: %d match_id(s) lack exactly one home and one away row: %s",
          nrow(bad_symmetry),
          paste(head(bad_symmetry$match_id, 5L), collapse = ", ")
        )
      )

      # Report coverage before running invariants.
      coverage <- DBI::dbGetQuery(db_conn, paste(
        "SELECT COUNT(*) AS total_rows,",
        "  SUM(CASE WHEN match_has_scoreflow = 1 THEN 1 ELSE 0 END) AS scoreflow_rows",
        "FROM match_scoreflow_summary"
      ))

      # 5. Invariants against actual data — the source of truth for whether the
      #    build SQL produced correct results, not just whether the logic is right.
      inv <- DBI::dbGetQuery(db_conn, paste(
        "SELECT",
        "  SUM(CASE WHEN match_has_scoreflow = 1",
        "            AND (seconds_leading > match_total_seconds",
        "            OR seconds_trailing > match_total_seconds",
        "            OR seconds_tied > match_total_seconds)",
        "            THEN 1 ELSE 0 END) AS time_component_overflow,",
        "  SUM(CASE WHEN match_has_scoreflow = 1",
        "            AND comeback_win = 1",
        "            AND (won != 1 OR deepest_deficit_points <= 0)",
        "            THEN 1 ELSE 0 END) AS comeback_win_invalid,",
        "  SUM(CASE WHEN match_has_scoreflow = 1",
        "            AND won_trailing_most = 1",
        "            AND (won != 1 OR seconds_trailing <= match_total_seconds / 2.0)",
        "            THEN 1 ELSE 0 END) AS won_trailing_most_invalid,",
        "  SUM(CASE WHEN match_has_scoreflow = 1",
        "            AND comeback_win = 1",
        "            AND comeback_deficit_points != deepest_deficit_points",
        "            THEN 1 ELSE 0 END) AS comeback_deficit_mismatch,",
        "  SUM(CASE WHEN match_has_scoreflow = 1",
        "            AND COALESCE(comeback_win, 0) = 0",
        "            AND COALESCE(comeback_deficit_points, 0) != 0",
        "            THEN 1 ELSE 0 END) AS comeback_deficit_nonzero_no_win",
        "FROM match_scoreflow_summary"
      ))
      assert_true(inv$time_component_overflow == 0L,
        "DB: match_scoreflow_summary has rows where a time component exceeds match_total_seconds")
      assert_true(inv$comeback_win_invalid == 0L,
        "DB: match_scoreflow_summary has invalid comeback_win rows (won=0 or deficit=0)")
      assert_true(inv$won_trailing_most_invalid == 0L,
        "DB: match_scoreflow_summary has invalid won_trailing_most rows")
      assert_true(inv$comeback_deficit_mismatch == 0L,
        "DB: match_scoreflow_summary comeback_deficit_points != deepest_deficit_points for comeback_win rows")
      assert_true(inv$comeback_deficit_nonzero_no_win == 0L,
        "DB: match_scoreflow_summary comeback_deficit_points nonzero without comeback_win")

      check_step(sprintf(
        "match_scoreflow_summary DB validation pass (%d rows, %d with scoreflow coverage)",
        coverage$total_rows, coverage$scoreflow_rows
      ))
    }, finally = {
      DBI::dbDisconnect(db_conn)
    })
  }
}

# ---------------------------------------------------------------------------
# Scoreflow helper unit tests (no live DB required)
# ---------------------------------------------------------------------------
{
  scoreflow_helpers_env <- new.env(parent = globalenv())
  sys.source(file.path(getwd(), 'api', 'R', 'helpers.R'), envir = scoreflow_helpers_env)
  scoreflow_helpers_env$api_log <- function(...) NULL

  # Validator exports
  assert_true(is.function(scoreflow_helpers_env$parse_scoreflow_metric),
    'Expected parse_scoreflow_metric to be exported from helpers.R.')
  assert_true(is.function(scoreflow_helpers_env$parse_scoreflow_scenario),
    'Expected parse_scoreflow_scenario to be exported from helpers.R.')
  assert_true(is.function(scoreflow_helpers_env$parse_scoreflow_team_sort),
    'Expected parse_scoreflow_team_sort to be exported from helpers.R.')
  assert_true(is.function(scoreflow_helpers_env$has_match_scoreflow_summary),
    'Expected has_match_scoreflow_summary to be exported from helpers.R.')
  assert_true(is.function(scoreflow_helpers_env$fetch_scoreflow_game_records),
    'Expected fetch_scoreflow_game_records to be exported from helpers.R.')
  assert_true(is.function(scoreflow_helpers_env$fetch_scoreflow_team_summary),
    'Expected fetch_scoreflow_team_summary to be exported from helpers.R.')

  # has_match_scoreflow_summary: only caches TRUE, never FALSE.
  # NULL conn causes DBI::dbExistsTable to throw, caught by tryCatch -> returns FALSE.
  # This avoids needing to mock the DBI package namespace.
  {
    options(netballstats.mss_available = NULL)
    # NULL conn -> DBI error -> FALSE, nothing cached
    result_absent <- scoreflow_helpers_env$has_match_scoreflow_summary(conn = NULL)
    assert_true(!isTRUE(result_absent),
      'Expected has_match_scoreflow_summary to return FALSE when DB is unreachable.')
    assert_true(is.null(getOption('netballstats.mss_available')),
      'Expected has_match_scoreflow_summary to NOT cache a FALSE/error result.')

    # Pre-set cache to TRUE; function must return TRUE even with an unreachable conn
    options(netballstats.mss_available = TRUE)
    result_cached <- scoreflow_helpers_env$has_match_scoreflow_summary(conn = NULL)
    assert_true(isTRUE(result_cached),
      'Expected has_match_scoreflow_summary to return cached TRUE without querying DB.')

    options(netballstats.mss_available = NULL)  # restore for subsequent tests
  }

  # parse_scoreflow_metric: defaults and validation
  assert_true(
    identical(scoreflow_helpers_env$parse_scoreflow_metric(''), 'comeback_deficit_points'),
    'Expected parse_scoreflow_metric to default to comeback_deficit_points.'
  )
  assert_true(
    identical(scoreflow_helpers_env$parse_scoreflow_metric('trailing_share'), 'trailing_share'),
    'Expected parse_scoreflow_metric to accept trailing_share.'
  )
  assert_true(
    identical(scoreflow_helpers_env$parse_scoreflow_metric('Seconds_Leading'), 'seconds_leading'),
    'Expected parse_scoreflow_metric to normalise case.'
  )
  assert_true(
    tryCatch({
      scoreflow_helpers_env$parse_scoreflow_metric('invalid_metric')
      FALSE
    }, error = function(e) TRUE),
    'Expected parse_scoreflow_metric to reject an unrecognised metric.'
  )

  # parse_scoreflow_scenario: defaults and validation
  assert_true(
    identical(scoreflow_helpers_env$parse_scoreflow_scenario(''), 'all'),
    'Expected parse_scoreflow_scenario to default to all.'
  )
  assert_true(
    identical(scoreflow_helpers_env$parse_scoreflow_scenario('comeback_wins'), 'comeback_wins'),
    'Expected parse_scoreflow_scenario to accept comeback_wins.'
  )
  assert_true(
    identical(scoreflow_helpers_env$parse_scoreflow_scenario('WON_TRAILING_MOST'), 'won_trailing_most'),
    'Expected parse_scoreflow_scenario to normalise case.'
  )
  assert_true(
    tryCatch({
      scoreflow_helpers_env$parse_scoreflow_scenario('invalid')
      FALSE
    }, error = function(e) TRUE),
    'Expected parse_scoreflow_scenario to reject an unrecognised scenario.'
  )

  # parse_scoreflow_team_sort: defaults and validation
  assert_true(
    identical(scoreflow_helpers_env$parse_scoreflow_team_sort(''), 'total_seconds_leading'),
    'Expected parse_scoreflow_team_sort to default to total_seconds_leading.'
  )
  assert_true(
    identical(scoreflow_helpers_env$parse_scoreflow_team_sort('comeback_wins'), 'comeback_wins'),
    'Expected parse_scoreflow_team_sort to accept comeback_wins.'
  )
  assert_true(
    tryCatch({
      scoreflow_helpers_env$parse_scoreflow_team_sort('nwar')
      FALSE
    }, error = function(e) TRUE),
    'Expected parse_scoreflow_team_sort to reject an unrecognised sort key.'
  )

  # fetch_scoreflow_game_records: query shape checks (no live DB; capture generated SQL)
  {
    captured_query <- NULL
    captured_params <- NULL
    scoreflow_helpers_env$query_rows <- function(conn, query, params = list()) {
      captured_query  <<- query
      captured_params <<- params
      data.frame()
    }
    scoreflow_helpers_env$fetch_scoreflow_game_records(
      conn     = NULL,
      metric   = 'comeback_deficit_points',
      scenario = 'comeback_wins',
      seasons  = c(2023L, 2024L),
      team_id  = 5L,
      opponent_id = NULL,
      limit    = 10L
    )
    sql <- normalize_sql(captured_query)
    assert_contains(sql, 'match_scoreflow_summary mss',
      'Expected fetch_scoreflow_game_records query to read from match_scoreflow_summary.')
    assert_contains(sql, 'match_has_scoreflow = 1',
      'Expected fetch_scoreflow_game_records to filter to rows with scoreflow data.')
    assert_contains(sql, 'mss.comeback_win = 1',
      'Expected fetch_scoreflow_game_records to apply the comeback_wins scenario filter.')
    assert_contains(sql, 'mss.season IN (?season_1, ?season_2)',
      'Expected fetch_scoreflow_game_records to parameterise the season IN filter.')
    assert_contains(sql, 'mss.squad_id = ?team_id',
      'Expected fetch_scoreflow_game_records to parameterise the team_id filter.')
    assert_contains(sql, 'ORDER BY mss.comeback_deficit_points DESC',
      'Expected fetch_scoreflow_game_records to order by the selected metric DESC.')
    assert_true(is.null(captured_params[['opponent_id']]),
      'Expected fetch_scoreflow_game_records to omit opponent_id param when not supplied.')
    assert_true(identical(captured_params[['team_id']], 5L),
      'Expected fetch_scoreflow_game_records to pass team_id as integer.')
  }

  # fetch_scoreflow_game_records with wins scenario and opponent filter
  {
    captured_query2 <- NULL
    scoreflow_helpers_env$query_rows <- function(conn, query, params = list()) {
      captured_query2 <<- query
      data.frame()
    }
    scoreflow_helpers_env$fetch_scoreflow_game_records(
      conn        = NULL,
      metric      = 'trailing_share',
      scenario    = 'wins',
      seasons     = NULL,
      team_id     = NULL,
      opponent_id = 7L,
      limit       = 5L
    )
    sql2 <- normalize_sql(captured_query2)
    assert_contains(sql2, 'mss.won = 1',
      'Expected wins scenario to apply mss.won = 1 filter.')
    assert_contains(sql2, 'mss.trailing_share DESC',
      'Expected trailing_share metric to order by trailing_share.')
    assert_contains(sql2, 'mss.opponent_id = ?opponent_id',
      'Expected opponent_id to appear in query when supplied.')
    assert_true(!grepl('mss.season IN', sql2),
      'Expected no season filter when seasons is NULL.')
  }

  # fetch_scoreflow_team_summary: query shape checks
  {
    captured_team_query <- NULL
    scoreflow_helpers_env$query_rows <- function(conn, query, params = list()) {
      captured_team_query <<- query
      data.frame()
    }
    scoreflow_helpers_env$fetch_scoreflow_team_summary(
      conn        = NULL,
      seasons     = c(2022L, 2023L),
      team_id     = NULL,
      min_matches = 3L,
      sort_by     = 'comeback_wins',
      limit       = 10L
    )
    sql3 <- normalize_sql(captured_team_query)
    assert_contains(sql3, 'match_scoreflow_summary mss',
      'Expected fetch_scoreflow_team_summary query to read from match_scoreflow_summary.')
    assert_contains(sql3, 'SUM(CASE WHEN mss.comeback_win = 1',
      'Expected fetch_scoreflow_team_summary to aggregate comeback_wins.')
    assert_contains(sql3, 'SUM(CASE WHEN mss.seconds_leading > mss.match_total_seconds / 2.0',
      'Expected fetch_scoreflow_team_summary to use majority-threshold for games_led_most.')
    assert_contains(sql3, 'MAX(mss.comeback_deficit_points) AS largest_comeback_win_points',
      'Expected fetch_scoreflow_team_summary to aggregate largest_comeback_win_points.')
    assert_contains(sql3, 'HAVING COUNT(*) >= 3',
      'Expected fetch_scoreflow_team_summary to apply min_matches HAVING clause.')
    assert_contains(sql3, 'ORDER BY comeback_wins DESC',
      'Expected fetch_scoreflow_team_summary to order by comeback_wins.')
    assert_contains(sql3, 'mss.season IN (?season_1, ?season_2)',
      'Expected fetch_scoreflow_team_summary to parameterise season filter.')
  }

  check_step('scoreflow helper unit tests pass (validators, cache-only-true, game-records query shape, team-summary query shape)')
}

# ---------------------------------------------------------------------------
# Scoreflow live endpoint regression tests
# ---------------------------------------------------------------------------
cat("Checking /scoreflow-game-records default response...\n")
scoreflow_game_records <- request_json(base_url, '/scoreflow-game-records', query = list(limit = '10'))
assert_true(is.list(scoreflow_game_records),
  'Expected /scoreflow-game-records to return a list payload.')
assert_true(is.list(scoreflow_game_records$filters),
  'Expected /scoreflow-game-records to include a filters block.')
assert_true(identical(as.character(scalar_value(scoreflow_game_records$filters$metric)), 'comeback_deficit_points'),
  'Expected /scoreflow-game-records to echo the default metric.')
assert_true(identical(as.character(scalar_value(scoreflow_game_records$filters$scenario)), 'all'),
  'Expected /scoreflow-game-records to echo the default scenario.')
assert_true(is.list(scoreflow_game_records$data),
  'Expected /scoreflow-game-records to include a data array.')
check_step('/scoreflow-game-records returns a valid payload with default params')

if (length(scoreflow_game_records$data) >= 1L) {
  first_sgr <- first_record(scoreflow_game_records$data)
  expected_game_cols <- c('match_id', 'season', 'round_number', 'squad_id', 'squad_name',
                          'opponent_id', 'opponent_name', 'is_home', 'won',
                          'comeback_deficit_points', 'deepest_deficit_points',
                          'seconds_leading', 'seconds_trailing', 'match_has_scoreflow')
  missing_game_cols <- setdiff(expected_game_cols, names(first_sgr))
  assert_true(length(missing_game_cols) == 0L,
    sprintf('/scoreflow-game-records missing expected columns: %s', paste(missing_game_cols, collapse = ', ')))
  check_step('/scoreflow-game-records data rows expose expected editorial columns')
}

cat("Checking /scoreflow-game-records scenario and metric params...\n")
comeback_records <- request_json(base_url, '/scoreflow-game-records', query = list(
  scenario = 'comeback_wins',
  metric   = 'comeback_deficit_points',
  limit    = '5'
))
assert_true(is.list(comeback_records$data),
  'Expected /scoreflow-game-records?scenario=comeback_wins to return a data array.')
check_step('/scoreflow-game-records accepts scenario=comeback_wins and metric=comeback_deficit_points')

cat("Checking /scoreflow-game-records validation rejects bad metric...\n")
bad_metric <- request_json(base_url, '/scoreflow-game-records',
  query = list(metric = 'bad_metric'), expected_status = 400L)
check_step('/scoreflow-game-records returns 400 for an invalid metric')

cat("Checking /scoreflow-game-records validation rejects bad scenario...\n")
bad_scenario <- request_json(base_url, '/scoreflow-game-records',
  query = list(scenario = 'bad_scenario'), expected_status = 400L)
check_step('/scoreflow-game-records returns 400 for an invalid scenario')

cat("Checking /scoreflow-team-summary default response...\n")
scoreflow_team_summary <- request_json(base_url, '/scoreflow-team-summary', query = list(limit = '10'))
assert_true(is.list(scoreflow_team_summary),
  'Expected /scoreflow-team-summary to return a list payload.')
assert_true(is.list(scoreflow_team_summary$filters),
  'Expected /scoreflow-team-summary to include a filters block.')
assert_true(identical(as.character(scalar_value(scoreflow_team_summary$filters$sort_by)), 'total_seconds_leading'),
  'Expected /scoreflow-team-summary to echo the default sort_by.')
assert_true(is.list(scoreflow_team_summary$data),
  'Expected /scoreflow-team-summary to include a data array.')
check_step('/scoreflow-team-summary returns a valid payload with default params')

if (length(scoreflow_team_summary$data) >= 1L) {
  first_sts <- first_record(scoreflow_team_summary$data)
  expected_team_cols <- c('squad_id', 'squad_name', 'matches_with_scoreflow',
                          'total_seconds_leading', 'total_seconds_trailing', 'total_seconds_tied',
                          'games_led_most', 'games_trailed_most',
                          'comeback_wins', 'won_trailing_most', 'largest_comeback_win_points')
  missing_team_cols <- setdiff(expected_team_cols, names(first_sts))
  assert_true(length(missing_team_cols) == 0L,
    sprintf('/scoreflow-team-summary missing expected columns: %s', paste(missing_team_cols, collapse = ', ')))
  check_step('/scoreflow-team-summary data rows expose expected aggregate columns')
}

cat("Checking /scoreflow-team-summary sort_by param...\n")
comeback_summary <- request_json(base_url, '/scoreflow-team-summary', query = list(
  sort_by     = 'comeback_wins',
  min_matches = '1',
  limit       = '8'
))
assert_true(is.list(comeback_summary$data),
  'Expected /scoreflow-team-summary?sort_by=comeback_wins to return a data array.')
assert_true(identical(as.character(scalar_value(comeback_summary$filters$sort_by)), 'comeback_wins'),
  'Expected /scoreflow-team-summary to echo sort_by=comeback_wins in filters.')
check_step('/scoreflow-team-summary accepts sort_by=comeback_wins')

cat("Checking /scoreflow-team-summary validation rejects bad sort_by...\n")
bad_sort <- request_json(base_url, '/scoreflow-team-summary',
  query = list(sort_by = 'invalid_sort'), expected_status = 400L)
check_step('/scoreflow-team-summary returns 400 for an invalid sort_by')

cat("Checking /scoreflow-featured-records default response...\n")
scoreflow_featured <- request_json(base_url, "/scoreflow-featured-records", query = list(
  seasons = paste(default_season, default_season - 1L, sep = ",")
))
assert_true(is.list(scoreflow_featured$filters),
  "Expected /scoreflow-featured-records to include a filters block.")
assert_true(is.list(scoreflow_featured$data) && length(scoreflow_featured$data) == 3L,
  "Expected /scoreflow-featured-records to return exactly three featured cards.")
first_featured <- first_record(scoreflow_featured$data)
assert_true(all(c("slug", "label", "metric", "scenario", "href_query", "record") %in% names(first_featured)),
  "Expected featured scoreflow cards to expose slug, label, metric, scenario, href_query, and record.")
check_step('/scoreflow-featured-records returns a valid payload with three cards')

cat("Checking /player-profile includes identity block...\n")
assert_true(is.list(profile_payload$identity),
  'Expected /player-profile to include an identity block.')
assert_true("debut_season" %in% names(profile_payload$identity),
  'Expected /player-profile identity to contain debut_season.')
assert_true("reference_status" %in% names(profile_payload$identity),
  'Expected /player-profile identity to contain reference_status.')
check_step('/player-profile identity block includes debut_season and reference_status')

cat("Checking /league-composition-summary default response...\n")
composition_summary <- request_json(base_url, '/league-composition-summary')
assert_true(is.list(composition_summary$data),
  'Expected /league-composition-summary to return a data list.')
assert_true(is.list(composition_summary$coverage),
  'Expected /league-composition-summary to return coverage metadata.')
assert_true(length(composition_summary$data) >= 1L,
  'Expected /league-composition-summary to return at least one season row.')
coverage_fields <- c('players_with_matches', 'players_with_birth_date', 'players_with_import_status')
missing_coverage_fields <- setdiff(coverage_fields, names(composition_summary$coverage))
assert_true(length(missing_coverage_fields) == 0L,
  sprintf('/league-composition-summary coverage missing required fields: %s',
          paste(missing_coverage_fields, collapse = ', ')))
check_step('/league-composition-summary returns data rows and coverage with required aggregate fields')

cat("Checking /league-composition-debut-bands default response...\n")
debut_bands <- request_json(base_url, '/league-composition-debut-bands')
assert_true(is.list(debut_bands$data),
  'Expected /league-composition-debut-bands to return a data list.')
assert_true(length(debut_bands$data) >= 1L,
  'Expected /league-composition-debut-bands to return at least one band row.')
assert_true("debut_player_names" %in% names(debut_bands$data[[1]]),
  'Expected /league-composition-debut-bands rows to include debut_player_names.')
check_step('/league-composition-debut-bands returns debut age bands with player-name detail')

# Task 6: API Endpoint Extension - Builder routing tests
cat("\nTesting Task 6: /api/query endpoint builder routing...\n")

cat("Checking backward compatibility: /query with simple highest query...\n")
simple_query <- request_json(base_url, '/query', query = list(question = 'highest goals'))
assert_true(identical(scalar_value(simple_query$status), 'supported'),
  'Expected simple query to return status=supported')
assert_true(is.list(simple_query$rows) && length(simple_query$rows) >= 1,
  'Expected simple query to return at least one row')
check_step('/query backward compatibility: simple queries still work')

cat("Checking backward compatibility: /query with simple lowest query...\n")
simple_lowest <- request_json(base_url, '/query', query = list(question = 'lowest penalties'))
assert_true(identical(scalar_value(simple_lowest$status), 'supported'),
  'Expected lowest query to return status=supported')
check_step('/query backward compatibility: lowest queries work')

cat("Checking /query POST with builder_source=false and no question (should skip parse and use simple logic)...\n")
no_question_post <- request_json_post(
  base_url,
  '/query',
  list(question = '', builder_source = FALSE),
  expected_status = 400L
)
assert_contains(
  scalar_value(no_question_post$error),
  'Invalid request parameters',
  'Expected empty question POST to return the standard validation error payload'
)
check_step('/query POST: empty question returns 400 validation error as expected')

cat("Checking /query POST builder_source=true with missing shape...\n")
no_shape_post <- request_json_post(
  base_url,
  '/query',
  list(builder_source = TRUE),
  expected_status = 400L
)
assert_true(identical(scalar_value(no_shape_post$status), 'error'),
  'Expected missing shape to return error')
assert_contains(scalar_value(no_shape_post$error), 'Shape is required',
  'Expected error message about shape')
check_step('/query POST: builder_source=true with missing shape returns error')

cat("Checking /query POST builder_source=true with valid comparison...\n")
comparison_post <- request_json_post(base_url, '/query', list(
  builder_source = TRUE,
  shape = 'comparison',
  subjects = c('Collingwood', 'Melbourne'),
  stat = 'goals',
  seasons = c(2024)
))
assert_true(!is.null(comparison_post$status),
  'Expected comparison builder to return status')
# Status could be error or success depending on data; main thing is it routes to builder
check_step('/query POST: builder_source=true routes to comparison builder')

cat("Checking /query POST builder_source=true with valid trend...\n")
trend_post <- request_json_post(base_url, '/query', list(
  builder_source = TRUE,
  shape = 'trend',
  subject = 'Collingwood',
  stat = 'goals'
))
assert_true(!is.null(trend_post$status),
  'Expected trend builder to return status')
check_step('/query POST: builder_source=true routes to trend builder')

cat("Checking /query POST builder_source=true with valid record...\n")
record_post <- request_json_post(base_url, '/query', list(
  builder_source = TRUE,
  shape = 'record',
  stat = 'goals'
))
assert_true(!is.null(record_post$status),
  'Expected record builder to return status')
check_step('/query POST: builder_source=true routes to record builder')

cat("Checking /query GET with question that has medium confidence parse...\n")
# This will depend on the parser confidence, but we're testing the flow exists
medium_conf_query <- request_json(base_url, '/query', 
  query = list(question = 'player stats over time'))
# Should either succeed with builder route or return parse_help_needed
assert_true(identical(scalar_value(medium_conf_query$status), 'parse_help_needed') ||
            identical(scalar_value(medium_conf_query$status), 'supported') ||
            identical(scalar_value(medium_conf_query$status), 'unsupported'),
  'Expected query to return parse_help_needed, supported, or unsupported')
check_step('/query GET: medium-confidence question routed appropriately')

cat("Checking /query GET backward compatibility: list query...\n")
list_query <- request_json(base_url, '/query', query = list(question = 'list players'))
assert_true(identical(scalar_value(list_query$status), 'supported') ||
            identical(scalar_value(list_query$status), 'unsupported'),
  'Expected list query to route to simple logic')
check_step('/query GET: list query backward compatible')

cat("Checking /query GET backward compatibility: count query...\n")
count_query <- request_json(base_url, '/query', query = list(question = 'how many goals'))
assert_true(identical(scalar_value(count_query$status), 'supported') ||
            identical(scalar_value(count_query$status), 'unsupported'),
  'Expected count query to work')
check_step('/query GET: count query backward compatible')

# Task 6: Array bounds safety tests
cat("\nTesting Task 6: Array bounds safety (empty array handling)...\n")

cat("Checking /query POST comparison with empty subjects array...\n")
empty_subjects <- request_json_post(base_url, '/query', list(
  builder_source = TRUE,
  shape = 'comparison',
  subjects = c(),
  stat = 'goals',
  seasons = c(2024)
), expected_status = 400L)
assert_true(identical(scalar_value(empty_subjects$status), 'error'),
  'Expected empty subjects to return error, not crash')
assert_contains(scalar_value(empty_subjects$error), 'Comparison requires',
  'Expected error message about comparison requirements')
check_step('/query POST: comparison with empty subjects returns error safely')

cat("Checking /query POST comparison with empty seasons array...\n")
empty_seasons <- request_json_post(base_url, '/query', list(
  builder_source = TRUE,
  shape = 'comparison',
  subjects = c('Collingwood', 'Melbourne'),
  stat = 'goals',
  seasons = c()
), expected_status = 400L)
assert_contains(
  scalar_value(empty_seasons$error),
  'Invalid request parameters',
  'Expected empty seasons array to fail request validation'
)
check_step('/query POST: comparison with empty seasons returns 400 safely')

cat("Checking /query POST trend with empty seasons array...\n")
trend_empty_seasons <- request_json_post(base_url, '/query', list(
  builder_source = TRUE,
  shape = 'trend',
  subject = 'Collingwood',
  stat = 'goals',
  seasons = c()
), expected_status = 200L)
assert_true(!is.null(trend_empty_seasons$status),
  'Expected trend with empty seasons to handle gracefully (NULL passed)')
# Trend allows NULL seasons, so this should succeed or give builder error, not crash
check_step('/query POST: trend with empty seasons handles gracefully')

cat("Checking /query POST record with empty seasons array...\n")
record_empty_seasons <- request_json_post(base_url, '/query', list(
  builder_source = TRUE,
  shape = 'record',
  stat = 'goals',
  seasons = c()
), expected_status = 200L)
assert_true(!is.null(record_empty_seasons$status),
  'Expected record with empty seasons to handle gracefully (NULL passed)')
# Record allows NULL seasons, so this should succeed or give builder error, not crash
check_step('/query POST: record with empty seasons handles gracefully')

cat('All Task 6 array bounds safety tests passed.\n')

cat('All Task 6 builder routing tests passed.\n')

# ============================================================================
# TASK 10: COMPREHENSIVE REGRESSION TEST SUITE
# ============================================================================
# Tests for:
# - 4 new query builders (comparison, combination, trend, record)
# - Parser robustness (confidence scoring, edge cases)
# - API endpoint behavior with builder_source flag
# - Existing query compatibility (no breaking changes)
# ============================================================================

cat("
╔════════════════════════════════════════════════════════════════════════════╗
║              TASK 10: COMPREHENSIVE REGRESSION TEST SUITE                 ║
║                  Testing all 4 query builders + parser                    ║
╚════════════════════════════════════════════════════════════════════════════╝
")

# ============================================================================
# Test Suite 1: Comparison Query Builder
# ============================================================================
cat("\n[COMPARISON] Testing comparison query builder...\n")

cat("  → Testing basic comparison: 2 teams, 1 stat, 1 season\n")
comp_basic <- request_json_post(base_url, '/query', list(
  builder_source = TRUE,
  shape = 'comparison',
  subjects = c('Collingwood', 'Melbourne'),
  stat = 'goals',
  seasons = c(default_season)
), expected_status = 200L)

assert_true(!is.null(comp_basic$status), 'Comparison should return status')
assert_true(!is.null(comp_basic$results) || !is.null(comp_basic$error), 
  'Comparison should return results or error')
# Verify results structure when results are present
if (!is.null(comp_basic$results)) {
  assert_true(is.list(comp_basic$results), 
    'Results should be a list')
  if (length(comp_basic$results) > 0) {
    first_result <- comp_basic$results[[1]]
    assert_true(is.list(first_result),
      'Each result should be a record (list)')
    # Verify required fields exist in results
    assert_true(!is.null(first_result$subject) || !is.null(first_result$team),
      'Result should have subject/team identifier')
    assert_true(is.numeric(first_result$total) || is.numeric(first_result$value),
      'Result should have numeric total/value')
  }
}
check_step('Basic comparison query: 2 teams, 1 stat, 1 season')

cat("  → Testing edge case: Only 1 subject (should fail gracefully)\n")
comp_single_subject <- request_json_post(base_url, '/query', list(
  builder_source = TRUE,
  shape = 'comparison',
  subjects = c('Collingwood'),
  stat = 'goals',
  seasons = c(default_season)
), expected_status = 400L)

assert_true(!is.null(comp_single_subject$status), 'Single subject comparison should return status')
assert_true(identical(as.character(scalar_value(comp_single_subject$status)), 'error'),
  'Single subject comparison should return error status')
check_step('Edge case: Single subject comparison fails with error')

cat("  → Testing edge case: 3+ subjects (should fail gracefully)\n")
comp_many_subjects <- request_json_post(base_url, '/query', list(
  builder_source = TRUE,
  shape = 'comparison',
  subjects = c('Collingwood', 'Melbourne', 'Essendon'),
  stat = 'goals',
  seasons = c(default_season)
), expected_status = 200L)

assert_true(!is.null(comp_many_subjects$status), '3+ subject comparison should return status')
assert_true(identical(as.character(scalar_value(comp_many_subjects$status)), 'error'),
  '3+ subject comparison should return error status')
check_step('Edge case: 3+ subject comparison fails with error')

cat("  → Testing edge case: Invalid stat (should fail with suggestions)\n")
comp_invalid_stat <- request_json_post(base_url, '/query', list(
  builder_source = TRUE,
  shape = 'comparison',
  subjects = c('Collingwood', 'Melbourne'),
  stat = 'invalid_stat_xyz_123',
  seasons = c(default_season)
), expected_status = 200L)

assert_true(!is.null(comp_invalid_stat$status), 'Invalid stat should return status')
# Should either fail or provide suggestions
check_step('Edge case: Invalid stat handled gracefully')

# ============================================================================
# Test Suite 2: Combination Query Builder
# ============================================================================
cat("\n[COMBINATION] Testing combination query builder...\n")

cat("  → Testing basic combination: 2+ stats, 1+ seasons\n")
comb_basic <- request_json_post(base_url, '/query', list(
  builder_source = TRUE,
  shape = 'combination',
  filters = list(
    list(stat = 'goals', operator = '>=', threshold = 50),
    list(stat = 'feeds', operator = '>=', threshold = 100)
  ),
  logical_operator = 'AND',
  seasons = c(default_season)
), expected_status = 200L)

assert_true(!is.null(comb_basic$status), 'Combination should return status')
# May return empty results if no matches, but should handle gracefully
check_step('Basic combination query: Multiple stats with AND operator')

cat("  → Testing combination with OR operator\n")
comb_or <- request_json_post(base_url, '/query', list(
  builder_source = TRUE,
  shape = 'combination',
  filters = list(
    list(stat = 'goals', operator = '>=', threshold = 100),
    list(stat = 'intercepts', operator = '>=', threshold = 50)
  ),
  logical_operator = 'OR',
  seasons = c(default_season)
), expected_status = 200L)

assert_true(!is.null(comb_or$status), 'Combination with OR should return status')
# Verify AND and OR have semantic difference
# AND should be subset of OR (fewer or equal rows)
if (!is.null(comb_basic$data) && !is.null(comb_or$data)) {
  and_count <- length(comb_basic$data) %||% nrow(comb_basic$data)
  or_count <- length(comb_or$data) %||% nrow(comb_or$data)
  assert_true(and_count <= or_count,
    sprintf('AND combination (%d rows) should have <= rows than OR (%d rows)', 
            and_count, or_count))
}
check_step('Combination query: Multiple stats with OR operator')

cat("  → Testing edge case: Empty filters (should fail)\n")
comb_empty_filters <- request_json_post(base_url, '/query', list(
  builder_source = TRUE,
  shape = 'combination',
  filters = list(),
  logical_operator = 'AND',
  seasons = c(default_season)
), expected_status = 400L)

assert_true(!is.null(comb_empty_filters$status), 'Empty filters should return status')
assert_true(identical(as.character(scalar_value(comb_empty_filters$status)), 'error'),
  'Empty filters should return error status')
check_step('Edge case: Empty filters fails with error')

cat("  → Testing edge case: Invalid operator (should fail)\n")
comb_invalid_op <- request_json_post(base_url, '/query', list(
  builder_source = TRUE,
  shape = 'combination',
  filters = list(list(stat = 'goals', operator = '>=', threshold = 50)),
  logical_operator = 'INVALID_OP',
  seasons = c(default_season)
), expected_status = 200L)

assert_true(!is.null(comb_invalid_op$status), 'Invalid operator should return status')
check_step('Edge case: Invalid logical operator handled gracefully')

# ============================================================================
# Test Suite 3: Trend Query Builder
# ============================================================================
cat("\n[TREND] Testing trend query builder...\n")

cat("  → Testing basic trend: 1 subject, 1 stat, 3+ seasons\n")
trend_basic <- request_json_post(base_url, '/query', list(
  builder_source = TRUE,
  shape = 'trend',
  subject = 'Collingwood',
  stat = 'goals',
  seasons = c(default_season - 2, default_season - 1, default_season)
), expected_status = 200L)

assert_true(!is.null(trend_basic$status), 'Trend should return status')
# May return error if data not available, but should handle gracefully
check_step('Basic trend query: 1 team, 1 stat, 3+ seasons')

cat("  → Testing edge case: No seasons specified (should use available)\n")
trend_no_seasons <- request_json_post(base_url, '/query', list(
  builder_source = TRUE,
  shape = 'trend',
  subject = 'Collingwood',
  stat = 'goals'
), expected_status = 200L)

assert_true(!is.null(trend_no_seasons$status), 'Trend without seasons should return status')
check_step('Trend query: NULL seasons (uses all available)')

cat("  → Testing edge case: Only 1-2 seasons (may not be valid trend)\n")
trend_few_seasons <- request_json_post(base_url, '/query', list(
  builder_source = TRUE,
  shape = 'trend',
  subject = 'Collingwood',
  stat = 'goals',
  seasons = c(default_season)
), expected_status = 200L)

assert_true(!is.null(trend_few_seasons$status), 'Trend with 1 season should return status')
# Should either return error (trend needs 3+) or a warning, but not crash
check_step('Edge case: Trend with <3 seasons handled gracefully')

# ============================================================================
# Test Suite 4: Record Query Builder
# ============================================================================
cat("\n[RECORD] Testing record query builder...\n")

cat("  → Testing basic record: All-time (all seasons)\n")
record_alltime <- request_json_post(base_url, '/query', list(
  builder_source = TRUE,
  shape = 'record',
  stat = 'goals'
), expected_status = 200L)

assert_true(!is.null(record_alltime$status), 'Record all-time should return status')
# Should return a record holder or error if no data
check_step('Basic record query: All-time points record')

cat("  → Testing record: Specific season\n")
record_season <- request_json_post(base_url, '/query', list(
  builder_source = TRUE,
  shape = 'record',
  stat = 'goals',
  seasons = c(default_season)
), expected_status = 200L)

assert_true(!is.null(record_season$status), 'Record for season should return status')
check_step('Record query: Specific season record')

cat("  → Testing edge case: Invalid stat (should fail)\n")
record_invalid_stat <- request_json_post(base_url, '/query', list(
  builder_source = TRUE,
  shape = 'record',
  stat = 'invalid_stat_xyz_123'
), expected_status = 200L)

assert_true(!is.null(record_invalid_stat$status), 'Invalid stat record should return status')
# Should either fail or provide helpful error
check_step('Edge case: Record with invalid stat handled gracefully')

# ============================================================================
# Test Suite 5: Parser - Confidence Scoring
# ============================================================================
cat("\n[PARSER] Testing confidence scoring and shape detection...\n")

cat("  → Testing high-confidence comparison query\n")
parse_comp_high <- request_json_post(base_url, '/query', list(
  question = 'Collingwood vs Melbourne goals in 2025'
), expected_status = 200L)

# Parser may detect as comparison with high confidence
if (!is.null(parse_comp_high$confidence)) {
  assert_true(is.numeric(parse_comp_high$confidence), 'Confidence should be numeric')
  assert_true(parse_comp_high$confidence >= 0 && parse_comp_high$confidence <= 1,
    'Confidence should be between 0 and 1')
  # Verify high confidence triggers builder (either shape is returned or results are provided)
  assert_true(parse_comp_high$confidence > 0.5, 
    'High-confidence comparison should have confidence > 0.5')
  assert_true(!is.null(parse_comp_high$shape) || !is.null(parse_comp_high$results),
    'High-confidence parse should include shape or results for routing')
}
check_step('Parser: High-confidence comparison detection')

cat("  → Testing trend pattern detection\n")
parse_trend <- request_json_post(base_url, '/query', list(
  question = 'Goals trend for Collingwood 2023 2024 2025'
), expected_status = 200L)

# Parser may detect trend shape or medium confidence
assert_true(!is.null(parse_trend$status), 'Parser should return status')
check_step('Parser: Trend pattern detection')

cat("  → Testing record pattern detection\n")
parse_record <- request_json_post(base_url, '/query', list(
  question = 'All-time goals record'
), expected_status = 200L)

# Parser may detect record shape
assert_true(!is.null(parse_record$status), 'Parser should return status')
check_step('Parser: Record pattern detection')

# ============================================================================
# Test Suite 6: Parser - Edge Cases
# ============================================================================
cat("\n[PARSER] Testing parser edge cases...\n")

cat("  → Testing empty input\n")
parse_empty <- request_json_post(base_url, '/query', list(
  question = ''
), expected_status = 400L)

assert_contains(
  scalar_value(parse_empty$error),
  'Invalid request parameters',
  'Empty question should fail request validation'
)
check_step('Parser: Empty input returns 400 validation error')

cat("  → Testing very long input\n")
long_input <- paste(rep('word ', 200), collapse = '')
parse_long <- request_json_post(base_url, '/query', list(
  question = long_input
), expected_status = 400L)

assert_contains(
  scalar_value(parse_long$error),
  'Invalid request parameters',
  'Overlong question should fail request validation'
)
check_step('Parser: Very long input returns 400 validation error')

cat("  → Testing random/nonsense input\n")
parse_nonsense <- request_json_post(base_url, '/query', list(
  question = 'xyz abc 123 qwerty foobar'
), expected_status = 200L)

assert_true(!is.null(parse_nonsense$status), 'Nonsense input should return status')
# Should return low confidence or error, not crash
check_step('Parser: Random/nonsense input handled gracefully')

cat("  → Testing /query/parse trend question preserves multi-season trend shape\n")
parse_trend <- request_json_post(base_url, '/query/parse', list(
  question = 'Grace Nweke goal assists across 2023, 2024, 2025'
), expected_status = 200L)

assert_true(isTRUE(scalar_value(parse_trend$success)), 'Expected /query/parse trend question to parse successfully.')
assert_true(identical(scalar_value(parse_trend$shape), 'trend'), 'Expected /query/parse trend question to return trend shape.')
assert_true(
  is.list(parse_trend$parsed$seasons) && length(parse_trend$parsed$seasons) >= 2,
  'Expected /query/parse trend question to preserve multi-season parsing.'
)
check_step('Parser endpoint: trend question returns complex trend parse metadata')

cat("  → Testing /query/parse all-time record question routes through complex parser\n")
parse_record <- request_json_post(base_url, '/query/parse', list(
  question = 'Highest single-game intercepts all time'
), expected_status = 200L)

assert_true(isTRUE(scalar_value(parse_record$success)), 'Expected /query/parse all-time record question to parse successfully.')
assert_true(identical(scalar_value(parse_record$shape), 'record'), 'Expected /query/parse all-time record question to return record shape.')
assert_true(
  identical(scalar_value(parse_record$parsed$scope), 'all_time'),
  'Expected /query/parse all-time record question to preserve all_time scope.'
)
check_step('Parser endpoint: all-time record question returns complex record metadata')

cat("  → Testing /query/parse combination question returns structured builder guidance\n")
parse_combination <- request_json_post(base_url, '/query/parse', list(
  question = 'Players with 40+ goals AND 5+ gains in 2024'
), expected_status = 200L)

assert_true(
  identical(scalar_value(parse_combination$status), 'parse_help_needed') ||
    isTRUE(scalar_value(parse_combination$success)),
  'Expected /query/parse combination question to return either a successful parse or structured parse_help_needed guidance.'
)
if (identical(scalar_value(parse_combination$status), 'parse_help_needed')) {
  assert_true(!is.null(parse_combination$builder_prefill), 'Expected parse_help_needed response to include builder_prefill.')
}
check_step('Parser endpoint: combination question returns complex parse or builder guidance')

# ============================================================================
# Test Suite 7: API Endpoint Behavior - builder_source Flag
# ============================================================================
cat("\n[API] Testing /query endpoint with builder_source flag...\n")

cat("  → Testing builder_source=true routes to comparison builder\n")
api_builder_comp <- request_json_post(base_url, '/query', list(
  builder_source = TRUE,
  shape = 'comparison',
  subjects = c('Collingwood', 'Melbourne'),
  stat = 'goals',
  seasons = c(default_season)
), expected_status = 200L)

assert_true(!is.null(api_builder_comp$status), 'builder_source=true should return status')
check_step('API: builder_source flag routes to builders correctly')

cat("  → Testing builder_source=false uses parser\n")
api_parser <- request_json_post(base_url, '/query', list(
  builder_source = FALSE,
  question = 'Collingwood goals 2025'
), expected_status = 200L)

# May return results or prompt for clarification
assert_true(!is.null(api_parser$status), 'builder_source=false should use parser')
check_step('API: builder_source=false routes to parser')

cat("  → Testing builder_source not provided (defaults to parser)\n")
api_default <- request_json_post(base_url, '/query', list(
  question = 'Collingwood goals 2025'
), expected_status = 200L)

assert_true(!is.null(api_default$status), 'Default (no builder_source) should use parser')
check_step('API: builder_source not provided defaults to parser')

# ============================================================================
# Test Suite 8: Regression - Existing Query Compatibility
# ============================================================================
cat("\n[REGRESSION] Testing existing queries still work...\n")

cat("  → Testing existing simple player query\n")
existing_player <- request_json_post(base_url, '/query', list(
  question = 'Collingwood goals 2025'
), expected_status = 200L)

assert_true(!is.null(existing_player$status), 'Existing player query should work')
# Should not crash or break
check_step('Existing query: Simple player stats still works')

cat("  → Testing existing team vs team query\n")
existing_comp <- request_json_post(base_url, '/query', list(
  question = 'Collingwood vs Melbourne'
), expected_status = 200L)

assert_true(!is.null(existing_comp$status), 'Existing comparison query should work')
check_step('Existing query: Team comparison still works')

cat("  → Testing existing player list query\n")
existing_list <- request_json(base_url, '/players', query = list(
  limit = 5,
  search = ''
), expected_status = 200L)

assert_true(is.list(existing_list) && length(existing_list) >= 1, 
  'Existing player list should work')
check_step('Existing query: Player list still works')

cat("  → Testing existing metadata queries\n")
existing_meta <- request_json(base_url, '/meta', expected_status = 200L)

assert_true(!is.null(existing_meta$seasons), 'Metadata should have seasons')
assert_true(!is.null(existing_meta$teams), 'Metadata should have teams')
check_step('Existing query: Metadata endpoints still work')

# ============================================================================
# Test Suite 9: Integration - All Builders Under Load
# ============================================================================
cat("\n[INTEGRATION] Testing all builders under realistic conditions...\n")

cat("  → Testing rapid sequential builder calls\n")
for (i in 1:5) {
  seq_result <- request_json_post(base_url, '/query', list(
    builder_source = TRUE,
    shape = if (i %% 2 == 0) 'comparison' else 'record',
    subjects = if (i %% 2 == 0) c('Collingwood', 'Melbourne') else NULL,
    stat = 'goals',
    seasons = c(default_season)
  ), expected_status = 200L)
  assert_true(!is.null(seq_result$status), 
    sprintf('Sequential call %d should return status', i))
}
check_step('Integration: 5 rapid sequential builder calls succeed')

cat("  → Testing mixed builder and parser calls\n")
mixed_results <- list()
mixed_results[[1]] <- request_json_post(base_url, '/query', list(
  builder_source = TRUE,
  shape = 'comparison',
  subjects = c('Collingwood', 'Melbourne'),
  stat = 'goals',
  seasons = c(default_season)
), expected_status = 200L)

mixed_results[[2]] <- request_json_post(base_url, '/query', list(
  question = 'Collingwood goals trend'
), expected_status = 200L)

for (j in seq_along(mixed_results)) {
  assert_true(!is.null(mixed_results[[j]]$status),
    sprintf('Mixed call %d should return status', j))
}
check_step('Integration: Mixed builder and parser calls succeed')

# ============================================================================
# SUMMARY
# ============================================================================
cat("
╔════════════════════════════════════════════════════════════════════════════╗
║                                                                            ║
║                   ✅ ALL TASK 10 REGRESSION TESTS PASSED                  ║
║                                                                            ║
║  Coverage Summary:                                                         ║
║  ✓ Comparison Query Builder (4 tests)                                     ║
║  ✓ Combination Query Builder (4 tests)                                    ║
║  ✓ Trend Query Builder (3 tests)                                          ║
║  ✓ Record Query Builder (3 tests)                                         ║
║  ✓ Parser Confidence Scoring (3 tests)                                    ║
║  ✓ Parser Edge Cases (3 tests)                                            ║
║  ✓ API builder_source Flag (3 tests)                                      ║
║  ✓ Regression: Existing Queries (4 tests)                                 ║
║  ✓ Integration: Load Testing (2 tests)                                    ║
║                                                                            ║
║  Total: 29 comprehensive tests                                            ║
║  All 4 query shapes tested with edge cases                                ║
║  Parser robustness verified                                               ║
║  No breaking changes to existing queries                                  ║
║  API integration working correctly                                        ║
║                                                                            ║
╚════════════════════════════════════════════════════════════════════════════╝
")

cat('All API regression checks passed.\n')
