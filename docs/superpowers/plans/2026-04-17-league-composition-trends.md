# League Composition Trends Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Build a new public league-composition analysis page plus player-profile identity context, backed by a maintained player reference dataset and build-time demographic summaries.

**Architecture:** Add a shared R helper for maintained player reference parsing and demographic derivation, materialize reference-backed season summaries during `scripts/build_database.R`, expose explicit read-only Plumber endpoints for whole-league trend views, then add a dedicated static page and a lightweight profile identity block on top. Keep the release honest with coverage metadata, caution states, and no guessed birthday or import values.

**Tech Stack:** R scripts, Plumber, PostgreSQL, static HTML, vanilla JavaScript, shared CSS in `assets/styles.css`, Node-based smoke checks, existing `npm run build` pipeline, Azure Static Web Apps

---

## File Map

- Create: `R/player_reference.R` — shared parser/normalizer/derivation helpers used by the DB build, API, and R-side tests.
- Create: `config/player_reference.csv` — maintained site-owned player identity and provenance source keyed by `player_id`.
- Create: `scripts/test_player_reference_data.R` — no-framework R regression script for CSV validation and demographic derivation.
- Create: `league-composition/index.html` — new public league-composition analysis page.
- Create: `assets/league-composition.js` — page controller for filters, API requests, editorial lead text, and trend/band rendering.
- Create: `scripts/verify_league_composition_ui.mjs` — built-output smoke check for the new page and player identity hooks.
- Modify: `scripts/build_database.R` — read the maintained CSV, materialize reference/demographic/league summary tables, emit coverage warnings, and grant the new tables.
- Modify: `api/R/helpers.R` — add league-composition SQL helpers and validators.
- Modify: `api/plumber.R` — source the shared helper, extend `player-profile`, and add the new analytical routes.
- Modify: `scripts/test_api_regression.R` — add route and payload coverage for the new API contract.
- Modify: `scripts/build_static.mjs` — include the new page directory and new JS asset in the static build.
- Modify: `package.json` — extend the existing `verify` path to include the new smoke check.
- Modify: `assets/styles.css` — add the new page system plus the player identity block styles.
- Modify: `assets/player.js` — render the new identity/context block from the extended `/player-profile` payload.
- Modify: `assets/telemetry.js` — map the new page to a stable sanitized page name.
- Modify: `player/index.html` — add profile identity/context markup hooks.
- Modify: `index.html`, `player/index.html`, `players/index.html`, `query/index.html`, `compare/index.html`, `round/index.html`, `scoreflow/index.html`, `home-court-advantage/index.html`, `changelog/index.html`, `nwar/index.html` — add the new nav link and `aria-current` where appropriate.
- Modify: `README.md` — document the new page and maintained reference-data requirement.
- Modify: `changelog/index.html` — add the shipped release note once the feature lands.

## Validation Commands

Use these exact commands during implementation:

- `cd /Users/craig/Git/netballstats && Rscript scripts/test_player_reference_data.R`
- `cd /Users/craig/Git/netballstats && Rscript -e "parse(file='R/player_reference.R'); parse(file='api/R/helpers.R'); parse(file='api/plumber.R'); parse(file='scripts/build_database.R'); parse(file='scripts/test_api_regression.R')"`
- `cd /Users/craig/Git/netballstats && npm run build`
- `cd /Users/craig/Git/netballstats && node scripts/verify_home_edge_breakdown.mjs`
- `cd /Users/craig/Git/netballstats && node scripts/verify_league_composition_ui.mjs`
- `cd /Users/craig/Git/netballstats && npm run build:verify`
- `cd /Users/craig/Git/netballstats && Rscript scripts/test_api_regression.R --base-url=http://127.0.0.1:8000`

Implementation should happen in a dedicated worktree, for example `feature/league-composition-trends`, before merging back to `main`.

---

### Task 1: Add the maintained reference helper and CSV contract

**Files:**
- Create: `R/player_reference.R`
- Create: `config/player_reference.csv`
- Create: `scripts/test_player_reference_data.R`
- Modify: `scripts/build_database.R`
- Modify: `api/plumber.R`

- [x] **Step 1: Write the failing R-side contract test**

Create `scripts/test_player_reference_data.R` with these exact expectations:

```r
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

reference_path <- file.path(repo_root, "config", "player_reference.csv")
reference_rows <- read_player_reference_csv(reference_path)

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

cat("Player reference contract checks passed\n")
```

- [x] **Step 2: Run the test to confirm it fails**

Run:

```bash
cd /Users/craig/Git/netballstats
Rscript scripts/test_player_reference_data.R
```

Expected: FAIL with `cannot open file '.../R/player_reference.R'`

- [x] **Step 3: Create the CSV contract and shared helper**

Create `config/player_reference.csv` with the exact header row:

```csv
player_id,date_of_birth,nationality,import_status,source_label,source_url,verified_at,notes
```

Create `R/player_reference.R` with these exact parsing and normalization helpers:

