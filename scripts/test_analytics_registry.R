#!/usr/bin/env Rscript

repo_root <- normalizePath(getwd(), mustWork = TRUE)
analytics_env <- new.env(parent = baseenv())
source(file.path(repo_root, "api", "R", "analytics.R"), local = analytics_env)
source(file.path(repo_root, "api", "R", "helpers.R"), local = analytics_env)

stopifnot(is.list(analytics_env$ANALYTICAL_METRICS))

expected_keys <- c(
  "playerScoringEfficiency",
  "playerAttackInvolvementRate",
  "playerTurnoverCostRate",
  "playerDefensiveDisruption",
  "playerPressureBalance",
  "teamFinishingEfficiency",
  "teamBallSecurityRate",
  "teamDisruption",
  "teamPossessionControlBalance"
)

stopifnot(identical(sort(names(analytics_env$ANALYTICAL_METRICS)), sort(expected_keys)))

player_catalog <- analytics_env$analytics_catalog_records("player")
team_catalog <- analytics_env$analytics_catalog_records("team")

stopifnot(length(player_catalog) == 5L)
stopifnot(length(team_catalog) == 4L)
stopifnot(any(vapply(player_catalog, function(entry) identical(entry$key, "playerScoringEfficiency"), logical(1))))
stopifnot(any(vapply(team_catalog, function(entry) isTRUE(entry$prefer_low), logical(1))))

stopifnot(isTRUE(analytics_env$analytics_metric_supports_mode("playerPressureBalance", "total")))
stopifnot(!isTRUE(analytics_env$analytics_metric_supports_mode("playerScoringEfficiency", "total")))
stopifnot(identical(analytics_env$analytics_metric_default_mode("playerScoringEfficiency"), "average"))

profile_stub <- list(
  playerScoringEfficiency = 1.21,
  playerAttackInvolvementRate = 0.31,
  playerTurnoverCostRate = 0.07,
  playerDefensiveDisruption = 6.4,
  playerPressureBalance = 4.2
)

notes <- analytics_env$build_player_analytics_notes(profile_stub)
stopifnot(length(notes) >= 2L)
stopifnot(any(grepl("attacking", notes, fixed = TRUE)))
stopifnot(any(grepl("pressure", notes, fixed = TRUE)))

stopifnot(identical(analytics_env$resolve_query_stat("Which players scored 20 or more goals in 2022?"), "goals"))
stopifnot(identical(analytics_env$resolve_query_stat("top goal assists per game"), "goalAssists"))
stopifnot(is.null(analytics_env$resolve_query_stat("gibberish xyzzy nonexistent")))

cat("Analytical metric registry checks passed\n")
