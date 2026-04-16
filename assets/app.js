const config = window.NETBALL_STATS_CONFIG || {};
const API_BASE_URL = (config.apiBaseUrl || "/api").replace(/\/$/, "");
const MATCHES_LIMIT = 12;
const LEADERS_LIMIT = 10;
const CHART_RANK_LIMIT = 10;
const DEFAULT_CHART_PALETTE = [
  "#f0c67e",
  "#79d8d0",
  "#ff9e9e",
  "#f4a0d8",
  "#d1c36b",
  "#8ac6ff"
];
const {
  clearChart,
  formatNumber,
  renderHorizontalBarChart,
  renderTrendChart,
  renderSeasonColumnChart
} = window.NetballCharts;
const {
  buildUrl,
  fetchJson,
  formatDate,
  formatStatLabel = (stat) => stat,
  getThemePalette = () => [...DEFAULT_CHART_PALETTE],
  getCheckedValues = () => [],
  clearEmptyTableState = () => {},
  playerProfileUrl = (playerId) => `/player/${encodeURIComponent(playerId)}/`,
  renderEmptyTableRow = () => {},
  renderSeasonCheckboxes = () => {},
  setCheckedValues = () => {},
  showElementLoadingStatus = () => {},
  showElementStatus = () => {},
  syncResponsiveTable = () => {}
} = window.NetballStatsUI || {};
const {
  applyMetaConfig = () => {},
  bucketCount = () => "unknown",
  trackEvent = () => {}
} = window.NetballStatsTelemetry || {};

const state = {
  meta: null,
  filters: {
    seasons: [],
    teamId: "",
    round: "",
    teamStat: "points",
    playerStat: "points",
    statMode: "total",
    rankingMode: "highest",
    archiveMode: "aggregate",
    playerSearch: ""
  },
  views: {
    "competition-season": "table",
    "team-leaders": "table",
    "player-leaders": "table"
  },
  results: {
    teamLeaderRows: [],
    playerLeaderRows: []
  },
  deferredPanels: {
    queryKey: "",
    competition: { status: "idle", data: [], error: "" },
    team: { status: "idle", data: [], error: "" },
    player: { status: "idle", data: [], error: "" }
  }
};

const ARCHIVE_LOADING_MESSAGES = [
  "Loading match log…",
  "Loading leaderboards…",
  "Loading season context…"
];
const ARCHIVE_STARTUP_MESSAGES = [
  "Waking the stats service…",
  "Starting the archive…"
];

const elements = {
  statusBanner: document.getElementById("status-banner"),
  filtersForm: document.getElementById("filters-form"),
  seasonChoices: document.getElementById("season-choices"),
  activeFilterSummary: document.getElementById("active-filter-summary"),
  teamId: document.getElementById("team-id"),
  round: document.getElementById("round"),
  teamStat: document.getElementById("team-stat"),
  playerStat: document.getElementById("player-stat"),
  archiveMode: document.getElementById("archive-mode"),
  archiveModeHint: document.getElementById("archive-mode-hint"),
  archiveModeButtons: document.querySelectorAll("[data-archive-mode]"),
  archiveAdvanced: document.getElementById("archive-advanced"),
  statMode: document.getElementById("stat-mode"),
  rankingMode: document.getElementById("ranking-mode"),
  rankingButtons: document.querySelectorAll("[data-ranking-mode]"),
  playerSearch: document.getElementById("player-search"),
  resetFilters: document.getElementById("reset-filters"),
  heroTotalGoals: document.getElementById("hero-total-goals"),
  heroRefreshNote: document.getElementById("hero-refresh-note"),
  summaryMatches: document.getElementById("summary-matches"),
  summaryTeams: document.getElementById("summary-teams"),
  summaryPlayers: document.getElementById("summary-players"),
  summaryGoals: document.getElementById("summary-goals"),
  summaryRefreshed: document.getElementById("summary-refreshed"),
  editorialLeadHeadline: document.getElementById("editorial-lead-headline"),
  editorialLeadCopy: document.getElementById("editorial-lead-copy"),
  editorialLeadNote: document.getElementById("editorial-lead-note"),
  editorialLeadFactLabel: document.getElementById("editorial-lead-fact-label"),
  editorialLeadFactValue: document.getElementById("editorial-lead-fact-value"),
  editorialLeadFactCopy: document.getElementById("editorial-lead-fact-copy"),
  editorialLeadSecondaryLabel: document.getElementById("editorial-lead-secondary-label"),
  editorialLeadSecondaryValue: document.getElementById("editorial-lead-secondary-value"),
  editorialLeadSecondaryCopy: document.getElementById("editorial-lead-secondary-copy"),
  archiveContextNote: document.getElementById("archive-context-note"),
  matchesTableBody: document.querySelector("#matches-table tbody"),
  competitionSeasonBody: document.querySelector("#competition-season-table tbody"),
  teamLeadersBody: document.querySelector("#team-leaders-table tbody"),
  playerLeadersBody: document.querySelector("#player-leaders-table tbody"),
  competitionSeasonChart: document.getElementById("competition-season-chart"),
  competitionSeasonSummary: document.getElementById("competition-season-summary"),
  competitionSeasonChartTitle: document.getElementById("competition-season-chart-title"),
  teamLeadersChart: document.getElementById("team-leaders-chart"),
  teamTrendChart: document.getElementById("team-trend-chart"),
  playerLeadersChart: document.getElementById("player-leaders-chart"),
  playerTrendChart: document.getElementById("player-trend-chart"),
  competitionSeasonPanel: document.getElementById("competition-season-panel"),
  playerTrendCard: document.getElementById("player-trend-card"),
  teamTrendCard: document.getElementById("team-trend-card"),
  playerTrendTitle: document.getElementById("player-trend-title"),
  teamTrendTitle: document.getElementById("team-trend-title"),
  playerPanelTitle: document.getElementById("player-panel-title"),
  teamPanelTitle: document.getElementById("team-panel-title"),
  playerPanelSummary: document.getElementById("player-panel-summary"),
  teamPanelSummary: document.getElementById("team-panel-summary"),
  playerLeadersHead: document.getElementById("player-leaders-head"),
  teamLeadersHead: document.getElementById("team-leaders-head"),
  teamLeadersChartTitle: document.getElementById("team-leaders-chart-title"),
  playerLeadersChartTitle: document.getElementById("player-leaders-chart-title"),
  competitionValueHeading: document.getElementById("competition-value-heading"),
  teamValueHeading: document.getElementById("team-value-heading"),
  playerValueHeading: document.getElementById("player-value-heading"),
  panelViewButtons: document.querySelectorAll("[data-panel][data-view-mode]"),
  seasonActionButtons: document.querySelectorAll("[data-season-action]"),
  scoreflowTeaserCards: document.getElementById("scoreflow-teaser-cards")
};