```r
`%||%` <- get0("%||%", ifnotfound = function(x, y) if (is.null(x) || length(x) == 0) y else x)

required_player_reference_columns <- function() {
  c("player_id", "date_of_birth", "nationality", "import_status", "source_label", "source_url", "verified_at", "notes")
}

normalize_import_status <- function(value) {
  normalized <- tolower(trimws(as.character(value %||% "")))
  if (!nzchar(normalized)) {
    return(NA_character_)
  }
  if (!normalized %in% c("local", "import")) {
    stop("import_status must be either 'local' or 'import'.", call. = FALSE)
  }
  normalized
}

debut_age_band <- function(age_years) {
  age_years <- suppressWarnings(as.numeric(age_years))
  if (is.na(age_years)) return(NA_character_)
  if (age_years < 20) return("19 and under")
  if (age_years < 23) return("20 to 22")
  if (age_years < 26) return("23 to 25")
  "26 and over"
}

read_player_reference_csv <- function(path) {
  rows <- utils::read.csv(path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  missing_columns <- setdiff(required_player_reference_columns(), names(rows))
  if (length(missing_columns)) {
    stop("Missing player reference columns: ", paste(missing_columns, collapse = ", "), call. = FALSE)
  }

  rows <- rows[required_player_reference_columns()]
  rows$player_id <- as.integer(rows$player_id)
  if (anyNA(rows$player_id)) {
    stop("player_id must be an integer in every maintained row.", call. = FALSE)
  }

  rows$date_of_birth <- as.Date(rows$date_of_birth)
  if (any(is.na(rows$date_of_birth))) {
    stop("date_of_birth must be ISO-8601 (YYYY-MM-DD) in every maintained row.", call. = FALSE)
  }

  rows$import_status <- vapply(rows$import_status, normalize_import_status, character(1))
  rows$nationality <- trimws(as.character(rows$nationality))
  rows$source_label <- trimws(as.character(rows$source_label))
  rows$source_url <- trimws(as.character(rows$source_url))
  rows$verified_at <- as.Date(rows$verified_at)

  if (any(!nzchar(rows$nationality))) stop("nationality is required for every maintained row.", call. = FALSE)
  if (any(!nzchar(rows$source_label))) stop("source_label is required for every maintained row.", call. = FALSE)
  if (any(!nzchar(rows$source_url))) stop("source_url is required for every maintained row.", call. = FALSE)
  if (any(is.na(rows$verified_at))) stop("verified_at must be ISO-8601 (YYYY-MM-DD) in every maintained row.", call. = FALSE)

  rows$notes <- as.character(rows$notes %||% "")
  rows
}
```

Add the shared source line near the top of both runtime entrypoints:

```r
source(file.path(repo_root_path, "R", "player_reference.R"), local = TRUE)
```

- [x] **Step 4: Re-run the contract test**

Run:

```bash
cd /Users/craig/Git/netballstats
Rscript scripts/test_player_reference_data.R
```

Expected: PASS with `Player reference contract checks passed`

- [x] **Step 5: Commit**

```bash
cd /Users/craig/Git/netballstats
git add R/player_reference.R config/player_reference.csv scripts/test_player_reference_data.R scripts/build_database.R api/plumber.R
git commit -m "feat: add player reference contract"
```

---

### Task 2: Materialize player identity and league-composition summary tables at build time

**Files:**
- Modify: `R/player_reference.R`
- Modify: `scripts/build_database.R`
- Modify: `scripts/test_player_reference_data.R`

- [x] **Step 1: Extend the failing R-side test to cover demographic derivation**

Append these exact fixture assertions to `scripts/test_player_reference_data.R` after the contract checks:

```r
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
```

- [x] **Step 2: Run the test to confirm the derivation layer is still missing**

Run:

```bash
cd /Users/craig/Git/netballstats
Rscript scripts/test_player_reference_data.R
```

Expected: FAIL with `could not find function "build_player_reference_tables"`

- [x] **Step 3: Implement the derivation helper and build wiring**

Add this exact helper to `R/player_reference.R`:

```r
season_anchor_dates <- function(matches_rows) {
  aggregate(match_date ~ season, data = matches_rows, FUN = min)
}

age_in_years_on <- function(date_of_birth, anchor_date) {
  floor(as.numeric(anchor_date - date_of_birth) / 365.25)
}

build_player_reference_tables <- function(players_rows, player_period_rows, matches_rows, reference_rows) {
  debut_rows <- aggregate(season ~ player_id, data = unique(player_period_rows[c("player_id", "season")]), FUN = min)
  names(debut_rows)[2] <- "debut_season"

  player_reference <- merge(players_rows, reference_rows, by = "player_id", all.x = TRUE, sort = FALSE)
  player_reference <- merge(player_reference, debut_rows, by = "player_id", all.x = TRUE, sort = FALSE)

  anchors <- season_anchor_dates(matches_rows)
  season_players <- unique(player_period_rows[c("player_id", "season")])
  season_players <- merge(season_players, player_reference, by = "player_id", all.x = TRUE, sort = FALSE)
  season_players <- merge(season_players, anchors, by = "season", all.x = TRUE, sort = FALSE)

  season_players$experience_seasons <- ifelse(
    is.na(season_players$debut_season),
    NA_integer_,
    as.integer(season_players$season - season_players$debut_season + 1L)
  )
  season_players$age_years <- ifelse(
    is.na(season_players$date_of_birth) | is.na(season_players$match_date),
    NA_real_,
    age_in_years_on(season_players$date_of_birth, season_players$match_date)
  )
  season_players$debut_age_band <- ifelse(
    season_players$season == season_players$debut_season,
    vapply(season_players$age_years, debut_age_band, character(1)),
    NA_character_
  )

  players_per_season <- aggregate(player_id ~ season, data = season_players, FUN = length)
  names(players_per_season)[2] <- "players_with_matches"

  age_counts <- aggregate(!is.na(age_years) ~ season, data = season_players, FUN = sum)
  names(age_counts)[2] <- "players_with_birth_date"

  import_counts <- aggregate(!is.na(import_status) ~ season, data = season_players, FUN = sum)
  names(import_counts)[2] <- "players_with_import_status"

  avg_age <- aggregate(age_years ~ season, data = season_players, FUN = function(x) round(mean(x, na.rm = TRUE), 2))
  avg_experience <- aggregate(experience_seasons ~ season, data = season_players, FUN = function(x) round(mean(x, na.rm = TRUE), 2))
  avg_debut_age <- aggregate(age_years ~ season, data = subset(season_players, season == debut_season), FUN = function(x) round(mean(x, na.rm = TRUE), 2))
  names(avg_age)[2] <- "average_player_age"
  names(avg_experience)[2] <- "average_experience_seasons"
  names(avg_debut_age)[2] <- "average_debut_age"

  import_share <- aggregate(import_status == "import" ~ season, data = subset(season_players, !is.na(import_status)), FUN = function(x) round(mean(x), 4))
  names(import_share)[2] <- "import_share"

  league_summary <- Reduce(function(left, right) merge(left, right, by = "season", all = TRUE), list(
    players_per_season, age_counts, import_counts, avg_age, avg_experience, avg_debut_age, import_share
  ))
  league_summary$age_coverage_share <- round(league_summary$players_with_birth_date / league_summary$players_with_matches, 4)
  league_summary$import_coverage_share <- round(league_summary$players_with_import_status / league_summary$players_with_matches, 4)

  debut_rows_only <- subset(season_players, season == debut_season & !is.na(debut_age_band))
  debut_band_counts <- aggregate(player_id ~ season + debut_age_band, data = debut_rows_only, FUN = length)
  names(debut_band_counts) <- c("season", "age_band", "players")
  debut_totals <- aggregate(players ~ season, data = debut_band_counts, FUN = sum)
  names(debut_totals)[2] <- "total_debut_players"
  debut_bands <- merge(debut_band_counts, debut_totals, by = "season", all.x = TRUE, sort = FALSE)
  debut_bands$share <- round(debut_bands$players / debut_bands$total_debut_players, 4)

  list(
    player_reference = player_reference,
    player_season_demographics = season_players,
    league_composition_summary = league_summary,
    league_composition_debut_bands = debut_bands
  )
}
```

Then wire `scripts/build_database.R` to read the maintained CSV and append the new tables to the existing `list(...)` returned from `prepare_match_tables()`:

```r
reference_rows <- read_player_reference_csv(file.path(repo_root_path, "config", "player_reference.csv"))
reference_tables <- build_player_reference_tables(players, player_period_stats, dplyr::bind_rows(match_rows), reference_rows)

list(
  competitions = ...,
  matches = ...,
  teams = ...,
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
```

Also add `dbWriteTable(...)`, `ANALYZE`, and `GRANT SELECT` coverage for:

```r
c("player_reference", "player_season_demographics", "league_composition_summary", "league_composition_debut_bands")
```

- [x] **Step 4: Re-run the derivation test and syntax parse**

Run:

```bash
cd /Users/craig/Git/netballstats
Rscript scripts/test_player_reference_data.R
Rscript -e "parse(file='R/player_reference.R'); parse(file='scripts/build_database.R')"
```

Expected:

- `Player reference contract checks passed`
- no parse errors

- [x] **Step 5: Commit**

```bash
cd /Users/craig/Git/netballstats
git add R/player_reference.R scripts/build_database.R scripts/test_player_reference_data.R
git commit -m "feat: materialize league composition tables"
```

---

### Task 3: Expose the new API contract and extend player-profile

**Files:**
- Modify: `api/R/helpers.R`
- Modify: `api/plumber.R`
- Modify: `scripts/test_api_regression.R`

- [x] **Step 1: Write the failing API regression coverage**

Add these exact checks to `scripts/test_api_regression.R` after the existing player-profile assertions:

```r
assert_true(is.list(profile_payload$identity), 'Expected /player-profile to include an identity block.')
assert_true("debut_season" %in% names(profile_payload$identity), 'Expected player identity to include debut_season.')
assert_true("reference_status" %in% names(profile_payload$identity), 'Expected player identity to include reference_status.')

league_summary_payload <- request_json(base_url, '/league-composition-summary')
assert_true(is.list(league_summary_payload$data), 'Expected /league-composition-summary to return rows.')
assert_true(is.list(league_summary_payload$coverage), 'Expected /league-composition-summary to return coverage metadata.')
assert_true(length(league_summary_payload$data) >= 1, 'Expected /league-composition-summary to return at least one season row.')

league_bands_payload <- request_json(base_url, '/league-composition-debut-bands')
assert_true(is.list(league_bands_payload$data), 'Expected /league-composition-debut-bands to return rows.')
assert_true(length(league_bands_payload$data) >= 1, 'Expected /league-composition-debut-bands to return at least one band row.')
```

- [x] **Step 2: Run the regression script to confirm the API contract is missing**

Run:

```bash
cd /Users/craig/Git/netballstats
Rscript scripts/test_api_regression.R --base-url=http://127.0.0.1:8000
```

Expected: FAIL on the first new assertion about `profile_payload$identity`

