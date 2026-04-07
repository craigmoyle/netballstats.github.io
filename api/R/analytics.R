`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || all(is.na(x))) y else x

ANALYTICAL_METRICS <- list(
  playerScoringEfficiency = list(
    key = "playerScoringEfficiency",
    subject = "player",
    family = "Efficiency",
    label = "Scoring Efficiency",
    short_label = "Score Eff",
    description = "Points scored per shooting attempt.",
    formula = "(goal1 + 2 * goal2) / goalAttempts",
    metric_modes = c("average"),
    prefer_low = FALSE,
    valid_from_season = 2008L
  ),
  playerAttackInvolvementRate = list(
    key = "playerAttackInvolvementRate",
    subject = "player",
    family = "Involvement",
    label = "Attack Involvement Rate",
    short_label = "Atk Involve",
    description = "Share of a team's attacking actions driven by the player.",
    formula = "(feeds + goalAssists + centrePassReceives + goalAttempts) / team_attacking_actions",
    metric_modes = c("average"),
    prefer_low = FALSE,
    valid_from_season = 2008L
  ),
  playerTurnoverCostRate = list(
    key = "playerTurnoverCostRate",
    subject = "player",
    family = "Ball Security and Pressure",
    label = "Turnover Cost Rate",
    short_label = "TO Cost",
    description = "Possession giveaways relative to the player's attacking load.",
    formula = "(generalPlayTurnovers + unforcedTurnovers + interceptPassThrown) / player_attacking_actions",
    metric_modes = c("average"),
    prefer_low = TRUE,
    valid_from_season = 2008L
  ),
  playerDefensiveDisruption = list(
    key = "playerDefensiveDisruption",
    subject = "player",
    family = "Ball Security and Pressure",
    label = "Defensive Disruption",
    short_label = "Disruption",
    description = "Total defensive disruption created from gains, intercepts, deflections, and rebounds.",
    formula = "gain + intercepts + deflections + rebounds",
    metric_modes = c("total", "average"),
    prefer_low = FALSE,
    valid_from_season = 2008L
  ),
  playerPressureBalance = list(
    key = "playerPressureBalance",
    subject = "player",
    family = "Ball Security and Pressure",
    label = "Pressure Balance",
    short_label = "Press Bal",
    description = "Defensive disruption created minus direct possession giveaways.",
    formula = "playerDefensiveDisruption - (generalPlayTurnovers + unforcedTurnovers + interceptPassThrown)",
    metric_modes = c("total", "average"),
    prefer_low = FALSE,
    valid_from_season = 2008L
  ),
  teamFinishingEfficiency = list(
    key = "teamFinishingEfficiency",
    subject = "team",
    family = "Efficiency",
    label = "Finishing Efficiency",
    short_label = "Finish Eff",
    description = "Points scored per team shooting attempt.",
    formula = "points / goalAttempts",
    metric_modes = c("average"),
    prefer_low = FALSE,
    valid_from_season = 2008L
  ),
  teamBallSecurityRate = list(
    key = "teamBallSecurityRate",
    subject = "team",
    family = "Ball Security and Pressure",
    label = "Ball Security Rate",
    short_label = "Ball Sec",
    description = "Turnovers committed per team possession.",
    formula = "(generalPlayTurnovers + unforcedTurnovers) / possessions",
    metric_modes = c("average"),
    prefer_low = TRUE,
    valid_from_season = 2008L
  ),
  teamDisruption = list(
    key = "teamDisruption",
    subject = "team",
    family = "Ball Security and Pressure",
    label = "Team Disruption",
    short_label = "Disruption",
    description = "Combined gains, intercepts, and deflections.",
    formula = "gain + intercepts + deflections",
    metric_modes = c("total", "average"),
    prefer_low = FALSE,
    valid_from_season = 2008L
  ),
  teamPossessionControlBalance = list(
    key = "teamPossessionControlBalance",
    subject = "team",
    family = "Ball Security and Pressure",
    label = "Possession Control Balance",
    short_label = "Control Bal",
    description = "Ball-winning events created minus direct turnover giveaways.",
    formula = "(gain + intercepts) - (generalPlayTurnovers + unforcedTurnovers)",
    metric_modes = c("total", "average"),
    prefer_low = FALSE,
    valid_from_season = 2008L
  )
)

analytics_metric_definition <- function(key) ANALYTICAL_METRICS[[key]] %||% NULL

analytics_metric_keys <- function(subject = c("player", "team")) {
  subject <- match.arg(subject)
  names(Filter(function(def) identical(def$subject, subject), ANALYTICAL_METRICS))
}

is_analytical_metric <- function(key, subject = NULL) {
  definition <- analytics_metric_definition(key)
  if (is.null(definition)) {
    return(FALSE)
  }
  if (is.null(subject)) {
    return(TRUE)
  }
  identical(definition$subject, subject)
}

analytics_metric_supports_mode <- function(key, metric_mode) {
  definition <- analytics_metric_definition(key)
  !is.null(definition) && metric_mode %in% definition$metric_modes
}

analytics_metric_default_mode <- function(key) {
  definition <- analytics_metric_definition(key)
  if (is.null(definition)) "total" else definition$metric_modes[[1]]
}

analytics_catalog_records <- function(subject = c("player", "team")) {
  subject <- match.arg(subject)
  lapply(analytics_metric_keys(subject), function(key) {
    definition <- analytics_metric_definition(key)
    list(
      key = definition$key,
      label = definition$label,
      short_label = definition$short_label,
      family = definition$family,
      description = definition$description,
      formula = definition$formula,
      metric_modes = definition$metric_modes,
      prefer_low = definition$prefer_low,
      valid_from_season = definition$valid_from_season
    )
  })
}

build_player_analytics_notes <- function(profile_values) {
  notes <- character()

  if (!is.null(profile_values$playerAttackInvolvementRate) && profile_values$playerAttackInvolvementRate >= 0.28) {
    notes <- c(notes, "High attacking involvement: the player sits at the centre of a large share of their team's ball flow.")
  }
  if (!is.null(profile_values$playerScoringEfficiency) && profile_values$playerScoringEfficiency >= 1.05) {
    notes <- c(notes, "Efficient finisher: shot output converts into points at a strong rate.")
  }
  if (!is.null(profile_values$playerTurnoverCostRate) && profile_values$playerTurnoverCostRate <= 0.10) {
    notes <- c(notes, "Ball-secure under load: possessions are rarely wasted relative to attacking responsibility.")
  }
  if (!is.null(profile_values$playerPressureBalance) && profile_values$playerPressureBalance >= 3) {
    notes <- c(notes, "Positive pressure balance: defensive disruption comfortably outweighs direct giveaways.")
  }

  unique(notes)
}

player_analytics_match_rows <- function(conn, metric_key, seasons = NULL, team_id = NULL, round = NULL, search = "") {
  if (!has_player_match_stats(conn)) {
    return(data.frame(
      player_id = integer(0), player_name = character(0), squad_name = character(0),
      squad_id = integer(0), season = integer(0), round_number = integer(0),
      match_id = integer(0), metric_value = numeric(0), stringsAsFactors = FALSE
    ))
  }
  query <- paste(
    "WITH player_base AS (",
    "  SELECT stats.player_id, players.canonical_name AS player_name, MAX(stats.squad_name) AS squad_name,",
    "    stats.squad_id, stats.match_id, stats.season, stats.round_number,",
    "    SUM(CASE WHEN stats.stat = 'goal1' THEN stats.match_value ELSE 0 END) AS goal1,",
    "    SUM(CASE WHEN stats.stat = 'goal2' THEN stats.match_value ELSE 0 END) AS goal2,",
    "    SUM(CASE WHEN stats.stat = 'goalAttempts' THEN stats.match_value ELSE 0 END) AS goal_attempts,",
    "    SUM(CASE WHEN stats.stat = 'feeds' THEN stats.match_value ELSE 0 END) AS feeds,",
    "    SUM(CASE WHEN stats.stat = 'goalAssists' THEN stats.match_value ELSE 0 END) AS goal_assists,",
    "    SUM(CASE WHEN stats.stat = 'centrePassReceives' THEN stats.match_value ELSE 0 END) AS centre_pass_receives,",
    "    SUM(CASE WHEN stats.stat = 'generalPlayTurnovers' THEN stats.match_value ELSE 0 END) AS general_play_turnovers,",
    "    SUM(CASE WHEN stats.stat = 'unforcedTurnovers' THEN stats.match_value ELSE 0 END) AS unforced_turnovers,",
    "    SUM(CASE WHEN stats.stat = 'interceptPassThrown' THEN stats.match_value ELSE 0 END) AS intercept_pass_thrown,",
    "    SUM(CASE WHEN stats.stat = 'gain' THEN stats.match_value ELSE 0 END) AS gain,",
    "    SUM(CASE WHEN stats.stat = 'intercepts' THEN stats.match_value ELSE 0 END) AS intercepts,",
    "    SUM(CASE WHEN stats.stat = 'deflections' THEN stats.match_value ELSE 0 END) AS deflections,",
    "    SUM(CASE WHEN stats.stat = 'rebounds' THEN stats.match_value ELSE 0 END) AS rebounds",
    "  FROM player_match_stats AS stats",
    "  INNER JOIN players ON players.player_id = stats.player_id",
    "  WHERE stats.stat IN ('goal1','goal2','goalAttempts','feeds','goalAssists','centrePassReceives','generalPlayTurnovers','unforcedTurnovers','interceptPassThrown','gain','intercepts','deflections','rebounds')",
    "  GROUP BY stats.player_id, players.canonical_name, stats.squad_id, stats.match_id, stats.season, stats.round_number",
    "), team_context AS (",
    "  SELECT squad_id, match_id,",
    "    SUM(feeds + goal_assists + centre_pass_receives + goal_attempts) AS team_attacking_actions",
    "  FROM player_base",
    "  GROUP BY squad_id, match_id",
    ")",
    "SELECT player_base.player_id, player_base.player_name, player_base.squad_name,",
    "  player_base.squad_id, player_base.season, player_base.round_number, player_base.match_id,",
    "  CASE",
    "    WHEN ?metric_key = 'playerScoringEfficiency' THEN ROUND(CAST((player_base.goal1 + 2 * player_base.goal2) / NULLIF(player_base.goal_attempts, 0) AS numeric), 4)",
    "    WHEN ?metric_key = 'playerAttackInvolvementRate' THEN ROUND(CAST((player_base.feeds + player_base.goal_assists + player_base.centre_pass_receives + player_base.goal_attempts) / NULLIF(team_context.team_attacking_actions, 0) AS numeric), 4)",
    "    WHEN ?metric_key = 'playerTurnoverCostRate' THEN ROUND(CAST((player_base.general_play_turnovers + player_base.unforced_turnovers + player_base.intercept_pass_thrown) / NULLIF(player_base.feeds + player_base.goal_assists + player_base.centre_pass_receives + player_base.goal_attempts, 0) AS numeric), 4)",
    "    WHEN ?metric_key = 'playerDefensiveDisruption' THEN ROUND(CAST(player_base.gain + player_base.intercepts + player_base.deflections + player_base.rebounds AS numeric), 4)",
    "    WHEN ?metric_key = 'playerPressureBalance' THEN ROUND(CAST((player_base.gain + player_base.intercepts + player_base.deflections + player_base.rebounds) - (player_base.general_play_turnovers + player_base.unforced_turnovers + player_base.intercept_pass_thrown) AS numeric), 4)",
    "    ELSE NULL",
    "  END AS metric_value",
    "FROM player_base",
    "INNER JOIN team_context ON team_context.squad_id = player_base.squad_id AND team_context.match_id = player_base.match_id",
    "WHERE 1 = 1"
  )

  filters <- apply_stat_filters(query, list(metric_key = metric_key), seasons = seasons, team_id = team_id, round_number = round, table_alias = "player_base")
  filters <- apply_player_search_filter(filters$query, filters$params, search, "player_base.player_id")
  rows <- query_rows(conn, filters$query, filters$params)
  rows[!is.na(rows$metric_value), , drop = FALSE]
}

team_analytics_match_rows <- function(conn, metric_key, seasons = NULL, team_id = NULL, round = NULL) {
  query <- paste(
    "WITH team_base AS (",
    "  SELECT stats.squad_id, MAX(stats.squad_name) AS squad_name, stats.match_id, stats.season, stats.round_number,",
    "    SUM(CASE WHEN stats.stat = 'goal1' THEN stats.value_number ELSE 0 END) AS goal1,",
    "    SUM(CASE WHEN stats.stat = 'goal2' THEN stats.value_number ELSE 0 END) AS goal2,",
    "    SUM(CASE WHEN stats.stat = 'goalAttempts' THEN stats.value_number ELSE 0 END) AS goal_attempts,",
    "    SUM(CASE WHEN stats.stat = 'generalPlayTurnovers' THEN stats.value_number ELSE 0 END) AS general_play_turnovers,",
    "    SUM(CASE WHEN stats.stat = 'unforcedTurnovers' THEN stats.value_number ELSE 0 END) AS unforced_turnovers,",
    "    SUM(CASE WHEN stats.stat = 'gain' THEN stats.value_number ELSE 0 END) AS gain,",
    "    SUM(CASE WHEN stats.stat = 'intercepts' THEN stats.value_number ELSE 0 END) AS intercepts,",
    "    SUM(CASE WHEN stats.stat = 'deflections' THEN stats.value_number ELSE 0 END) AS deflections,",
    "    SUM(CASE WHEN stats.stat = 'possessions' THEN stats.value_number ELSE 0 END) AS possessions",
    "  FROM team_period_stats AS stats",
    "  WHERE stats.stat IN ('goal1','goal2','goalAttempts','generalPlayTurnovers','unforcedTurnovers','gain','intercepts','deflections','possessions')",
    "  GROUP BY stats.squad_id, stats.match_id, stats.season, stats.round_number",
    ")",
    "SELECT squad_id, squad_name, season, round_number, match_id,",
    "  CASE",
    "    WHEN ?metric_key = 'teamFinishingEfficiency' THEN ROUND(CAST((goal1 + 2 * goal2) / NULLIF(goal_attempts, 0) AS numeric), 4)",
    "    WHEN ?metric_key = 'teamBallSecurityRate' THEN ROUND(CAST((general_play_turnovers + unforced_turnovers) / NULLIF(possessions, 0) AS numeric), 4)",
    "    WHEN ?metric_key = 'teamDisruption' THEN ROUND(CAST(gain + intercepts + deflections AS numeric), 4)",
    "    WHEN ?metric_key = 'teamPossessionControlBalance' THEN ROUND(CAST((gain + intercepts) - (general_play_turnovers + unforced_turnovers) AS numeric), 4)",
    "    ELSE NULL",
    "  END AS metric_value",
    "FROM team_base",
    "WHERE 1 = 1"
  )

  filters <- apply_stat_filters(query, list(metric_key = metric_key), seasons = seasons, team_id = team_id, round_number = round, table_alias = "team_base")
  rows <- query_rows(conn, filters$query, filters$params)
  rows[!is.na(rows$metric_value), , drop = FALSE]
}

summarize_analytics_rows <- function(rows, metric_key, entity = c("player", "team")) {
  entity <- match.arg(entity)
  if (!nrow(rows)) {
    return(rows)
  }

  id_col <- if (identical(entity, "player")) "player_id" else "squad_id"
  name_col <- if (identical(entity, "player")) "player_name" else "squad_name"
  group_ids <- interaction(rows[[id_col]], rows[[name_col]], drop = TRUE, lex.order = TRUE)

  combined <- lapply(split(seq_len(nrow(rows)), group_ids), function(indices) {
    part <- rows[indices, , drop = FALSE]
    total_value <- round(sum(part$metric_value, na.rm = TRUE), 4)
    average_value <- round(mean(part$metric_value, na.rm = TRUE), 4)
    if (identical(entity, "player")) {
      part$season <- suppressWarnings(as.integer(part$season))
      latest_index <- order(-part$season, part$squad_name, na.last = TRUE)[[1]]
      data.frame(
        player_id = part$player_id[[1]],
        player_name = part$player_name[[1]],
        squad_name = part$squad_name[[latest_index]],
        stat = metric_key,
        total_value = if (analytics_metric_supports_mode(metric_key, "total")) total_value else average_value,
        average_value = average_value,
        matches_played = length(unique(part$match_id)),
        stringsAsFactors = FALSE
      )
    } else {
      data.frame(
        squad_id = part$squad_id[[1]],
        squad_name = part$squad_name[[1]],
        stat = metric_key,
        total_value = if (analytics_metric_supports_mode(metric_key, "total")) total_value else average_value,
        average_value = average_value,
        matches_played = length(unique(part$match_id)),
        stringsAsFactors = FALSE
      )
    }
  })

  do.call(rbind, combined)
}

fetch_player_analytics_leader_rows <- function(conn, metric_key, seasons = NULL, team_id = NULL, round = NULL, search = "", metric = "average", ranking = "highest", limit = 12L) {
  rows <- player_analytics_match_rows(conn, metric_key, seasons = seasons, team_id = team_id, round = round, search = search)
  if (!nrow(rows)) {
    return(data.frame(
      player_id = integer(0), player_name = character(0), squad_name = character(0),
      stat = character(0), total_value = numeric(0), average_value = numeric(0),
      matches_played = integer(0), stringsAsFactors = FALSE
    ))
  }
  summarized <- summarize_analytics_rows(rows, metric_key, entity = "player")
  order_col <- if (identical(metric, "average")) summarized$average_value else summarized$total_value
  direction <- if (identical(ranking, "lowest")) {
    order(order_col, summarized$player_name, na.last = TRUE)
  } else {
    order(-order_col, summarized$player_name, na.last = TRUE)
  }
  summarized <- summarized[direction, , drop = FALSE]
  head(summarized, as.integer(limit))
}

fetch_team_analytics_leader_rows <- function(conn, metric_key, seasons = NULL, team_id = NULL, round = NULL, metric = "average", ranking = "highest", limit = 8L) {
  rows <- team_analytics_match_rows(conn, metric_key, seasons = seasons, team_id = team_id, round = round)
  if (!nrow(rows)) {
    return(data.frame(
      squad_id = integer(0), squad_name = character(0),
      stat = character(0), total_value = numeric(0), average_value = numeric(0),
      matches_played = integer(0), stringsAsFactors = FALSE
    ))
  }
  summarized <- summarize_analytics_rows(rows, metric_key, entity = "team")
  order_col <- if (identical(metric, "average")) summarized$average_value else summarized$total_value
  direction <- if (identical(ranking, "lowest")) {
    order(order_col, summarized$squad_name, na.last = TRUE)
  } else {
    order(-order_col, summarized$squad_name, na.last = TRUE)
  }
  summarized <- summarized[direction, , drop = FALSE]
  head(summarized, as.integer(limit))
}

fetch_competition_analytics_series_rows <- function(conn, metric_key, seasons = NULL, round = NULL, metric = "average") {
  rows <- team_analytics_match_rows(conn, metric_key, seasons = seasons, team_id = NULL, round = round)
  if (!nrow(rows)) {
    return(data.frame(
      season = integer(0), stat = character(0),
      total_value = numeric(0), average_value = numeric(0),
      matches_played = integer(0), stringsAsFactors = FALSE
    ))
  }
  seasons_vec <- sort(unique(rows$season))
  combined <- lapply(seasons_vec, function(s) {
    part <- rows[rows$season == s, , drop = FALSE]
    total_value <- round(sum(part$metric_value, na.rm = TRUE), 4)
    average_value <- round(mean(part$metric_value, na.rm = TRUE), 4)
    data.frame(
      season = s,
      stat = metric_key,
      total_value = if (analytics_metric_supports_mode(metric_key, "total")) total_value else average_value,
      average_value = average_value,
      matches_played = length(unique(part$match_id)),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, combined)
}

fetch_team_analytics_season_series_rows <- function(conn, metric_key, seasons = NULL, team_id = NULL, round = NULL, metric = "average", ranking = "highest", limit = 10L) {
  rows <- team_analytics_match_rows(conn, metric_key, seasons = seasons, team_id = team_id, round = round)
  if (!nrow(rows)) {
    return(data.frame(
      squad_id = integer(0), squad_name = character(0), season = integer(0),
      stat = character(0), total_value = numeric(0), average_value = numeric(0),
      matches_played = integer(0), stringsAsFactors = FALSE
    ))
  }

  # Determine top squads across all seasons
  all_summarized <- summarize_analytics_rows(rows, metric_key, entity = "team")
  order_col <- if (identical(metric, "average")) all_summarized$average_value else all_summarized$total_value
  direction <- if (identical(ranking, "lowest")) {
    order(order_col, all_summarized$squad_name, na.last = TRUE)
  } else {
    order(-order_col, all_summarized$squad_name, na.last = TRUE)
  }
  all_summarized <- all_summarized[direction, , drop = FALSE]
  if (is.null(team_id)) {
    top_ids <- head(all_summarized$squad_id, as.integer(limit))
    rows <- rows[rows$squad_id %in% top_ids, , drop = FALSE]
  }

  seasons_vec <- sort(unique(rows$season))
  squad_ids <- unique(rows$squad_id)
  combined <- lapply(squad_ids, function(sid) {
    squad_rows <- rows[rows$squad_id == sid, , drop = FALSE]
    lapply(seasons_vec, function(s) {
      part <- squad_rows[squad_rows$season == s, , drop = FALSE]
      if (!nrow(part)) return(NULL)
      total_value <- round(sum(part$metric_value, na.rm = TRUE), 4)
      average_value <- round(mean(part$metric_value, na.rm = TRUE), 4)
      data.frame(
        squad_id = sid,
        squad_name = part$squad_name[[1]],
        season = s,
        stat = metric_key,
        total_value = if (analytics_metric_supports_mode(metric_key, "total")) total_value else average_value,
        average_value = average_value,
        matches_played = length(unique(part$match_id)),
        stringsAsFactors = FALSE
      )
    })
  })
  result <- do.call(rbind, Filter(Negate(is.null), unlist(combined, recursive = FALSE)))
  series_order_col <- if (identical(metric, "average")) result$average_value else result$total_value
  if (identical(ranking, "lowest")) {
    result[order(result$season, series_order_col, result$squad_name, na.last = TRUE), , drop = FALSE]
  } else {
    result[order(result$season, -series_order_col, result$squad_name, na.last = TRUE), , drop = FALSE]
  }
}

fetch_player_analytics_season_series_rows <- function(conn, metric_key, seasons = NULL, team_id = NULL, round = NULL, search = "", metric = "average", ranking = "highest", limit = 10L) {
  rows <- player_analytics_match_rows(conn, metric_key, seasons = seasons, team_id = team_id, round = round, search = search)
  if (!nrow(rows)) {
    return(data.frame(
      player_id = integer(0), player_name = character(0), squad_name = character(0),
      season = integer(0), stat = character(0), total_value = numeric(0),
      average_value = numeric(0), matches_played = integer(0), stringsAsFactors = FALSE
    ))
  }

  # Determine top players across all seasons for ranking/limiting
  all_summarized <- summarize_analytics_rows(rows, metric_key, entity = "player")
  order_col <- if (identical(metric, "average")) all_summarized$average_value else all_summarized$total_value
  direction <- if (identical(ranking, "lowest")) {
    order(order_col, all_summarized$player_name, na.last = TRUE)
  } else {
    order(-order_col, all_summarized$player_name, na.last = TRUE)
  }
  all_summarized <- all_summarized[direction, , drop = FALSE]
  top_ids <- head(all_summarized$player_id, as.integer(limit))
  rows <- rows[rows$player_id %in% top_ids, , drop = FALSE]

  seasons_vec <- sort(unique(rows$season))
  player_ids <- unique(rows$player_id)
  combined <- lapply(player_ids, function(pid) {
    player_rows <- rows[rows$player_id == pid, , drop = FALSE]
    lapply(seasons_vec, function(s) {
      part <- player_rows[player_rows$season == s, , drop = FALSE]
      if (!nrow(part)) return(NULL)
      total_value <- round(sum(part$metric_value, na.rm = TRUE), 4)
      average_value <- round(mean(part$metric_value, na.rm = TRUE), 4)
      data.frame(
        player_id = pid,
        player_name = part$player_name[[1]],
        squad_name = max(part$squad_name),
        season = s,
        stat = metric_key,
        total_value = if (analytics_metric_supports_mode(metric_key, "total")) total_value else average_value,
        average_value = average_value,
        matches_played = length(unique(part$match_id)),
        stringsAsFactors = FALSE
      )
    })
  })
  result <- do.call(rbind, Filter(Negate(is.null), unlist(combined, recursive = FALSE)))
  result$season <- suppressWarnings(as.integer(result$season))
  series_order_col <- if (identical(metric, "average")) result$average_value else result$total_value
  if (identical(ranking, "lowest")) {
    result[order(result$season, series_order_col, result$player_name, na.last = TRUE), , drop = FALSE]
  } else {
    result[order(result$season, -series_order_col, result$player_name, na.last = TRUE), , drop = FALSE]
  }
}