function isLocalApiConfigured() {
  try {
    const apiUrl = new URL(API_BASE_URL, window.location.href);
    return apiUrl.hostname === "localhost" || apiUrl.hostname === "127.0.0.1";
  } catch {
    return API_BASE_URL.startsWith("http://localhost") || API_BASE_URL.startsWith("http://127.0.0.1");
  }
}

function showStatus(message, tone = "neutral", options = {}) {
  showElementStatus(elements.statusBanner, message, tone, options);
}

function showLoadingStatus(messages, kicker) {
  showElementLoadingStatus(elements.statusBanner, messages, kicker);
}

async function fetchOptionalJson(path, params = {}) {
  try {
    return await fetchJson(path, params);
  } catch (error) {
    return {
      data: [],
      error: error.message || ""
    };
  }
}

function clearTable(tableBody, message) {
  renderEmptyTableRow(tableBody, message);
}

function createCell(text, className) {
  const cell = document.createElement("td");
  if (className) {
    cell.className = className;
  }
  cell.textContent = text;
  return cell;
}

function createLinkCell(href, text, className) {
  const cell = document.createElement("td");
  if (className) {
    cell.className = className;
  }

  const link = document.createElement("a");
  link.href = href;
  link.className = "table-link";
  link.textContent = text;
  cell.appendChild(link);
  return cell;
}

function renderArchiveContextNote() {
  if (!elements.archiveContextNote) return;
  const scope = describeSeasonScope();
  elements.archiveContextNote.textContent = isRecordMode()
    ? `Use the archive to surface the sharpest one-game performances in ${scope}, then open the dossier for full career context.`
    : `Use the archive to scan the strongest totals in ${scope}, then open the dossier for season-by-season context.`;
}

function renderEditorialLead(payload) {
  if (!elements.editorialLeadHeadline || !elements.editorialLeadCopy || !elements.editorialLeadNote) {
    return;
  }

  if (!payload || payload.error) {
    elements.editorialLeadHeadline.textContent = "The archive is ready for a fresh read.";
    elements.editorialLeadCopy.textContent = "Start with the latest completed round, then use the filters below to chase the player, team, or stat thread you care about.";
    elements.editorialLeadNote.textContent = "Open the round recap for the newest scorelines, or stay here and cut a custom slice of the archive.";
    elements.editorialLeadFactLabel.textContent = "Archive route";
    elements.editorialLeadFactValue.textContent = "Round recap";
    elements.editorialLeadFactCopy.textContent = "The latest completed round is the quickest way into the live archive.";
    elements.editorialLeadSecondaryLabel.textContent = "Next move";
    elements.editorialLeadSecondaryValue.textContent = "Choose the slice";
    elements.editorialLeadSecondaryCopy.textContent = "Use seasons and stat selectors first, then tighten the frame only if you need it.";
    return;
  }

  const summary = payload.summary || {};
  const leadFact = Array.isArray(payload.notable_facts) && payload.notable_facts.length ? payload.notable_facts[0] : null;
  const secondFact = Array.isArray(payload.notable_facts) && payload.notable_facts.length > 1 ? payload.notable_facts[1] : null;
  const roundName = payload.round_label || "Latest completed round";
  const roundLabel = payload.season ? `${roundName}, ${payload.season}` : roundName;

  elements.editorialLeadHeadline.textContent = `${roundLabel} is now on the shelf.`;
  elements.editorialLeadCopy.textContent = leadFact?.detail
    || `${formatNumber(summary.total_matches)} matches and ${formatNumber(summary.total_goals)} points are now logged in the latest completed round.`;
  elements.editorialLeadNote.textContent = secondFact?.detail
    || "Use the recap for the full slate, then come back here to compare names, trace patterns, or narrow the archive.";
  elements.editorialLeadFactLabel.textContent = leadFact?.title || "Lead note";
  elements.editorialLeadFactValue.textContent = leadFact?.value || `${formatNumber(summary.total_goals)} points`;
  elements.editorialLeadFactCopy.textContent = leadFact?.detail || "The archive has logged the latest round totals.";
  elements.editorialLeadSecondaryLabel.textContent = "Round frame";
  elements.editorialLeadSecondaryValue.textContent = Number.isFinite(Number(summary.total_matches))
    ? `${formatNumber(summary.total_matches)} matches`
    : "--";
  elements.editorialLeadSecondaryCopy.textContent = summary.biggest_margin === null || summary.biggest_margin === undefined
    ? "Biggest margin unavailable."
    : `Biggest margin ${formatNumber(summary.biggest_margin)}.`;
}

function createPlayerLinkCell(playerId, text) {
  const cell = document.createElement("td");
  const link = document.createElement("a");
  link.href = playerProfileUrl(playerId);
  link.className = "table-link table-link--dossier";

  const label = document.createElement("span");
  label.textContent = text;

  const meta = document.createElement("span");
  meta.className = "table-link__meta";
  meta.textContent = "Open dossier";

  link.append(label, meta);
  cell.appendChild(link);
  return cell;
}

function createTeamCell(name, colour) {
  const cell = document.createElement("td");
  const swatch = document.createElement("span");
  swatch.className = "team-swatch";
  swatch.setAttribute("aria-hidden", "true");
  swatch.style.setProperty("--swatch-color", colour || "var(--muted)");
  cell.appendChild(swatch);
  cell.appendChild(document.createTextNode(name));
  return cell;
}

function createMatchResultCell(match) {
  const cell = document.createElement("td");
  const homeScore = Number(match.home_score);
  const awayScore = Number(match.away_score);
  const homeWon = homeScore > awayScore;
  const awayWon = awayScore > homeScore;

  const homeSpan = document.createElement("span");
  homeSpan.textContent = `${match.home_squad_name} ${formatNumber(homeScore)}`;
  homeSpan.className = homeWon ? "result-winner" : "result-loser";

  const sep = document.createTextNode(" – ");

  const awaySpan = document.createElement("span");
  awaySpan.textContent = `${formatNumber(awayScore)} ${match.away_squad_name}`;
  awaySpan.className = awayWon ? "result-winner" : "result-loser";

  cell.append(homeSpan, sep, awaySpan);
  return cell;
}

function populateSelect(select, options, placeholder) {
  const previousValue = select.value;
  select.replaceChildren();

  const placeholderOption = document.createElement("option");
  placeholderOption.value = "";
  placeholderOption.textContent = placeholder;
  select.appendChild(placeholderOption);

  options.forEach((option) => {
    const element = document.createElement("option");
    element.value = option.value;
    element.textContent = option.label;
    select.appendChild(element);
  });

  if ([...select.options].some((option) => option.value === previousValue)) {
    select.value = previousValue;
  }
}

function setSelectedSeasons(values) {
  setCheckedValues(elements.seasonChoices, values);
}

function getSelectedSeasons() {
  return getCheckedValues(elements.seasonChoices)
    .sort((left, right) => Number(right) - Number(left));
}