- [x] **Step 3: Implement the new payload block and two explicit routes**

Add these exact helper shapes in `api/R/helpers.R`:

```r
parse_composition_seasons <- function(season = "", seasons = "") {
  parse_season_filter(season, seasons)
}

query_league_composition_summary <- function(conn, seasons = NULL) {
  query <- "SELECT season, players_with_matches, players_with_birth_date, players_with_import_status, age_coverage_share, import_coverage_share, average_debut_age, average_player_age, average_experience_seasons, import_share FROM league_composition_summary WHERE 1 = 1"
  params <- list()
  if (length(seasons)) {
    placeholders <- paste(rep("?", length(seasons)), collapse = ", ")
    query <- paste0(query, " AND season IN (", placeholders, ")")
    params <- as.list(as.integer(seasons))
  }
  rows <- query_rows(conn, paste0(query, " ORDER BY season ASC"), params)

  coverage <- query_rows(
    conn,
    paste0(
      "SELECT SUM(players_with_matches) AS players_with_matches, ",
      "SUM(players_with_birth_date) AS players_with_birth_date, ",
      "SUM(players_with_import_status) AS players_with_import_status ",
      "FROM (", query, ") filtered"
    ),
    params
  )

  list(
    data = rows_to_records(rows),
    coverage = record_to_scalars(as.list(coverage[1, , drop = FALSE]))
  )
}

query_league_composition_debut_bands <- function(conn, seasons = NULL) {
  query <- "SELECT season, age_band, players, total_debut_players, share FROM league_composition_debut_bands WHERE 1 = 1"
  params <- list()
  if (length(seasons)) {
    placeholders <- paste(rep("?", length(seasons)), collapse = ", ")
    query <- paste0(query, " AND season IN (", placeholders, ")")
    params <- as.list(as.integer(seasons))
  }
  rows_to_records(query_rows(conn, paste0(query, " ORDER BY season ASC, age_band ASC"), params))
}
```

Extend `build_player_profile_payload()` in `api/plumber.R` so it accepts a third argument, `identity_row`, and returns:

```r
identity = list(
  date_of_birth = json_scalar(identity_row$date_of_birth[[1]] %||% NA_character_),
  nationality = json_scalar(identity_row$nationality[[1]] %||% NA_character_),
  import_status = json_scalar(identity_row$import_status[[1]] %||% NA_character_),
  source_label = json_scalar(identity_row$source_label[[1]] %||% NA_character_),
  source_url = json_scalar(identity_row$source_url[[1]] %||% NA_character_),
  verified_at = json_scalar(identity_row$verified_at[[1]] %||% NA_character_),
  debut_season = json_scalar(identity_row$debut_season[[1]] %||% NA_integer_),
  experience_seasons = json_scalar(identity_row$experience_seasons[[1]] %||% NA_integer_),
  reference_status = json_scalar(identity_row$reference_status[[1]] %||% "missing")
)
```

Fetch the identity row inside `/player-profile` with a `LEFT JOIN` over `player_reference` and `player_season_demographics`, then add these new routes:

```r
#* @get /league-composition-summary
#* @get /api/league-composition-summary
function(season = "", seasons = "", res) {
  conn <- tryCatch(get_db_conn(), error = function(error) error)
  if (inherits(conn, "error")) return(database_unavailable(res, conn))
  tryCatch({
    selected_seasons <- parse_composition_seasons(season, seasons)
    query_league_composition_summary(conn, selected_seasons)
  }, error = function(error) handle_request_error(error, res))
}

#* @get /league-composition-debut-bands
#* @get /api/league-composition-debut-bands
function(season = "", seasons = "", res) {
  conn <- tryCatch(get_db_conn(), error = function(error) error)
  if (inherits(conn, "error")) return(database_unavailable(res, conn))
  tryCatch({
    selected_seasons <- parse_composition_seasons(season, seasons)
    list(data = query_league_composition_debut_bands(conn, selected_seasons))
  }, error = function(error) handle_request_error(error, res))
}
```

- [x] **Step 4: Re-run parse checks and the API regression script**

Run:

```bash
cd /Users/craig/Git/netballstats
Rscript -e "parse(file='api/R/helpers.R'); parse(file='api/plumber.R'); parse(file='scripts/test_api_regression.R')"
Rscript scripts/test_api_regression.R --base-url=http://127.0.0.1:8000
```

Expected:

- no parse errors
- the new `/player-profile`, `/league-composition-summary`, and `/league-composition-debut-bands` assertions pass

- [x] **Step 5: Commit**

```bash
cd /Users/craig/Git/netballstats
git add api/R/helpers.R api/plumber.R scripts/test_api_regression.R
git commit -m "feat: add league composition api surface"
```

---

### Task 4: Add the new page shell, nav wiring, telemetry name, and build verification

**Files:**
- Create: `league-composition/index.html`
- Create: `assets/league-composition.js`
- Create: `scripts/verify_league_composition_ui.mjs`
- Modify: `scripts/build_static.mjs`
- Modify: `package.json`
- Modify: `assets/telemetry.js`
- Modify: `index.html`
- Modify: `player/index.html`
- Modify: `players/index.html`
- Modify: `query/index.html`
- Modify: `compare/index.html`
- Modify: `round/index.html`
- Modify: `scoreflow/index.html`
- Modify: `home-court-advantage/index.html`
- Modify: `changelog/index.html`
- Modify: `nwar/index.html`
- Modify: `assets/styles.css`

