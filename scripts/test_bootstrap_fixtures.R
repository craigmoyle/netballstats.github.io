#!/usr/bin/env Rscript

script_path <- function() {
  file_arg <- grep("^--file=", commandArgs(), value = TRUE)
  if (!length(file_arg)) {
    return(normalizePath(".", mustWork = FALSE))
  }

  normalizePath(sub("^--file=", "", file_arg[[1]]), mustWork = FALSE)
}

repo_root <- normalizePath(file.path(dirname(script_path()), ".."), mustWork = FALSE)
source(file.path(repo_root, "R", "bootstrap_fixtures.R"), local = TRUE)

assert_true <- function(condition, message) {
  if (!isTRUE(condition)) {
    stop(message, call. = FALSE)
  }
}

assert_true(
  identical(normalize_fixture_round_number("R7"), 7L),
  "Expected R-prefixed round labels to normalize to integers."
)
assert_true(
  identical(normalize_fixture_round_number("7"), 7L),
  "Expected numeric string rounds to normalize to integers."
)
assert_true(
  identical(normalize_fixture_round_number(8L), 8L),
  "Expected integer rounds to pass through unchanged."
)
assert_true(
  identical(normalize_fixture_match_number(3L, 9L), 3L),
  "Expected explicit match numbers to be preferred."
)
assert_true(
  identical(normalize_fixture_match_number(NULL, 9L), 9L),
  "Expected fallback game numbers to be used when match numbers are absent."
)

invalid_round_message <- tryCatch(
  {
    normalize_fixture_round_number("Final")
    NULL
  },
  error = function(error) error$message
)
assert_true(
  identical(invalid_round_message, "Fixture round number must be numeric or R-prefixed numeric."),
  "Expected invalid round labels to fail with a clear error."
)

build_database_lines <- readLines(
  file.path(repo_root, "scripts", "build_database.R"),
  warn = FALSE
)
assert_true(
  !any(grepl("\\bget_connection\\s*\\(", build_database_lines)),
  "Bootstrap should reuse the build-time database connection helper."
)
assert_true(
  !any(grepl("\\bm\\$gameNumber\\b", build_database_lines)),
  "Bootstrap should use matchNumber from the fixture API payload."
)
assert_true(
  !any(grepl("extract\\(year from local_start_time\\)", build_database_lines, fixed = TRUE)),
  "Bootstrap pre-check should not call extract(year ...) on text timestamp columns."
)
assert_true(
  !any(grepl("\\bchampion_data_match_id\\b", build_database_lines)),
  "Bootstrap insert should target the actual matches table schema."
)
assert_true(
  !any(grepl("\\bstatus\\b", build_database_lines) & grepl("INSERT INTO matches", c("", build_database_lines[-length(build_database_lines)]))),
  "Bootstrap insert should use match_status rather than a non-existent status column."
)
assert_true(
  !any(grepl('paste0\\("netball_",\\s*m\\$matchId\\)', build_database_lines)),
  "Bootstrap should preserve numeric match ids so future full builds overwrite the same matches cleanly."
)

cat("Bootstrap fixture regression checks passed\n")
