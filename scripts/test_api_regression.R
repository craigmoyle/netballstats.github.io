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

request_json <- function(base_url, path, query = list(), expected_status = 200L) {
  url <- build_endpoint_url(base_url, path, query)
  response <- httr::GET(url, httr::timeout(30))
  status <- httr::status_code(response)
  body_text <- httr::content(response, as = 'text', encoding = 'UTF-8')

  if (!identical(status, expected_status)) {
    stop(
      sprintf('Expected HTTP %s from %s, got %s. Body: %s', expected_status, url, status, body_text),
      call. = FALSE
    )
  }

  if (!nzchar(body_text)) {
    return(list())
  }

  jsonlite::fromJSON(body_text, simplifyVector = FALSE)
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
check_step('metadata endpoint returns seasons, teams, and stat catalogs')

default_season <- as.integer(scalar_value(meta$default_season %||% meta$seasons[[1]]))
summary_payload <- request_json(base_url, '/summary', query = list(season = default_season))
assert_true(!is.null(summary_payload$total_matches), 'Expected /summary to return total_matches.')
assert_true(as.numeric(scalar_value(summary_payload$total_matches)) >= 1, 'Expected /summary to report at least one match.')
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
possessive_subject <- helpers_env$extract_query_subject_phrase(
  "What is the Swifts' highest goals total against the Vixens?",
  'highest'
)
assert_true(identical(possessive_subject, 'the Swifts'), 'Expected possessive team phrasing to normalize to the team subject.')
check_step('parser normalizes possessive team phrasing')

invalid_summary <- request_json(base_url, '/summary', query = list(season = 1900), expected_status = 400L)
assert_true(nzchar(as.character(invalid_summary$error %||% '')), 'Expected invalid requests to return an error payload.')
check_step('validation errors return a 400 response')

cat('All API regression checks passed.\n')