function renderSeasonChoices(seasons) {
  renderSeasonCheckboxes(elements.seasonChoices, seasons, { inputName: "season-choice" });
}

function seasonSummaryLabel(seasons) {
  if (!state.meta || !state.meta.seasons.length) {
    return "No seasons available";
  }
  if (!seasons.length) {
    return "All seasons selected";
  }
  if (seasons.length === 1) {
    return `Season ${seasons[0]}`;
  }
  return `${seasons.length} seasons selected`;
}

function describeSeasonScope() {
  if (!state.meta || !state.meta.seasons.length) {
    return "the available seasons";
  }
  if (!state.filters.seasons.length) {
    return "all seasons";
  }
  if (state.filters.seasons.length === 1) {
    return `season ${state.filters.seasons[0]}`;
  }
  return `the ${state.filters.seasons.length} selected seasons`;
}

function teamLabel(teamId) {
  if (!teamId || !state.meta) {
    return "All teams";
  }
  const selectedTeam = state.meta.teams.find((team) => `${team.squad_id}` === `${teamId}`);
  return selectedTeam ? selectedTeam.squad_name : "All teams";
}

function selectedStatLabel(selectElement, statKey) {
  const selectedOptionLabel = selectElement?.selectedOptions?.[0]?.textContent?.trim();
  if (selectedOptionLabel) {
    return selectedOptionLabel;
  }
  return formatStatLabel(statKey || "stat");
}

function currentTeamStatLabel() {
  return selectedStatLabel(elements.teamStat, state.filters.teamStat);
}

function currentPlayerStatLabel() {
  return selectedStatLabel(elements.playerStat, state.filters.playerStat);
}

function isAverageMetric() {
  return state.filters.statMode === "average";
}

function isRecordMode() {
  return state.filters.archiveMode === "records";
}

function statModeLabel() {
  return isAverageMetric() ? "Avg/game" : "Total";
}

function statModeDescriptor() {
  return isAverageMetric() ? "average per game" : "total";
}

function rankingModeLabel() {
  return state.filters.rankingMode === "lowest" ? "Lowest" : "Highest";
}

function rankingModeDescriptor() {
  return state.filters.rankingMode === "lowest" ? "Lowest first" : "Highest first";
}

function archiveModeLabel() {
  return isRecordMode() ? "Single-game records" : "Archive totals";
}

function setRankingMode(nextMode = "highest") {
  const normalized = nextMode === "lowest" ? "lowest" : "highest";
  if (elements.rankingMode) {
    elements.rankingMode.value = normalized;
  }

  elements.rankingButtons.forEach((button) => {
    const active = button.dataset.rankingMode === normalized;
    button.classList.toggle("is-active", active);
    button.classList.toggle("button--ghost", !active);
    button.setAttribute("aria-pressed", `${active}`);
  });
}

function setArchiveMode(nextMode = "aggregate") {
  const normalized = nextMode === "records" ? "records" : "aggregate";
  if (elements.archiveMode) {
    elements.archiveMode.value = normalized;
  }

  elements.archiveModeButtons.forEach((button) => {
    const active = button.dataset.archiveMode === normalized;
    button.classList.toggle("is-active", active);
    button.classList.toggle("button--ghost", !active);
    button.setAttribute("aria-pressed", `${active}`);
  });
}

function replaceTableHead(tableHead, labels) {
  if (!tableHead) return;
  const row = document.createElement("tr");
  labels.forEach((label) => {
    const config = typeof label === "string" ? { text: label } : label;
    const th = document.createElement("th");
    th.scope = "col";
    if (config.id) {
      th.id = config.id;
    }
    th.textContent = config.text;
    row.appendChild(th);
  });
  tableHead.replaceChildren(row);
}

function updateArchiveModePresentation() {
  const recordMode = isRecordMode();

  if (elements.statMode) {
    elements.statMode.disabled = recordMode;
    elements.statMode.setAttribute("aria-disabled", `${recordMode}`);
  }

  if (elements.archiveModeHint) {
    elements.archiveModeHint.textContent = recordMode
      ? "Single-game highs or lows for the player and team sections."
      : "Switch player and team sections between totals and single-game records.";
  }

  if (elements.competitionSeasonPanel) {
    elements.competitionSeasonPanel.hidden = recordMode;
  }
  if (elements.playerTrendCard) {
    elements.playerTrendCard.hidden = recordMode;
  }
  if (elements.teamTrendCard) {
    elements.teamTrendCard.hidden = recordMode;
  }

  if (elements.playerPanelTitle) {
    elements.playerPanelTitle.textContent = recordMode ? "Player records" : "Player leaderboard";
  }
  if (elements.teamPanelTitle) {
    elements.teamPanelTitle.textContent = recordMode ? "Team records" : "Team leaderboard";
  }
  if (elements.playerPanelSummary) {
    const playerStatLabel = currentPlayerStatLabel();
    elements.playerPanelSummary.textContent = recordMode
      ? `Single-game player records for ${playerStatLabel}.`
      : `Top player lines for ${playerStatLabel} across the selected seasons.`;
  }
  if (elements.teamPanelSummary) {
    const teamStatLabel = currentTeamStatLabel();
    elements.teamPanelSummary.textContent = recordMode
      ? `Single-game team records for ${teamStatLabel}.`
      : `Team view of ${teamStatLabel} across seasons.`;
  }
  if (elements.playerTrendTitle) {
    elements.playerTrendTitle.textContent = recordMode
      ? "No season trend in record mode"
      : `Season trend for top players in ${currentPlayerStatLabel()}`;
  }
  if (elements.teamTrendTitle) {
    elements.teamTrendTitle.textContent = recordMode
      ? "No season trend in record mode"
      : `Season trend for top clubs in ${currentTeamStatLabel()}`;
  }
  if (elements.competitionSeasonSummary) {
    elements.competitionSeasonSummary.textContent = `Season context for ${currentTeamStatLabel()}.`;
  }
  if (elements.competitionSeasonChartTitle) {
    elements.competitionSeasonChartTitle.textContent = `Competition trend by season for ${currentTeamStatLabel()}`;
  }

  replaceTableHead(
    elements.playerLeadersHead,
    recordMode
      ? ["Rank", "Player", "Team", "Opponent", "Season", "Round", "Stat total", "Local start"]
      : ["Rank", "Player", "Team", "Stat", { text: statModeLabel(), id: "player-value-heading" }, "Matches"]
  );
  replaceTableHead(
    elements.teamLeadersHead,
    recordMode
      ? ["Rank", "Team", "Opponent", "Season", "Round", "Stat total", "Local start"]
      : ["Rank", "Team", "Stat", { text: statModeLabel(), id: "team-value-heading" }, "Matches"]
  );
}