- [x] **Step 1: Write the failing smoke check**

Create `scripts/verify_league_composition_ui.mjs` with these exact assertions:

```js
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const distDir = path.resolve(scriptDir, "..", "dist");
const pageHtml = readFileSync(path.join(distDir, "league-composition", "index.html"), "utf8");
const playerHtml = readFileSync(path.join(distDir, "player", "index.html"), "utf8");
const stylesheetHrefMatch = pageHtml.match(/<link rel="stylesheet" href="(\/assets\/styles\.[^"]+\.css)">/);

assert.ok(stylesheetHrefMatch, "Expected the built league composition page to reference a fingerprinted stylesheet.");

const css = readFileSync(path.join(distDir, stylesheetHrefMatch[1].replace(/^\//, "")), "utf8");

assert.match(pageHtml, /league-composition-desk/, "Expected the built page to include league-composition-desk.");
assert.match(pageHtml, /league-composition-summary-body/, "Expected the built page to include league-composition-summary-body.");
assert.match(pageHtml, /league-composition-band-body/, "Expected the built page to include league-composition-band-body.");
assert.match(css, /\.league-composition-desk\b/, "Expected built CSS to include .league-composition-desk.");

console.log("League composition smoke checks passed");
```

- [x] **Step 2: Run the smoke check to confirm the new page is absent**

Run:

```bash
cd /Users/craig/Git/netballstats
npm run build && node scripts/verify_league_composition_ui.mjs
```

Expected: FAIL with `ENOENT` for `dist/league-composition/index.html`

- [x] **Step 3: Add the page shell, build registration, nav link, and telemetry name**

Create `league-composition/index.html` with this exact shell:

```html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <script src="/assets/theme.js"></script>
    <title>League Composition | Netball Stats Database</title>
    <meta name="description" content="Track youth break-ins, league age and experience, and import share across the netball archive.">
    <link rel="preload" href="/assets/fonts/fraunces-latin.woff2" as="font" type="font/woff2" crossorigin>
    <link rel="preload" href="/assets/fonts/teko-600-latin.woff2" as="font" type="font/woff2" crossorigin>
    <link rel="stylesheet" href="/assets/styles.css">
    <script defer src="/assets/config.js"></script>
    <script defer src="/assets/telemetry.js"></script>
    <script defer src="/assets/league-composition.js"></script>
  </head>
  <body class="league-composition-page">
    <a href="#main-content" class="skip-link">Skip to content</a>
    <header class="page-shell hero-shell reveal">
      <nav class="page-nav" aria-label="Site navigation">
        <a class="page-nav__link" href="/">Explore archive</a>
        <a class="page-nav__link" href="/league-composition/" aria-current="page">League composition</a>
        <a class="page-nav__link" href="/round/">Round recap</a>
        <a class="page-nav__link" href="/scoreflow/">Scoreflow</a>
        <a class="page-nav__link" href="/players/">Player profiles</a>
        <a class="page-nav__link" href="/query/">Ask the stats</a>
        <a class="page-nav__link" href="/compare/">Compare</a>
        <a class="page-nav__link" href="/home-court-advantage/">Home court advantage</a>
        <a class="page-nav__link" href="/changelog/">Changelog</a>
        <a class="page-nav__link" href="/nwar/">nWAR</a>
        <button type="button" class="theme-toggle" id="theme-toggle" aria-label="Switch to light theme">Light</button>
      </nav>
      <section class="hero-panel composition-hero">
        <div class="hero-copy">
          <p class="eyebrow">League composition archive</p>
          <h1>Who is getting into the league?</h1>
          <p class="intro-copy">Track debut age, league age and experience, and import share season by season.</p>
        </div>
      </section>
    </header>
    <main id="main-content" class="page-shell page-main">
      <section class="panel reveal league-composition-desk">
        <div id="league-composition-status" class="status-banner" role="status" aria-live="polite" hidden></div>
        <div class="panel__heading">
          <p class="panel__eyebrow">Composition desk</p>
          <h2>Choose the season frame</h2>
          <p id="league-composition-meta" class="panel__lead">Loading season coverage…</p>
        </div>
        <form id="league-composition-filters" class="filters filters--dashboard" aria-label="League composition filters">
          <fieldset class="field field--wide">
            <legend>Seasons</legend>
            <div id="league-composition-season-choices" class="season-choices" role="group" aria-label="Season choices"></div>
          </fieldset>
        </form>
      </section>
      <section class="panel reveal">
        <div class="panel__heading">
          <p class="panel__eyebrow">League summary</p>
          <h2>Season-by-season trends</h2>
        </div>
        <div class="table-wrapper">
          <table class="stack-table">
            <tbody id="league-composition-summary-body"></tbody>
          </table>
        </div>
      </section>
      <section class="panel reveal">
        <div class="panel__heading">
          <p class="panel__eyebrow">Youth break-ins</p>
          <h2>Debut age bands</h2>
        </div>
        <div class="table-wrapper">
          <table class="stack-table">
            <tbody id="league-composition-band-body"></tbody>
          </table>
        </div>
      </section>
    </main>
  </body>
</html>
```

Create the initial JS stub:

```js
const { showStatusBanner = () => {} } = window.NetballStatsUI || {};
showStatusBanner(document.getElementById("league-composition-status"), "Loading league composition…", "loading");
```

