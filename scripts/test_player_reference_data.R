#!/usr/bin/env Rscript

script_path <- function() {
  file_arg <- grep("^--file=", commandArgs(), value = TRUE)
  if (!length(file_arg)) {
    return(normalizePath(".", mustWork = FALSE))
  }
  normalizePath(sub("^--file=", "", file_arg[[1]]), mustWork = FALSE)
}

repo_root <- normalizePath(file.path(dirname(script_path()), ".."), mustWork = FALSE)
source(file.path(repo_root, "R", "player_reference.R"), local = TRUE)

run_player_reference_tests <- function() {
reference_path <- file.path(repo_root, "config", "player_reference.csv")
raw_reference_rows <- utils::read.csv(reference_path, stringsAsFactors = FALSE, na.strings = "NA")
reference_rows <- read_player_reference_csv(reference_path)
invalid_reference_path <- file.path(repo_root, "config", ".player_reference_invalid_test.csv")
duplicate_reference_path <- file.path(repo_root, "config", ".player_reference_duplicate_test.csv")
template_reference_path <- file.path(repo_root, "config", ".player_reference_template_test.csv")
writeLines(
  c(
    "player_id,date_of_birth,nationality,import_status,source_label,source_url,verified_at,notes",
    "1.5,2000-01-01,Australia,local,Manual,https://example.com,2026-04-17,"
  ),
  invalid_reference_path
)
writeLines(
  c(
    "player_id,date_of_birth,nationality,import_status,source_label,source_url,verified_at,notes",
    "1,2000-01-01,Australia,local,Manual,https://example.com/1,2026-04-17,",
    "1,2001-02-02,Jamaica,import,Manual,https://example.com/2,2026-04-17,"
  ),
  duplicate_reference_path
)
writeLines(
  c(
    "player_id,player_name,date_of_birth,nationality,import_status,source_label,source_url,verified_at,notes",
    "1,Example One,,,,,,,"
  ),
  template_reference_path
)
on.exit(unlink(c(invalid_reference_path, duplicate_reference_path, template_reference_path)), add = TRUE)

stopifnot("player_name" %in% names(raw_reference_rows))
stopifnot(all(nzchar(raw_reference_rows$player_name)))
stopifnot(
  raw_reference_rows$nationality[match("Abigail Latu-Meafou", raw_reference_rows$player_name)] == "Australia"
)
stopifnot(
  raw_reference_rows$nationality[match("Alice Teague-Neeld", raw_reference_rows$player_name)] == "Australia"
)
stopifnot(
  raw_reference_rows$nationality[match("Ameliaranne Ekenasio", raw_reference_rows$player_name)] == ""
)
stopifnot(
  all(raw_reference_rows$nationality[raw_reference_rows$player_name == "Hulita Veve"] == "Tonga")
)
stopifnot(
  all(
    raw_reference_rows$source_url[raw_reference_rows$player_name == "Hulita Veve"] ==
      "https://en.wikipedia.org/wiki/Hulita_Veve"
  )
)
stopifnot(
  identical(
    names(reference_rows),
    c("player_id", "date_of_birth", "nationality", "import_status", "source_label", "source_url", "verified_at", "notes")
  )
)
stopifnot(nrow(reference_rows) >= 0)
stopifnot(identical(normalize_import_status("Import"), "import"))
stopifnot(identical(normalize_import_status("LOCAL"), "local"))
stopifnot(identical(debut_age_band(19.9), "19 and under"))
stopifnot(identical(debut_age_band(20.0), "20 to 22"))
stopifnot(identical(debut_age_band(26.0), "26 and over"))
invalid_player_id_error <- tryCatch(
  {
    read_player_reference_csv(invalid_reference_path)
    NULL
  },
  error = function(error) error$message
)
stopifnot(identical(invalid_player_id_error, "player_id must be an integer in every maintained row."))
duplicate_player_id_error <- tryCatch(
  {
    read_player_reference_csv(duplicate_reference_path)
    NULL
  },
  error = function(error) error$message
)
stopifnot(identical(duplicate_player_id_error, "player_id must be unique in the maintained player reference file."))
template_reference_rows <- read_player_reference_csv(template_reference_path)
stopifnot(nrow(template_reference_rows) == 1L)
stopifnot(identical(template_reference_rows$player_id[[1]], 1L))
stopifnot(is.na(template_reference_rows$date_of_birth[[1]]))
stopifnot(is.na(template_reference_rows$import_status[[1]]))
stopifnot(identical(template_reference_rows$notes[[1]], ""))

players_fixture <- data.frame(
  player_id = c(1L, 2L),
  canonical_name = c("Example One", "Example Two"),
  stringsAsFactors = FALSE
)

player_period_fixture <- data.frame(
  player_id = c(1L, 1L, 2L, 2L),
  season = c(2022L, 2023L, 2023L, 2024L),
  match_id = c(10L, 11L, 21L, 22L),
  squad_name = c("Swifts", "Swifts", "Fever", "Fever"),
  stringsAsFactors = FALSE
)

matches_fixture <- data.frame(
  match_id = c(10L, 11L, 21L, 22L),
  season = c(2022L, 2023L, 2023L, 2024L),
  match_date = as.Date(c("2022-04-01", "2023-03-25", "2023-03-25", "2024-03-30")),
  home_squad_id = c(1L, 1L, 2L, 2L),
  away_squad_id = c(9L, 9L, 8L, 8L),
  stringsAsFactors = FALSE
)

reference_fixture <- data.frame(
  player_id = c(1L, 2L),
  date_of_birth = as.Date(c("2003-02-10", "1995-07-01")),
  nationality = c("Australia", "Jamaica"),
  import_status = c("local", "import"),
  source_label = c("Club profile", "Club profile"),
  source_url = c("https://example.com/1", "https://example.com/2"),
  verified_at = as.Date(c("2026-04-17", "2026-04-17")),
  notes = c("", ""),
  stringsAsFactors = FALSE
)

tables <- build_player_reference_tables(players_fixture, player_period_fixture, matches_fixture, reference_fixture)

stopifnot(all(c("player_reference", "player_season_demographics", "league_composition_summary", "league_composition_debut_bands") %in% names(tables)))
stopifnot(nrow(tables$player_reference) == 2L)
stopifnot(any(tables$player_season_demographics$debut_season == 2022L))
stopifnot(any(tables$league_composition_summary$season == 2023L))
stopifnot(any(tables$league_composition_debut_bands$age_band == "19 and under"))

empty_reference_fixture <- reference_fixture[0, ]
empty_reference_tables <- build_player_reference_tables(players_fixture, player_period_fixture, matches_fixture, empty_reference_fixture)

stopifnot(nrow(empty_reference_tables$player_reference) == 2L)
stopifnot(all(empty_reference_tables$league_composition_summary$players_with_import_status == 0))
stopifnot(all(is.na(empty_reference_tables$league_composition_summary$import_share)))
stopifnot(nrow(empty_reference_tables$league_composition_debut_bands) == 0L)

missing_match_date_fixture <- matches_fixture
missing_match_date_fixture$match_date <- as.Date(rep(NA_character_, nrow(missing_match_date_fixture)))
missing_match_date_tables <- build_player_reference_tables(players_fixture, player_period_fixture, missing_match_date_fixture, reference_fixture)

stopifnot(nrow(missing_match_date_tables$player_season_demographics) == 4L)
stopifnot(all(is.na(missing_match_date_tables$player_season_demographics$match_date)))
stopifnot(all(is.na(missing_match_date_tables$league_composition_summary$average_player_age)))
stopifnot(all(is.na(missing_match_date_tables$league_composition_summary$average_debut_age)))
stopifnot(nrow(missing_match_date_tables$league_composition_debut_bands) == 0L)

cat("Player reference contract checks passed\n")
}

run_player_reference_tests()