function statValue(row) {
  if (row && row.value !== undefined && row.value !== null && row.value !== "") {
    return row.value;
  }
  if (isRecordMode()) {
    return row?.total_value;
  }
  return isAverageMetric() ? row?.average_value : row?.total_value;
}

function updateValueHeadings() {
  updateArchiveModePresentation();
  if (isRecordMode()) {
    syncResponsiveTable(elements.playerLeadersBody.closest("table"));
    syncResponsiveTable(elements.teamLeadersBody.closest("table"));
    return;
  }

  const label = statModeLabel();
  const competitionValueHeading = document.getElementById("competition-value-heading");
  const teamValueHeading = document.getElementById("team-value-heading");
  const playerValueHeading = document.getElementById("player-value-heading");
  if (competitionValueHeading) {
    competitionValueHeading.textContent = label;
  }
  if (teamValueHeading) {
    teamValueHeading.textContent = label;
  }
  if (playerValueHeading) {
    playerValueHeading.textContent = label;
  }
  [
    elements.competitionSeasonBody,
    elements.teamLeadersBody,
    elements.playerLeadersBody
  ].forEach((tableBody) => syncResponsiveTable(tableBody.closest("table")));
}

function syncFiltersFromForm() {
  state.filters = {
    seasons: getSelectedSeasons(),
    teamId: elements.teamId.value,
    round: elements.round.value,
    teamStat: elements.teamStat.value,
    playerStat: elements.playerStat.value,
    statMode: elements.statMode.value,
    rankingMode: elements.rankingMode.value || "highest",
    archiveMode: elements.archiveMode.value || "aggregate",
    playerSearch: elements.playerSearch.value.trim()
  };
}

function archiveTelemetryProperties() {
  syncFiltersFromForm();
  return {
    season_count_bucket: bucketCount(state.filters.seasons.length, [0, 1, 2, 3, 5, 8]),
    has_team_filter: Boolean(state.filters.teamId),
    has_round_filter: Boolean(state.filters.round),
    has_player_search: Boolean(state.filters.playerSearch),
    stat_mode: state.filters.statMode || "unknown",
    ranking_mode: state.filters.rankingMode || "unknown",
    archive_mode: state.filters.archiveMode || "unknown",
    team_stat: state.filters.teamStat || "unknown",
    player_stat: state.filters.playerStat || "unknown"
  };
}

function renderFilterSummary() {
  syncFiltersFromForm();
  const segments = [
    seasonSummaryLabel(state.filters.seasons),
    teamLabel(state.filters.teamId),
    state.filters.round ? `Round ${state.filters.round}` : "All rounds",
    archiveModeLabel(),
    isRecordMode() ? "single-game totals" : statModeDescriptor(),
    rankingModeDescriptor(),
    `Team ${currentTeamStatLabel()}`,
    `Player ${currentPlayerStatLabel()}`
  ];

  if (state.filters.playerSearch) {
    segments.push(`Player search: ${state.filters.playerSearch}`);
  }

  elements.activeFilterSummary.textContent = segments.join(" • ");
  if (elements.archiveAdvanced) {
    const hasTighterSlice = Boolean(
      state.filters.teamId
      || state.filters.round
      || state.filters.playerSearch
      || state.filters.rankingMode !== "highest"
    );
    elements.archiveAdvanced.open = hasTighterSlice;
  }
  if (elements.teamLeadersChartTitle) {
    elements.teamLeadersChartTitle.textContent = isRecordMode()
      ? `${rankingModeLabel()} team records by ${currentTeamStatLabel()}`
      : `${rankingModeLabel()} clubs by ${currentTeamStatLabel()}`;
  }
  if (elements.playerLeadersChartTitle) {
    elements.playerLeadersChartTitle.textContent = isRecordMode()
      ? `${rankingModeLabel()} player records by ${currentPlayerStatLabel()}`
      : `${rankingModeLabel()} players by ${currentPlayerStatLabel()}`;
  }
  updateValueHeadings();
  renderArchiveContextNote();
}

function applyMeta(meta) {
  state.meta = meta;
  renderSeasonChoices(meta.seasons || []);

  populateSelect(
    elements.teamId,
    meta.teams.map((team) => ({ value: `${team.squad_id}`, label: team.squad_name })),
    "All teams"
  );
  populateSelect(
    elements.teamStat,
    meta.team_stats.map((stat) => ({ value: stat, label: formatStatLabel(stat) })),
    "Choose a team stat"
  );
  populateSelect(
    elements.playerStat,
    meta.player_stats.map((stat) => ({ value: stat, label: formatStatLabel(stat) })),
    "Choose a player stat"
  );

  const defaultSeason = meta.default_season ? `${meta.default_season}` : "";
  setSelectedSeasons(defaultSeason ? [defaultSeason] : []);
  elements.teamId.value = "";
  elements.round.value = "";
  elements.playerSearch.value = "";
  elements.statMode.value = "total";
  setRankingMode("highest");
  setArchiveMode("aggregate");
  elements.teamStat.value = meta.team_stats.includes("points") ? "points" : meta.team_stats[0] || "";
  elements.playerStat.value = meta.player_stats.includes("points") ? "points" : meta.player_stats[0] || "";
  renderFilterSummary();
  setPanelView("competition-season", state.views["competition-season"]);
  setPanelView("team-leaders", state.views["team-leaders"]);
  setPanelView("player-leaders", state.views["player-leaders"]);
}

function renderSummary(summary) {
  if (elements.heroTotalGoals) elements.heroTotalGoals.textContent = formatNumber(summary.total_goals);
  if (elements.heroRefreshNote) elements.heroRefreshNote.textContent = "Updated " + formatDate(summary.refreshed_at);
  elements.summaryMatches.textContent = formatNumber(summary.total_matches);
  if (elements.summaryTeams) elements.summaryTeams.textContent = formatNumber(summary.total_teams);
  elements.summaryPlayers.textContent = formatNumber(summary.total_players);
  if (elements.summaryGoals) elements.summaryGoals.textContent = formatNumber(summary.total_goals);
  elements.summaryRefreshed.textContent = formatDate(summary.refreshed_at);
}

function renderMatches(matches) {
  if (!matches.length) {
    clearTable(elements.matchesTableBody, "No matches for these filters.");
    return;
  }

  clearEmptyTableState(elements.matchesTableBody);
  const fragment = document.createDocumentFragment();
  matches.forEach((match) => {
    const row = document.createElement("tr");
    row.append(
      createCell(`${match.season} ${match.competition_phase}`),
      createCell(`R${match.round_number} G${match.game_number}`),
      createMatchResultCell(match),
      createCell(match.venue_name || "-"),
      createCell(formatDate(match.local_start_time))
    );
    fragment.appendChild(row);
  });
  elements.matchesTableBody.replaceChildren(fragment);
  syncResponsiveTable(elements.matchesTableBody.closest("table"));
}