Register the new page in `scripts/build_static.mjs`:

```js
const staticEntries = ['changelog', 'home-court-advantage', 'index.html', 'compare', 'league-composition', 'nwar', 'player', 'players', 'query', 'round', 'scoreflow', 'staticwebapp.config.json'];
const htmlEntries = ['changelog/index.html', 'home-court-advantage/index.html', 'index.html', 'compare/index.html', 'league-composition/index.html', 'nwar/index.html', 'player/index.html', 'players/index.html', 'query/index.html', 'round/index.html', 'scoreflow/index.html'];
const fingerprintedAssets = ['app.js', 'charts.js', 'compare.js', 'config.js', 'home-court-advantage.js', 'league-composition.js', 'nwar.js', 'player.js', 'players.js', 'query.js', 'round.js', 'scoreflow.js', 'styles.css', 'telemetry.js', 'theme.js'];
```

Extend `package.json` to keep the repo’s verify path current:

```json
"scripts": {
  "build": "node scripts/build_static.mjs",
  "verify": "node scripts/verify_home_edge_breakdown.mjs && node scripts/verify_league_composition_ui.mjs",
  "build:verify": "npm run build && npm run verify"
}
```

Add the stable page name to `assets/telemetry.js`:

```js
if (pathname === "/league-composition") {
  return "league-composition";
}
```

Add the same nav link to every page-level `*/index.html`, using `aria-current="page"` only on the active page.

Add the minimal CSS selectors:

```css
.league-composition-desk,
.player-identity-card {
  position: relative;
  overflow: hidden;
}
```

- [x] **Step 4: Re-run the build and smoke checks**

Run:

```bash
cd /Users/craig/Git/netballstats
npm run build
node scripts/verify_home_edge_breakdown.mjs
node scripts/verify_league_composition_ui.mjs
```

Expected:

- `Home Court Advantage breakdown smoke checks passed`
- `League composition smoke checks passed`

- [x] **Step 5: Commit**

```bash
cd /Users/craig/Git/netballstats
git add league-composition/index.html assets/league-composition.js scripts/verify_league_composition_ui.mjs scripts/build_static.mjs package.json assets/telemetry.js assets/styles.css index.html player/index.html players/index.html query/index.html compare/index.html round/index.html scoreflow/index.html home-court-advantage/index.html changelog/index.html nwar/index.html
git commit -m "feat: add league composition page shell"
```

---

### Task 5: Render the new page from the analytical endpoints

**Files:**
- Modify: `assets/league-composition.js`
- Modify: `league-composition/index.html`
- Modify: `assets/styles.css`

- [x] **Step 1: Extend the smoke check with page-rendering hooks**

Append these exact assertions to `scripts/verify_league_composition_ui.mjs`:

```js
assert.match(pageHtml, /league-composition-editorial-lead/, "Expected the built page to include league-composition-editorial-lead.");
assert.match(pageHtml, /league-composition-coverage-note/, "Expected the built page to include league-composition-coverage-note.");
assert.match(css, /\.league-composition-editorial-lead\b/, "Expected built CSS to include .league-composition-editorial-lead.");
assert.match(css, /\.league-composition-coverage-note\b/, "Expected built CSS to include .league-composition-coverage-note.");
```

- [x] **Step 2: Run the smoke check to confirm the richer hooks are still missing**

Run:

```bash
cd /Users/craig/Git/netballstats
npm run build && node scripts/verify_league_composition_ui.mjs
```

Expected: FAIL with `Expected the built page to include league-composition-editorial-lead`

- [x] **Step 3: Implement the page controller and coverage-aware rendering**

Update `league-composition/index.html` so the new editorial lead and coverage block exist above the tables:

```html
<section class="panel reveal league-composition-editorial-lead">
  <div class="panel__heading">
    <p class="panel__eyebrow">Editorial lead</p>
    <h2 id="league-composition-lead-headline">Loading the current league frame…</h2>
    <p id="league-composition-lead-copy" class="panel__lead">Reading the trend story across the selected seasons.</p>
  </div>
  <p id="league-composition-coverage-note" class="league-composition-coverage-note">Checking age and import coverage…</p>
</section>
```

Replace `assets/league-composition.js` with this exact controller shape:

```js
const {
  fetchJson,
  getCheckedValues = () => [],
  renderEmptyTableRow = () => {},
  showStatusBanner = () => {},
  syncResponsiveTable = () => {}
} = window.NetballStatsUI || {};

const state = {
  seasons: [],
  summary: [],
  bands: []
};

const elements = {
  status: document.getElementById("league-composition-status"),
  meta: document.getElementById("league-composition-meta"),
  leadHeadline: document.getElementById("league-composition-lead-headline"),
  leadCopy: document.getElementById("league-composition-lead-copy"),
  coverageNote: document.getElementById("league-composition-coverage-note"),
  seasonChoices: document.getElementById("league-composition-season-choices"),
  summaryBody: document.getElementById("league-composition-summary-body"),
  bandBody: document.getElementById("league-composition-band-body")
};

function selectedSeasons() {
  return getCheckedValues(elements.seasonChoices).sort((a, b) => Number(a) - Number(b));
}

function renderSummaryRows(rows) {
  elements.summaryBody.replaceChildren();
  if (!rows.length) {
    renderEmptyTableRow(elements.summaryBody, "No league-composition rows match this season frame.", { colSpan: 1, kicker: "No rows" });
    return;
  }

  const fragment = document.createDocumentFragment();
  rows.forEach((row) => {
    const tr = document.createElement("tr");
    const td = document.createElement("td");
    td.dataset.stackPrimary = "true";
    td.textContent = `${row.season}: debut age ${row.average_debut_age ?? "—"}, league age ${row.average_player_age ?? "—"}, experience ${row.average_experience_seasons ?? "—"}, import share ${row.import_share != null ? `${(Number(row.import_share) * 100).toFixed(1)}%` : "—"}`;
    tr.appendChild(td);
    fragment.appendChild(tr);
  });
  elements.summaryBody.appendChild(fragment);
  syncResponsiveTable(elements.summaryBody.closest("table"));
}

function renderBandRows(rows) {
  elements.bandBody.replaceChildren();
  if (!rows.length) {
    renderEmptyTableRow(elements.bandBody, "No debut-age band rows match this season frame.", { colSpan: 1, kicker: "No bands" });
    return;
  }

  const fragment = document.createDocumentFragment();
  rows.forEach((row) => {
    const tr = document.createElement("tr");
    const td = document.createElement("td");
    td.textContent = `${row.season}: ${row.age_band} — ${row.players} debut players (${(Number(row.share) * 100).toFixed(1)}%)`;
    tr.appendChild(td);
    fragment.appendChild(tr);
  });
  elements.bandBody.appendChild(fragment);
  syncResponsiveTable(elements.bandBody.closest("table"));
}

function renderCoverage(summaryPayload) {
  const ageCoverage = Number(summaryPayload.coverage?.players_with_birth_date || 0) / Number(summaryPayload.coverage?.players_with_matches || 1);
  const importCoverage = Number(summaryPayload.coverage?.players_with_import_status || 0) / Number(summaryPayload.coverage?.players_with_matches || 1);
  const coverageFloor = Math.min(ageCoverage, importCoverage);

  elements.coverageNote.textContent = coverageFloor < 0.85
    ? "Coverage is below the release target for at least one maintained field, so treat the trend lines as partial rather than final."
    : "Coverage is above the release target for age and import classifications in the selected season frame.";
}

function renderLead(rows) {
  const latest = rows[rows.length - 1];
  if (!latest) {
    elements.leadHeadline.textContent = "No league-composition seasons match this filter.";
    elements.leadCopy.textContent = "Try a broader season range.";
    return;
  }
  elements.leadHeadline.textContent = `${latest.season}: debut age ${latest.average_debut_age ?? "—"}, average age ${latest.average_player_age ?? "—"}`;
  elements.leadCopy.textContent = `The current frame shows ${latest.average_experience_seasons ?? "—"} average seasons of experience and ${latest.import_share != null ? `${(Number(latest.import_share) * 100).toFixed(1)}%` : "—"} import share.`;
}

async function loadPage() {
  showStatusBanner(elements.status, "Loading league composition…", "loading");
  const seasons = selectedSeasons();
  const params = seasons.length ? { seasons: seasons.join(",") } : {};

  const [summaryPayload, bandsPayload] = await Promise.all([
    fetchJson("/league-composition-summary", params),
    fetchJson("/league-composition-debut-bands", params)
  ]);

  state.summary = summaryPayload.data || [];
  state.bands = bandsPayload.data || [];
  elements.meta.textContent = seasons.length ? `Showing ${seasons.length} selected seasons.` : "Showing all seasons.";
  renderLead(state.summary);
  renderCoverage(summaryPayload);
  renderSummaryRows(state.summary);
  renderBandRows(state.bands);
  showStatusBanner(elements.status, "");
}

window.addEventListener("DOMContentLoaded", loadPage);
```

Add the matching CSS:

```css
.league-composition-editorial-lead {
  background:
    linear-gradient(180deg, color-mix(in srgb, var(--accent) 8%, transparent), transparent 44%),
    var(--panel-solid);
}

.league-composition-coverage-note {
  margin: 0;
  color: var(--muted);
  font-size: var(--text-ui-size);
  line-height: 1.65;
}
```

- [x] **Step 4: Re-run build verification**

Run:

```bash
cd /Users/craig/Git/netballstats
npm run build:verify
node scripts/verify_league_composition_ui.mjs
```

Expected:

- `League composition smoke checks passed`
- `Home Court Advantage breakdown smoke checks passed`

- [x] **Step 5: Commit**

```bash
cd /Users/craig/Git/netballstats
git add league-composition/index.html assets/league-composition.js assets/styles.css scripts/verify_league_composition_ui.mjs
git commit -m "feat: render league composition analysis page"
```

---

### Task 6: Add the profile identity block and finish the docs

**Files:**
- Modify: `player/index.html`
- Modify: `assets/player.js`
- Modify: `assets/styles.css`
- Modify: `README.md`
- Modify: `changelog/index.html`

- [x] **Step 1: Extend the smoke check with the final dossier hooks**

Append these exact assertions to `scripts/verify_league_composition_ui.mjs`:

```js
assert.match(playerHtml, /player-identity-card/, "Expected the built player page to include player-identity-card.");
assert.match(playerHtml, /player-identity-list/, "Expected the built player page to include player-identity-list.");
assert.match(playerHtml, /player-identity-status/, "Expected the built player page to include player-identity-status.");
assert.match(css, /\.player-identity-card\b/, "Expected built CSS to include .player-identity-card.");
assert.match(css, /\.player-identity-list\b/, "Expected built CSS to include .player-identity-list.");
assert.match(css, /\.player-identity-status\b/, "Expected built CSS to include .player-identity-status.");
```

