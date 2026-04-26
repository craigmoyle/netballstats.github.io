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

build_base_url <- function(args) {
  cli_value <- grep('^--base-url=', args, value = TRUE)
  base_url <- if (length(cli_value)) {
    sub('^--base-url=', '', cli_value[[1]])
  } else {
    Sys.getenv('NETBALL_STATS_API_BASE_URL', 'http://127.0.0.1:8000')
  }

  sub('/+$', '', trimws(base_url))
}

request_json_post <- function(base_url, path, body = list(), expected_status = 200L) {
  url <- paste0(base_url, path)
  response <- httr::POST(
    url,
    httr::add_headers(`Content-Type` = 'application/json'),
    body = jsonlite::toJSON(body, auto_unbox = TRUE),
    httr::timeout(30)
  )
  status <- httr::status_code(response)
  body_text <- httr::content(response, as = 'text', encoding = 'UTF-8')

  if (!identical(status, expected_status)) {
    stop(sprintf('Expected HTTP %s from %s, got %s. Body: %s', expected_status, url, status, body_text), call. = FALSE)
  }

  jsonlite::fromJSON(body_text, simplifyVector = FALSE)
}

args <- commandArgs(trailingOnly = TRUE)
base_url <- build_base_url(args)
cat(sprintf('Running /query/parse contract checks against %s\n', base_url))

trend_result <- request_json_post(base_url, '/query/parse', list(
  question = 'Grace Nweke goal assists across 2023, 2024, 2025'
))
assert_true(isTRUE(scalar_value(trend_result$success)), 'Expected trend question to parse successfully.')
assert_true(identical(scalar_value(trend_result$shape), 'trend'), 'Expected trend question to return trend shape.')
assert_true(
  is.list(trend_result$parsed$seasons) && length(trend_result$parsed$seasons) >= 2,
  'Expected trend question to preserve multiple parsed seasons.'
)
cat('✓ Trend contract preserved\n')

record_result <- request_json_post(base_url, '/query/parse', list(
  question = 'Highest single-game intercepts all time'
))
assert_true(isTRUE(scalar_value(record_result$success)), 'Expected all-time record question to parse successfully.')
assert_true(identical(scalar_value(record_result$shape), 'record'), 'Expected all-time record question to return record shape.')
assert_true(
  identical(scalar_value(record_result$parsed$scope), 'all_time'),
  'Expected all-time record question to preserve all_time scope.'
)
cat('✓ Record contract preserved\n')

combination_result <- request_json_post(base_url, '/query/parse', list(
  question = 'Players with 40+ goals AND 5+ gains in 2024'
))
assert_true(
  identical(scalar_value(combination_result$status), 'parse_help_needed') ||
    isTRUE(scalar_value(combination_result$success)),
  'Expected combination question to return a supported parse or structured parse_help_needed guidance.'
)
if (identical(scalar_value(combination_result$status), 'parse_help_needed')) {
  assert_true(!is.null(combination_result$builder_prefill), 'Expected parse_help_needed combination response to include builder_prefill.')
}
cat('✓ Combination contract preserved\n')

cat('All /query/parse contract checks passed.\n')