function renderTeamLeaders(rows) {
  if (!rows.length) {
    clearTable(elements.teamLeadersBody, "No results for these filters.");
    return;
  }

  clearEmptyTableState(elements.teamLeadersBody);
  const fragment = document.createDocumentFragment();
  rows.forEach((rowData, index) => {
    const colour = resolveTeamColour(rowData.squad_name, rowData.squad_colour, index);
    const row = document.createElement("tr");
    row.setAttribute("data-rank", index + 1);
    row.style.setProperty("--row-accent", colour);
    if (isRecordMode()) {
      row.append(
        createCell(`${index + 1}`),
        createTeamCell(rowData.squad_name, colour),
        createCell(rowData.opponent || "-"),
        createCell(`${rowData.season}`),
        createCell(`R${rowData.round_number}`),
        createCell(formatNumber(rowData.total_value)),
        createCell(formatDate(rowData.local_start_time))
      );
    } else {
      row.append(
        createCell(`${index + 1}`),
        createTeamCell(rowData.squad_name, colour),
        createCell(formatStatLabel(rowData.stat)),
        createCell(formatNumber(statValue(rowData))),
        createCell(formatNumber(rowData.matches_played))
      );
    }
    row.children[1].dataset.stackPrimary = "true";
    fragment.appendChild(row);
  });
  elements.teamLeadersBody.replaceChildren(fragment);
  syncResponsiveTable(elements.teamLeadersBody.closest("table"));
}

function renderPlayerLeaders(rows) {
  if (!rows.length) {
    clearTable(elements.playerLeadersBody, "No results for these filters.");
    return;
  }

  clearEmptyTableState(elements.playerLeadersBody);
  const fragment = document.createDocumentFragment();
  rows.forEach((rowData, index) => {
    const colour = resolvePlayerColour(rowData.player_name, rowData.squad_name, index);
    const row = document.createElement("tr");
    row.setAttribute("data-rank", index + 1);
    row.style.setProperty("--row-accent", colour);
    if (isRecordMode()) {
      row.append(
        createCell(`${index + 1}`),
        createPlayerLinkCell(rowData.player_id, rowData.player_name),
        createTeamCell(rowData.squad_name || "-", colour),
        createCell(rowData.opponent || "-"),
        createCell(`${rowData.season}`),
        createCell(`R${rowData.round_number}`),
        createCell(formatNumber(rowData.total_value)),
        createCell(formatDate(rowData.local_start_time))
      );
    } else {
      row.append(
        createCell(`${index + 1}`),
        createPlayerLinkCell(rowData.player_id, rowData.player_name),
        createTeamCell(rowData.squad_name || "-", colour),
        createCell(formatStatLabel(rowData.stat)),
        createCell(formatNumber(statValue(rowData))),
        createCell(formatNumber(rowData.matches_played))
      );
    }
    row.children[1].dataset.stackPrimary = "true";
    fragment.appendChild(row);
  });
  elements.playerLeadersBody.replaceChildren(fragment);
  syncResponsiveTable(elements.playerLeadersBody.closest("table"));
}

function renderCompetitionSeasonTable(rows, errorMessage) {
  if (errorMessage) {
    clearTable(elements.competitionSeasonBody, errorMessage);
    return;
  }

  if (!rows.length) {
    clearTable(elements.competitionSeasonBody, "No results for these filters.");
    return;
  }

  clearEmptyTableState(elements.competitionSeasonBody);
  const fragment = document.createDocumentFragment();
  rows.forEach((rowData) => {
    const row = document.createElement("tr");
    row.append(
      createCell(`${rowData.season}`),
      createCell(formatStatLabel(rowData.stat)),
      createCell(formatNumber(statValue(rowData))),
      createCell(formatNumber(rowData.matches_played))
    );
    fragment.appendChild(row);
  });
  elements.competitionSeasonBody.replaceChildren(fragment);
  syncResponsiveTable(elements.competitionSeasonBody.closest("table"));
}

function clearAllTables(message) {
  clearTable(elements.matchesTableBody, message);
  clearTable(elements.competitionSeasonBody, message);
  clearTable(elements.teamLeadersBody, message);
  clearTable(elements.playerLeadersBody, message);
}

function clearAllCharts(message) {
  clearChart(elements.competitionSeasonChart, message);
  clearChart(elements.teamLeadersChart, message);
  clearChart(elements.teamTrendChart, message);
  clearChart(elements.playerLeadersChart, message);
  clearChart(elements.playerTrendChart, message);
}

function createDeferredPanelState() {
  return {
    status: "idle",
    data: [],
    error: ""
  };
}

function resetDeferredPanels(queryKey = "") {
  state.deferredPanels = {
    queryKey,
    competition: createDeferredPanelState(),
    team: createDeferredPanelState(),
    player: createDeferredPanelState()
  };
}

function buildArchiveQueryKey() {
  return JSON.stringify({
    seasons: [...state.filters.seasons],
    teamId: state.filters.teamId,
    round: state.filters.round,
    teamStat: state.filters.teamStat,
    playerStat: state.filters.playerStat,
    statMode: state.filters.statMode,
    rankingMode: state.filters.rankingMode,
    archiveMode: state.filters.archiveMode,
    playerSearch: state.filters.playerSearch
  });
}