- [x] **Step 2: Run the smoke check to confirm the dossier identity block is still incomplete**

Run:

```bash
cd /Users/craig/Git/netballstats
npm run build && node scripts/verify_league_composition_ui.mjs
```

Expected: FAIL with `Expected the built player page to include player-identity-list`

- [x] **Step 3: Add the markup, renderer, and neutral fallback states**

Insert this exact block into `player/index.html` immediately after the career snapshot summary panel:

```html
<section class="panel reveal player-identity-card" aria-label="Player identity and debut context">
  <div class="panel__heading">
    <p class="panel__eyebrow">Identity context</p>
    <h2>Profile context</h2>
    <p id="player-identity-status" class="panel__lead">Loading birthday, nationality, debut, and import context.</p>
  </div>
  <dl id="player-identity-list" class="player-identity-list"></dl>
</section>
```

Update `assets/player.js` with these exact additions:

```js
elements.playerIdentityStatus = document.getElementById("player-identity-status");
elements.playerIdentityList = document.getElementById("player-identity-list");

function renderIdentityRow(label, value) {
  const fragment = document.createDocumentFragment();
  const dt = document.createElement("dt");
  dt.textContent = label;
  const dd = document.createElement("dd");
  dd.textContent = value || "Not yet verified";
  fragment.append(dt, dd);
  return fragment;
}

function renderPlayerIdentity(profile) {
  const identity = profile.identity || {};
  elements.playerIdentityList.replaceChildren(
    renderIdentityRow("Birthday", identity.date_of_birth),
    renderIdentityRow("Nationality", identity.nationality),
    renderIdentityRow("Import status", identity.import_status),
    renderIdentityRow("Debut season", identity.debut_season != null ? `${identity.debut_season}` : ""),
    renderIdentityRow("Experience", identity.experience_seasons != null ? `Season ${identity.experience_seasons}` : "")
  );

  elements.playerIdentityStatus.textContent = identity.reference_status === "missing"
    ? "Some maintained identity fields are not yet verified for this player."
    : `Verified against ${identity.source_label || "the maintained player reference file"}.`;
}
```

Call `renderPlayerIdentity(profile);` inside the existing successful load path, after `renderSquads(...)` and before the career tables are filled.

Add the CSS:

```css
.player-identity-card {
  background:
    linear-gradient(180deg, color-mix(in srgb, var(--accent-cool) 6%, transparent), transparent 44%),
    var(--panel-solid);
}

.player-identity-list {
  display: grid;
  grid-template-columns: repeat(5, minmax(0, 1fr));
  gap: 0.85rem;
}

.player-identity-list dt {
  color: var(--muted);
  font-size: var(--type-xs);
  letter-spacing: var(--tracking-kicker);
  text-transform: uppercase;
}

.player-identity-list dd {
  margin: 0.25rem 0 0;
}

.player-identity-status {
  margin: 0;
}
```

Update `README.md` with a short feature note under the product surface list:

```md
- `league-composition/`: season-by-season youth break-in, league age/experience, and import-share analysis backed by the maintained `config/player_reference.csv` reference file
```

Add the shipped changelog entry to `changelog/index.html` once the branch is ready to merge.

- [x] **Step 4: Re-run the final frontend and API validations**

Run:

```bash
cd /Users/craig/Git/netballstats
Rscript -e "parse(file='api/R/helpers.R'); parse(file='api/plumber.R'); parse(file='scripts/build_database.R'); parse(file='scripts/test_api_regression.R')"
npm run build:verify
node scripts/verify_league_composition_ui.mjs
Rscript scripts/test_api_regression.R --base-url=http://127.0.0.1:8000
```

Expected:

- no parse errors
- `League composition smoke checks passed`
- the new `/player-profile` identity assertions pass

- [x] **Step 5: Commit**

```bash
cd /Users/craig/Git/netballstats
git add player/index.html assets/player.js assets/styles.css README.md changelog/index.html scripts/verify_league_composition_ui.mjs
git commit -m "feat: add player identity context and docs"
```

---

## Spec Coverage Check

- **New public analysis page:** covered by Tasks 4 and 5.
- **Player profile enrichment:** covered by Task 6.
- **Maintained reference layer:** covered by Tasks 1 and 2.
- **Derived debut/age/experience/import summaries:** covered by Task 2.
- **Purpose-built API endpoints and coverage metadata:** covered by Task 3.
- **Coverage notes, neutral missing states, and no guessed values:** covered by Tasks 3, 5, and 6.
- **Docs and shipped release note:** covered by Task 6.

## Placeholder Scan

- No `TODO`, `TBD`, or “implement later” markers remain.
- Every code-editing step includes exact file paths and concrete code blocks.
- Every validation step uses exact commands already aligned to the repo’s current toolchain.

## Type/Name Consistency Check

- Maintained source file: `config/player_reference.csv`
- Shared helper file: `R/player_reference.R`
- Derived tables: `player_reference`, `player_season_demographics`, `league_composition_summary`, `league_composition_debut_bands`
- API routes: `/league-composition-summary`, `/league-composition-debut-bands`
- Frontend page path: `/league-composition/`
- Profile payload block: `identity`