function normaliseColour(value) {
  if (!value || typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  if (/^#[0-9a-f]{6}$/i.test(trimmed)) {
    return trimmed;
  }
  if (/^[0-9a-f]{6}$/i.test(trimmed)) {
    return `#${trimmed}`;
  }
  if (/^#[0-9a-f]{3}$/i.test(trimmed)) {
    return trimmed;
  }
  return null;
}

function fallbackColour(index) {
  const palette = getThemePalette(DEFAULT_CHART_PALETTE);
  return palette[index % palette.length];
}

function teamMetaByName(name) {
  if (!state.meta || !Array.isArray(state.meta.teams)) {
    return null;
  }
  return state.meta.teams.find((team) => team.squad_name === name) || null;
}

function resolveTeamColour(name, explicitColour, index) {
  const fromRow = normaliseColour(explicitColour);
  if (fromRow) {
    return fromRow;
  }
  const team = teamMetaByName(name);
  const fromMeta = normaliseColour(team?.squad_colour);
  return fromMeta || fallbackColour(index);
}

function resolvePlayerColour(name, squadName, index) {
  const team = teamMetaByName(squadName);
  const fromTeam = normaliseColour(team?.squad_colour);
  return fromTeam || fallbackColour(index);
}

function setPanelView(panel, mode) {
  state.views[panel] = mode;

  document.querySelectorAll(`[data-panel-view="${panel}"]`).forEach((view) => {
    view.hidden = view.dataset.panelMode !== mode;
  });

  document.querySelectorAll(`[data-panel="${panel}"][data-view-mode]`).forEach((button) => {
    const active = button.dataset.viewMode === mode;
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-pressed", active ? "true" : "false");
  });

  if (panel === "competition-season" && mode === "chart") {
    if (isRecordMode()) {
      clearChart(
        elements.competitionSeasonChart,
        "Record mode focuses on single-match performances. Switch back to totals to see season context."
      );
      return;
    }

    if (!state.deferredPanels.queryKey) {
      clearChart(elements.competitionSeasonChart, "Loading season context…");
      return;
    }

    void fetchDeferredPanel("competition", runQuerySeq);
    return;
  }

  if (panel === "team-leaders" && mode === "chart") {
    renderTeamLeaderChart(state.results.teamLeaderRows);

    if (isRecordMode()) {
      clearChart(
        elements.teamTrendChart,
        "Record mode focuses on single-match performances. Switch back to totals to see season trends."
      );
      return;
    }

    if (!state.deferredPanels.queryKey) {
      clearChart(elements.teamTrendChart, "Loading team trend…");
      return;
    }

    void fetchDeferredPanel("team", runQuerySeq);
    return;
  }

  if (panel === "player-leaders" && mode === "chart") {
    renderPlayerLeaderChart(state.results.playerLeaderRows);

    if (isRecordMode()) {
      clearChart(
        elements.playerTrendChart,
        "Record mode focuses on single-match performances. Switch back to totals to see season trends."
      );
      return;
    }

    if (!state.deferredPanels.queryKey) {
      clearChart(elements.playerTrendChart, "Loading player trend…");
      return;
    }

    void fetchDeferredPanel("player", runQuerySeq);
  }
}

function renderCompetitionSeasonChart(rows, errorMessage) {
  if (errorMessage) {
    clearChart(elements.competitionSeasonChart, errorMessage);
    return;
  }

  renderSeasonColumnChart(elements.competitionSeasonChart, rows, {
    ariaLabel: `Competition ${statModeDescriptor()} chart by season for ${currentTeamStatLabel()}`,
    emptyMessage: "No results for these filters.",
    labelAccessor: (row) => row.season,
    valueAccessor: (row) => statValue(row),
    colourAccessor: (_row, index) => fallbackColour(index)
  });
}

function renderTeamLeaderChart(leaderRows) {
  const chartLeaderRows = leaderRows.slice(0, CHART_RANK_LIMIT);

  renderHorizontalBarChart(elements.teamLeadersChart, chartLeaderRows, {
    ariaLabel: isRecordMode()
      ? `${rankingModeLabel()} single-game team records chart for ${currentTeamStatLabel()}`
      : `${rankingModeLabel()} team leaderboard ${statModeDescriptor()} chart for ${currentTeamStatLabel()}`,
    emptyMessage: "No results for these filters.",
    labelAccessor: (row) => row.squad_name,
    valueAccessor: (row) => isRecordMode() ? row.total_value : statValue(row),
    colourAccessor: (row, index) => resolveTeamColour(row.squad_name, row.squad_colour, index)
  });
}

function renderTeamTrendChart(trendRows, errorMessage = "") {
  if (isRecordMode()) {
    clearChart(elements.teamTrendChart, "Record mode focuses on single-match performances. Switch back to totals to see season trends.");
    return;
  }

  if (errorMessage) {
    clearChart(elements.teamTrendChart, errorMessage);
    return;
  }

  renderTrendChart(elements.teamTrendChart, trendRows, {
    ariaLabel: `Team season ${statModeDescriptor()} chart for ${currentTeamStatLabel()}`,
    emptyMessage: "No results for these filters.",
    singleSeasonMessage: "Choose two or more seasons for a trend.",
    idAccessor: (row) => row.squad_id,
    labelAccessor: (row) => row.squad_name,
    valueAccessor: (row) => statValue(row),
    colourAccessor: (row, index) => resolveTeamColour(row.squad_name, row.squad_colour, index)
  });
}

function renderPlayerLeaderChart(leaderRows) {
  const chartLeaderRows = leaderRows.slice(0, CHART_RANK_LIMIT);

  renderHorizontalBarChart(elements.playerLeadersChart, chartLeaderRows, {
    ariaLabel: isRecordMode()
      ? `${rankingModeLabel()} single-game player records chart for ${currentPlayerStatLabel()}`
      : `${rankingModeLabel()} player leaderboard ${statModeDescriptor()} chart for ${currentPlayerStatLabel()}`,
    emptyMessage: "No results for these filters.",
    labelAccessor: (row) => row.player_name,
    valueAccessor: (row) => isRecordMode() ? row.total_value : statValue(row),
    colourAccessor: (row, index) => resolvePlayerColour(row.player_name, row.squad_name, index)
  });
}

function renderPlayerTrendChart(trendRows, errorMessage = "") {
  if (isRecordMode()) {
    clearChart(elements.playerTrendChart, "Record mode focuses on single-match performances. Switch back to totals to see season trends.");
    return;
  }

  if (errorMessage) {
    clearChart(elements.playerTrendChart, errorMessage);
    return;
  }

  renderTrendChart(elements.playerTrendChart, trendRows, {
    ariaLabel: `Player season ${statModeDescriptor()} chart for ${currentPlayerStatLabel()}`,
    emptyMessage: "No results for these filters.",
    singleSeasonMessage: "Choose two or more seasons for a trend.",
    idAccessor: (row) => row.player_id,
    labelAccessor: (row) => row.player_name,
    valueAccessor: (row) => statValue(row),
    colourAccessor: (row, index) => resolvePlayerColour(row.player_name, row.squad_name, index)
  });
}

function renderCompetitionLoadingState() {
  if (isRecordMode()) {
    const message = "Record mode focuses on single-match performances. Switch back to totals to see season context.";
    renderCompetitionSeasonTable([], message);
    clearChart(elements.competitionSeasonChart, message);
    return;
  }

  renderCompetitionSeasonTable([], "Loading season context…");
  clearChart(
    elements.competitionSeasonChart,
    state.views["competition-season"] === "chart" ? "Loading season context…" : "Switch to chart to see season context."
  );
}

function renderTrendLoadingStates() {
  if (isRecordMode()) {
    clearChart(elements.teamTrendChart, "Record mode focuses on single-match performances. Switch back to totals to see season trends.");
    clearChart(elements.playerTrendChart, "Record mode focuses on single-match performances. Switch back to totals to see season trends.");
    return;
  }

  clearChart(
    elements.teamTrendChart,
    state.views["team-leaders"] === "chart" ? "Loading team trend…" : "Switch to chart to load season trends."
  );
  clearChart(
    elements.playerTrendChart,
    state.views["player-leaders"] === "chart" ? "Loading player trend…" : "Switch to chart to load season trends."
  );
}

function competitionSeriesParams() {
  return {
    seasons: state.filters.seasons,
    round: state.filters.round,
    stat: state.filters.teamStat,
    metric: state.filters.statMode
  };
}

function teamSeriesParams(baseParams) {
  return {
    ...baseParams,
    stat: state.filters.teamStat,
    metric: state.filters.statMode,
    ranking: state.filters.rankingMode,
    limit: CHART_RANK_LIMIT
  };
}

function playerSeriesParams(baseParams) {
  return {
    ...baseParams,
    stat: state.filters.playerStat,
    search: state.filters.playerSearch,
    metric: state.filters.statMode,
    ranking: state.filters.rankingMode,
    limit: CHART_RANK_LIMIT
  };
}

function renderDeferredPanel(panel) {
  const payload = state.deferredPanels[panel];
  if (!payload) {
    return;
  }

  if (panel === "competition") {
    if (payload.status === "loading") {
      renderCompetitionLoadingState();
      return;
    }

    renderCompetitionSeasonTable(
      payload.data,
      payload.error ? "Season totals temporarily unavailable." : ""
    );
    renderCompetitionSeasonChart(
      payload.data,
      payload.error ? "Season chart temporarily unavailable." : ""
    );
    return;
  }

  if (panel === "team") {
    if (payload.status === "loading") {
      clearChart(elements.teamTrendChart, "Loading team trend…");
      return;
    }

    renderTeamTrendChart(
      payload.data,
      payload.error ? "Team trend temporarily unavailable." : ""
    );
    return;
  }

  if (panel === "player") {
    if (payload.status === "loading") {
      clearChart(elements.playerTrendChart, "Loading player trend…");
      return;
    }

    renderPlayerTrendChart(
      payload.data,
      payload.error ? "Player trend temporarily unavailable." : ""
    );
  }
}

async function fetchDeferredPanel(panel, seq) {
  if (isRecordMode() || !state.deferredPanels.queryKey) {
    return;
  }

  const current = state.deferredPanels[panel];
  if (!current || current.status === "loading" || current.status === "ready" || current.status === "error") {
    if (current) {
      renderDeferredPanel(panel);
    }
    return;
  }

  state.deferredPanels[panel] = {
    status: "loading",
    data: [],
    error: ""
  };
  renderDeferredPanel(panel);

  const queryKey = state.deferredPanels.queryKey;
  const baseParams = {
    seasons: state.filters.seasons,
    team_id: state.filters.teamId,
    round: state.filters.round
  };

  let payload = { data: [], error: "" };
  if (panel === "competition") {
    payload = await fetchOptionalJson("/competition-season-series", competitionSeriesParams());
  } else if (panel === "team") {
    payload = await fetchOptionalJson("/team-season-series", teamSeriesParams(baseParams));
  } else if (panel === "player") {
    payload = await fetchOptionalJson("/player-season-series", playerSeriesParams(baseParams));
  }

  if (seq !== runQuerySeq || state.deferredPanels.queryKey !== queryKey) {
    return;
  }

  state.deferredPanels[panel] = {
    status: payload.error ? "error" : "ready",
    data: payload.data || [],
    error: payload.error || ""
  };
  renderDeferredPanel(panel);
}

let runQuerySeq = 0;

async function runQueries() {
  const seq = ++runQuerySeq;
  const submitBtn = elements.filtersForm.querySelector('[type="submit"]');
  if (submitBtn) {
    submitBtn.disabled = true;
    submitBtn.setAttribute("aria-busy", "true");
  }

  syncFiltersFromForm();
  renderFilterSummary();
  showLoadingStatus(ARCHIVE_LOADING_MESSAGES, "Loading archive");
  state.results.teamLeaderRows = [];
  state.results.playerLeaderRows = [];
  resetDeferredPanels();
  const leaderboardFetchLimit = Math.max(LEADERS_LIMIT, CHART_RANK_LIMIT);

  const baseParams = {
    seasons: state.filters.seasons,
    team_id: state.filters.teamId,
    round: state.filters.round
  };

  try {
    const [
      summary,
      matchesPayload,
      teamLeadersPayload,
      playerLeadersPayload
    ] = await Promise.all([
      fetchJson("/summary", baseParams),
      fetchJson("/matches", { ...baseParams, limit: MATCHES_LIMIT }),
      fetchJson(
        isRecordMode() ? "/team-game-highs" : "/team-leaders",
        {
          ...baseParams,
          stat: state.filters.teamStat,
          ...(isRecordMode() ? {} : { metric: state.filters.statMode }),
          ranking: state.filters.rankingMode,
          limit: leaderboardFetchLimit
        }
      ),
      fetchJson(
        isRecordMode() ? "/player-game-highs" : "/player-leaders",
        {
          ...baseParams,
          stat: state.filters.playerStat,
          search: state.filters.playerSearch,
          ...(isRecordMode() ? {} : { metric: state.filters.statMode }),
          ranking: state.filters.rankingMode,
          limit: leaderboardFetchLimit
        }
      )
    ]);
    const teamLeaderRows = teamLeadersPayload.data || [];
    const playerLeaderRows = playerLeadersPayload.data || [];

    if (seq !== runQuerySeq) return;

    state.results.teamLeaderRows = teamLeaderRows;
    state.results.playerLeaderRows = playerLeaderRows;
    resetDeferredPanels(buildArchiveQueryKey());

    renderSummary(summary);
    renderMatches(matchesPayload.data || []);
    renderTeamLeaders(teamLeaderRows.slice(0, LEADERS_LIMIT));
    renderPlayerLeaders(playerLeaderRows.slice(0, LEADERS_LIMIT));
    renderCompetitionLoadingState();
    renderTeamLeaderChart(teamLeaderRows);
    renderPlayerLeaderChart(playerLeaderRows);
    renderTrendLoadingStates();
    setPanelView("competition-season", state.views["competition-season"]);
    setPanelView("team-leaders", state.views["team-leaders"]);
    setPanelView("player-leaders", state.views["player-leaders"]);
    showStatus("Archive ready.", "success", { kicker: "Ready", autoHideMs: 2200 });

    void loadScoreflowHomeCards(seq);

    if (!isRecordMode()) {
      void fetchDeferredPanel("competition", seq);
    }
  } catch (error) {
    if (seq !== runQuerySeq) return;
    showStatus(error.message || "Couldn't load the archive.", "error", { kicker: "Archive unavailable" });
    clearAllTables("Couldn't load the archive.");
    clearAllCharts("Couldn't load charts.");
  } finally {
    if (seq === runQuerySeq && submitBtn) {
      submitBtn.disabled = false;
      submitBtn.removeAttribute("aria-busy");
    }
  }
}

// ---------------------------------------------------------------------------
// Scoreflow teaser band — homepage editorial bridge to /scoreflow/
// ---------------------------------------------------------------------------

function scoreflowHomeParams() {
  return {
    seasons: state.filters.seasons,
    team_id: state.filters.teamId
  };
}

function buildScoreflowDeepLink(hrefQuery) {
  const url = new URL("/scoreflow/", window.location.href);
  const q = hrefQuery || {};
  const seasons = Array.isArray(q.seasons)
    ? q.seasons
    : (q.seasons == null || typeof q.seasons === "object" ? [] : [q.seasons]);
  if (seasons.length) {
    url.searchParams.set("seasons", seasons.join(","));
  }
  if (q.team_id != null && typeof q.team_id !== "object" && `${q.team_id}`.trim() !== "") {
    url.searchParams.set("team_id", q.team_id);
  }
  if (q.metric && q.metric !== "comeback_deficit_points") {
    url.searchParams.set("metric", q.metric);
  }
  if (q.scenario && q.scenario !== "all") {
    url.searchParams.set("scenario", q.scenario);
  }
  return url.toString();
}

function formatScoreflowCardValue(record, metric) {
  if (!record) return "—";
  switch (metric) {
    case "comeback_deficit_points": {
      const n = Number(record.comeback_deficit_points);
      return Number.isFinite(n) && n > 0 ? `${formatNumber(n)} pts` : "—";
    }
    case "trailing_share": {
      const n = Number(record.trailing_share);
      return Number.isFinite(n) ? `${(n * 100).toFixed(1)}%` : "—";
    }
    case "seconds_leading": {
      const n = Number(record.seconds_leading);
      return Number.isFinite(n) ? `${formatNumber(Math.floor(n / 60))} min` : "—";
    }
    default:
      return "—";
  }
}

function renderScoreflowTeaserCards(cards) {
  const container = elements.scoreflowTeaserCards;
  if (!container) return;

  if (!Array.isArray(cards) || !cards.length) {
    const empty = document.createElement("p");
    empty.className = "scoreflow-teaser__empty";
    empty.textContent = "Scoreflow records are available across the full archive — adjust the season filter or explore the dedicated page.";
    container.replaceChildren(empty);
    return;
  }

  const fragment = document.createDocumentFragment();
  cards.forEach((card) => {
    const record = card.record;
    const link = document.createElement("a");
    link.className = "scoreflow-teaser__card";
    link.href = buildScoreflowDeepLink(card.href_query);

    const labelEl = document.createElement("span");
    labelEl.className = "scoreflow-teaser__card-label";
    labelEl.textContent = card.label || card.slug || "Scoreflow";

    const valueEl = document.createElement("strong");
    valueEl.className = "scoreflow-teaser__card-value";
    valueEl.textContent = formatScoreflowCardValue(record, card.metric);

    const teamEl = document.createElement("span");
    teamEl.className = "scoreflow-teaser__card-team";
    teamEl.textContent = record?.squad_name || "—";

    const ctxParts = [];
    if (record?.opponent_name) ctxParts.push(`vs ${record.opponent_name}`);
    if (record?.season) ctxParts.push(String(record.season));
    if (record?.round_number != null) ctxParts.push(`Rd ${record.round_number}`);

    const ctxEl = document.createElement("span");
    ctxEl.className = "scoreflow-teaser__card-context";
    ctxEl.textContent = ctxParts.length ? ctxParts.join(" · ") : "Archive record";

    const arrowEl = document.createElement("span");
    arrowEl.className = "scoreflow-teaser__card-arrow";
    arrowEl.setAttribute("aria-hidden", "true");
    arrowEl.textContent = "→";

    link.append(labelEl, valueEl, teamEl, ctxEl, arrowEl);
    fragment.appendChild(link);
  });

  container.replaceChildren(fragment);
}

async function loadScoreflowHomeCards(seq) {
  if (!elements.scoreflowTeaserCards) return;
  try {
    const payload = await fetchOptionalJson("/scoreflow-featured-records", scoreflowHomeParams());
    if (seq !== runQuerySeq) return;
    renderScoreflowTeaserCards(payload.data || []);
  } catch {
    // Silent failure: teaser is supplementary — do not surface errors on the homepage.
    if (seq === runQuerySeq) renderScoreflowTeaserCards([]);
  }
}

async function initialise() {
  clearAllTables("Loading…");
  clearAllCharts("Loading…");
  renderEditorialLead(null);

  try {
    let meta;
    try {
      meta = await fetchJson("/meta");
    } catch (firstError) {
      // Retry once to handle cold-start delays (R/Plumber can take 20-30s to start).
      showLoadingStatus(ARCHIVE_STARTUP_MESSAGES, "Starting up");
      await new Promise((resolve) => window.setTimeout(resolve, 5000));
      meta = await fetchJson("/meta");
    }
    applyMeta(meta);
    applyMetaConfig(meta);
    const editorialLeadPromise = fetchOptionalJson("/round-summary")
      .then((payload) => renderEditorialLead(payload));
    await runQueries();
    await editorialLeadPromise;
  } catch (error) {
    const hint = isLocalApiConfigured()
      ? "Run the API before using the site locally."
      : "Stats unavailable. Try again shortly.";
    showStatus(hint, "error", { kicker: "Archive unavailable" });
    clearAllTables("Stats unavailable.");
    clearAllCharts("Stats unavailable.");
  }
}

elements.filtersForm.addEventListener("submit", (event) => {
  event.preventDefault();
  trackEvent("archive_filters_applied", archiveTelemetryProperties());
  runQueries();
});

elements.filtersForm.addEventListener("input", () => {
  renderFilterSummary();
});

elements.filtersForm.addEventListener("change", () => {
  renderFilterSummary();
});

elements.seasonActionButtons.forEach((button) => {
  button.addEventListener("click", () => {
    if (!state.meta) {
      return;
    }

    const action = button.dataset.seasonAction;
    if (action === "all") {
      setSelectedSeasons((state.meta.seasons || []).map((season) => `${season}`));
    } else if (action === "clear") {
      setSelectedSeasons([]);
    } else if (action === "latest") {
      setSelectedSeasons(state.meta.default_season ? [`${state.meta.default_season}`] : []);
    }

    renderFilterSummary();
  });
});

elements.resetFilters.addEventListener("click", () => {
  if (!state.meta) {
    return;
  }

  trackEvent("archive_filters_reset", archiveTelemetryProperties());
  applyMeta(state.meta);
  runQueries();
});

elements.rankingButtons.forEach((button) => {
  button.addEventListener("click", () => {
    setRankingMode(button.dataset.rankingMode);
    renderFilterSummary();
  });
});

elements.archiveModeButtons.forEach((button) => {
  button.addEventListener("click", () => {
    setArchiveMode(button.dataset.archiveMode);
    renderFilterSummary();
  });
});

elements.panelViewButtons.forEach((button) => {
  button.addEventListener("click", () => {
    setPanelView(button.dataset.panel, button.dataset.viewMode);
  });
});

setPanelView("competition-season", "table");
setPanelView("team-leaders", "table");
setPanelView("player-leaders", "table");

initialise();
