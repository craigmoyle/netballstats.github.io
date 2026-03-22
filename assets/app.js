const config = window.NETBALL_STATS_CONFIG || {};
const API_BASE_URL = (config.apiBaseUrl || "/api").replace(/\/$/, "");
const DEFAULT_TIMEOUT_MS = 30000;
const MATCHES_LIMIT = 12;
const LEADERS_LIMIT = 10;
const CHART_RANK_LIMIT = 10;
const CHART_PALETTE = [
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
  syncResponsiveTable = () => {}
} = window.NetballStatsUI || {};

const state = {
  meta: null,
  filters: {
    seasons: [],
    teamId: "",
    round: "",
    teamStat: "points",
    playerStat: "points",
    statMode: "total",
    playerSearch: ""
  },
  views: {
    "competition-season": "table",
    "team-leaders": "table",
    "player-leaders": "table"
  }
};

const elements = {
  statusBanner: document.getElementById("status-banner"),
  filtersForm: document.getElementById("filters-form"),
  seasonChoices: document.getElementById("season-choices"),
  activeFilterSummary: document.getElementById("active-filter-summary"),
  teamId: document.getElementById("team-id"),
  round: document.getElementById("round"),
  teamStat: document.getElementById("team-stat"),
  playerStat: document.getElementById("player-stat"),
  statMode: document.getElementById("stat-mode"),
  playerSearch: document.getElementById("player-search"),
  resetFilters: document.getElementById("reset-filters"),
  heroTotalGoals: document.getElementById("hero-total-goals"),
  heroRefreshNote: document.getElementById("hero-refresh-note"),
  summaryMatches: document.getElementById("summary-matches"),
  summaryTeams: document.getElementById("summary-teams"),
  summaryPlayers: document.getElementById("summary-players"),
  summaryGoals: document.getElementById("summary-goals"),
  summaryRefreshed: document.getElementById("summary-refreshed"),
  matchesTableBody: document.querySelector("#matches-table tbody"),
  competitionSeasonBody: document.querySelector("#competition-season-table tbody"),
  teamLeadersBody: document.querySelector("#team-leaders-table tbody"),
  playerLeadersBody: document.querySelector("#player-leaders-table tbody"),
  competitionSeasonChart: document.getElementById("competition-season-chart"),
  teamLeadersChart: document.getElementById("team-leaders-chart"),
  teamTrendChart: document.getElementById("team-trend-chart"),
  playerLeadersChart: document.getElementById("player-leaders-chart"),
  playerTrendChart: document.getElementById("player-trend-chart"),
  competitionValueHeading: document.getElementById("competition-value-heading"),
  teamValueHeading: document.getElementById("team-value-heading"),
  playerValueHeading: document.getElementById("player-value-heading"),
  panelViewButtons: document.querySelectorAll("[data-panel][data-view-mode]"),
  seasonActionButtons: document.querySelectorAll("[data-season-action]")
};


function isLocalApiConfigured() {
  try {
    const apiUrl = new URL(API_BASE_URL, window.location.href);
    return apiUrl.hostname === "localhost" || apiUrl.hostname === "127.0.0.1";
  } catch {
    return API_BASE_URL.startsWith("http://localhost") || API_BASE_URL.startsWith("http://127.0.0.1");
  }
}

function showStatus(message, tone = "neutral") {
  elements.statusBanner.textContent = message;
  elements.statusBanner.dataset.tone = tone;
  elements.statusBanner.role = tone === "error" ? "alert" : "status";
  elements.statusBanner.hidden = !message;
}

function buildUrl(path, params = {}) {
  const url = new URL(`${API_BASE_URL}${path}`, window.location.href);
  Object.entries(params).forEach(([key, value]) => {
    if (Array.isArray(value)) {
      if (value.length) {
        url.searchParams.set(key, value.join(","));
      }
      return;
    }

    if (value !== undefined && value !== null && `${value}`.trim() !== "") {
      url.searchParams.set(key, value);
    }
  });
  return url;
}

async function fetchJson(path, params = {}) {
  const controller = new AbortController();
  const timeoutId = window.setTimeout(() => controller.abort(), DEFAULT_TIMEOUT_MS);

  try {
    const response = await fetch(buildUrl(path, params), {
      headers: {
        Accept: "application/json"
      },
      signal: controller.signal
    });

    const payload = await response.json().catch(() => ({ error: "Unexpected server response." }));
    if (!response.ok) {
      const message = Array.isArray(payload.error) ? payload.error.join(" ") : payload.error;
      throw new Error(message || `Request failed with status ${response.status}.`);
    }

    return payload;
  } catch (error) {
    if (error.name === "AbortError") {
      throw new Error("The request timed out.");
    }
    throw error;
  } finally {
    window.clearTimeout(timeoutId);
  }
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

const fmtDate = new Intl.DateTimeFormat("en-AU", {
  year: "numeric",
  month: "short",
  day: "numeric",
  hour: "numeric",
  minute: "2-digit"
});

function formatDate(value) {
  if (!value) {
    return "-";
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return fmtDate.format(date);
}

function clearTable(tableBody, message) {
  tableBody.replaceChildren();
  const row = document.createElement("tr");
  const cell = document.createElement("td");
  cell.colSpan = tableBody.parentElement.querySelectorAll("thead th").length;
  cell.textContent = message;
  row.appendChild(cell);
  tableBody.appendChild(row);
  syncResponsiveTable(tableBody.closest("table"));
}

function createCell(text, className) {
  const cell = document.createElement("td");
  if (className) {
    cell.className = className;
  }
  cell.textContent = text;
  return cell;
}

function playerProfileUrl(playerId) {
  return `/player/${encodeURIComponent(playerId)}/`;
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
  if (!elements.seasonChoices) return;
  const selected = new Set(values.map((value) => `${value}`));
  elements.seasonChoices.querySelectorAll("input[type='checkbox']").forEach((input) => {
    input.checked = selected.has(input.value);
  });
}

function getSelectedSeasons() {
  if (!elements.seasonChoices) return [];
  return [...elements.seasonChoices.querySelectorAll("input[type='checkbox']:checked")]
    .map((input) => input.value)
    .sort((left, right) => Number(right) - Number(left));
}

function renderSeasonChoices(seasons) {
  if (!elements.seasonChoices) return;
  elements.seasonChoices.replaceChildren();
  seasons.forEach((season) => {
    const label = document.createElement("label");
    label.className = "season-choice";

    const input = document.createElement("input");
    input.type = "checkbox";
    input.value = `${season}`;
    input.name = "season-choice";

    const text = document.createElement("span");
    text.textContent = `${season}`;

    label.append(input, text);
    elements.seasonChoices.appendChild(label);
  });
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

function selectedLimit(value, fallback) {
  const numeric = Number.parseInt(value, 10);
  return Number.isFinite(numeric) && numeric > 0 ? numeric : fallback;
}

function isAverageMetric() {
  return state.filters.statMode === "average";
}

function statModeLabel() {
  return isAverageMetric() ? "Avg/game" : "Total";
}

function statModeDescriptor() {
  return isAverageMetric() ? "average per game" : "total";
}

function statValue(row) {
  if (row && row.value !== undefined && row.value !== null && row.value !== "") {
    return row.value;
  }
  return isAverageMetric() ? row?.average_value : row?.total_value;
}

function updateValueHeadings() {
  const label = statModeLabel();
  elements.competitionValueHeading.textContent = label;
  elements.teamValueHeading.textContent = label;
  elements.playerValueHeading.textContent = label;
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
    playerSearch: elements.playerSearch.value.trim()
  };
}

function renderFilterSummary() {
  syncFiltersFromForm();
  const segments = [
    seasonSummaryLabel(state.filters.seasons),
    teamLabel(state.filters.teamId),
    state.filters.round ? `Round ${state.filters.round}` : "All rounds",
    statModeDescriptor(),
    `Team ${state.filters.teamStat || "-"}`,
    `Player ${state.filters.playerStat || "-"}`
  ];

  if (state.filters.playerSearch) {
    segments.push(`Player search: ${state.filters.playerSearch}`);
  }

  elements.activeFilterSummary.textContent = segments.join(" • ");
  updateValueHeadings();
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
    meta.team_stats.map((stat) => ({ value: stat, label: stat })),
    "Choose a team stat"
  );
  populateSelect(
    elements.playerStat,
    meta.player_stats.map((stat) => ({ value: stat, label: stat })),
    "Choose a player stat"
  );

  const defaultSeason = meta.default_season ? `${meta.default_season}` : "";
  setSelectedSeasons(defaultSeason ? [defaultSeason] : []);
  elements.teamId.value = "";
  elements.round.value = "";
  elements.playerSearch.value = "";
  elements.statMode.value = "total";
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

  const fragment = document.createDocumentFragment();
  rows.forEach((rowData, index) => {
    const colour = resolveTeamColour(rowData.squad_name, rowData.squad_colour, index);
    const row = document.createElement("tr");
    row.setAttribute("data-rank", index + 1);
    row.style.setProperty("--row-accent", colour);
    row.append(
      createCell(`${index + 1}`),
      createTeamCell(rowData.squad_name, colour),
      createCell(rowData.stat),
      createCell(formatNumber(statValue(rowData))),
      createCell(formatNumber(rowData.matches_played))
    );
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

  const fragment = document.createDocumentFragment();
  rows.forEach((rowData, index) => {
    const colour = resolvePlayerColour(rowData.player_name, rowData.squad_name, index);
    const row = document.createElement("tr");
    row.setAttribute("data-rank", index + 1);
    row.style.setProperty("--row-accent", colour);
    row.append(
      createCell(`${index + 1}`),
      createLinkCell(playerProfileUrl(rowData.player_id), rowData.player_name),
      createTeamCell(rowData.squad_name || "-", colour),
      createCell(rowData.stat),
      createCell(formatNumber(statValue(rowData))),
      createCell(formatNumber(rowData.matches_played))
    );
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

  const fragment = document.createDocumentFragment();
  rows.forEach((rowData) => {
    const row = document.createElement("tr");
    row.append(
      createCell(`${rowData.season}`),
      createCell(rowData.stat),
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
  return CHART_PALETTE[index % CHART_PALETTE.length];
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
}

function renderCompetitionSeasonChart(rows, errorMessage) {
  if (errorMessage) {
    clearChart(elements.competitionSeasonChart, errorMessage);
    return;
  }

  renderSeasonColumnChart(elements.competitionSeasonChart, rows, {
    ariaLabel: `Competition ${statModeDescriptor()} chart by season for ${state.filters.teamStat}`,
    emptyMessage: "No results for these filters.",
    labelAccessor: (row) => row.season,
    valueAccessor: (row) => statValue(row),
    colourAccessor: (_row, index) => fallbackColour(index)
  });
}

function renderTeamCharts(leaderRows, trendRows) {
  const chartLeaderRows = leaderRows.slice(0, CHART_RANK_LIMIT);

  renderHorizontalBarChart(elements.teamLeadersChart, chartLeaderRows, {
    ariaLabel: `Team leaderboard ${statModeDescriptor()} chart for ${state.filters.teamStat}`,
    emptyMessage: "No results for these filters.",
    labelAccessor: (row) => row.squad_name,
    valueAccessor: (row) => statValue(row),
    colourAccessor: (row, index) => resolveTeamColour(row.squad_name, row.squad_colour, index)
  });

  renderTrendChart(elements.teamTrendChart, trendRows, {
    ariaLabel: `Team season ${statModeDescriptor()} chart for ${state.filters.teamStat}`,
    emptyMessage: "No results for these filters.",
    singleSeasonMessage: "Select two or more seasons to see trends.",
    idAccessor: (row) => row.squad_id,
    labelAccessor: (row) => row.squad_name,
    valueAccessor: (row) => statValue(row),
    colourAccessor: (row, index) => resolveTeamColour(row.squad_name, row.squad_colour, index)
  });
}

function renderPlayerCharts(leaderRows, trendRows) {
  const chartLeaderRows = leaderRows.slice(0, CHART_RANK_LIMIT);

  renderHorizontalBarChart(elements.playerLeadersChart, chartLeaderRows, {
    ariaLabel: `Player leaderboard ${statModeDescriptor()} chart for ${state.filters.playerStat}`,
    emptyMessage: "No results for these filters.",
    labelAccessor: (row) => row.player_name,
    valueAccessor: (row) => statValue(row),
    colourAccessor: (row, index) => resolvePlayerColour(row.player_name, row.squad_name, index)
  });

  renderTrendChart(elements.playerTrendChart, trendRows, {
    ariaLabel: `Player season ${statModeDescriptor()} chart for ${state.filters.playerStat}`,
    emptyMessage: "No results for these filters.",
    singleSeasonMessage: "Select two or more seasons to see trends.",
    idAccessor: (row) => row.player_id,
    labelAccessor: (row) => row.player_name,
    valueAccessor: (row) => statValue(row),
    colourAccessor: (row, index) => resolvePlayerColour(row.player_name, row.squad_name, index)
  });
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
  showStatus("Loading…");
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
      playerLeadersPayload,
      competitionSeriesPayload,
      teamSeriesPayload,
      playerSeriesPayload
    ] = await Promise.all([
      fetchJson("/summary", baseParams),
      fetchJson("/matches", { ...baseParams, limit: MATCHES_LIMIT }),
      fetchJson("/team-leaders", {
        ...baseParams,
        stat: state.filters.teamStat,
        metric: state.filters.statMode,
        limit: leaderboardFetchLimit
      }),
      fetchJson("/player-leaders", {
        ...baseParams,
        stat: state.filters.playerStat,
        search: state.filters.playerSearch,
        metric: state.filters.statMode,
        limit: leaderboardFetchLimit
      }),
      fetchOptionalJson("/competition-season-series", {
        seasons: state.filters.seasons,
        round: state.filters.round,
        stat: state.filters.teamStat,
        metric: state.filters.statMode
      }),
      fetchOptionalJson("/team-season-series", {
        ...baseParams,
        stat: state.filters.teamStat,
        metric: state.filters.statMode,
        limit: CHART_RANK_LIMIT
      }),
      fetchOptionalJson("/player-season-series", {
        ...baseParams,
        stat: state.filters.playerStat,
        search: state.filters.playerSearch,
        metric: state.filters.statMode,
        limit: CHART_RANK_LIMIT
      })
    ]);

    const chartWarnings = [
      competitionSeriesPayload.error,
      teamSeriesPayload.error,
      playerSeriesPayload.error
    ].filter(Boolean);
    const teamLeaderRows = teamLeadersPayload.data || [];
    const playerLeaderRows = playerLeadersPayload.data || [];

    if (seq !== runQuerySeq) return;

    renderSummary(summary);
    renderMatches(matchesPayload.data || []);
    renderCompetitionSeasonTable(
      competitionSeriesPayload.data || [],
      competitionSeriesPayload.error ? "Season totals temporarily unavailable." : ""
    );
    renderTeamLeaders(teamLeaderRows.slice(0, LEADERS_LIMIT));
    renderPlayerLeaders(playerLeaderRows.slice(0, LEADERS_LIMIT));
    renderCompetitionSeasonChart(
      competitionSeriesPayload.data || [],
      competitionSeriesPayload.error ? "Season chart temporarily unavailable." : ""
    );
    renderTeamCharts(teamLeaderRows, teamSeriesPayload.data || []);
    renderPlayerCharts(playerLeaderRows, playerSeriesPayload.data || []);
    showStatus(
      chartWarnings.length
        ? "Loaded. Some charts are still catching up."
        : "",
      chartWarnings.length ? "neutral" : "success"
    );
  } catch (error) {
    if (seq !== runQuerySeq) return;
    showStatus(error.message || "Couldn't load stats.", "error");
    clearAllTables("Couldn't load stats.");
    clearAllCharts("Couldn't load charts.");
  } finally {
    if (seq === runQuerySeq && submitBtn) {
      submitBtn.disabled = false;
      submitBtn.removeAttribute("aria-busy");
    }
  }
}

async function initialise() {
  clearAllTables("Loading…");
  clearAllCharts("Loading…");

  try {
    let meta;
    try {
      meta = await fetchJson("/meta");
    } catch (firstError) {
      // Retry once to handle cold-start delays (R/Plumber can take 20-30s to start).
      showStatus("Starting up, please wait…", "info");
      await new Promise((resolve) => window.setTimeout(resolve, 5000));
      meta = await fetchJson("/meta");
    }
    applyMeta(meta);
    await runQueries();
  } catch (error) {
    const hint = isLocalApiConfigured()
      ? "Run the API before using the site locally."
      : "Stats unavailable. Try again shortly.";
    showStatus(hint, "error");
    clearAllTables("Stats unavailable.");
    clearAllCharts("Stats unavailable.");
  }
}

elements.filtersForm.addEventListener("submit", (event) => {
  event.preventDefault();
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

  applyMeta(state.meta);
  runQueries();
});

elements.panelViewButtons.forEach((button) => {
  button.addEventListener("click", () => {
    setPanelView(button.dataset.panel, button.dataset.viewMode);
  });
});

setPanelView("team-leaders", "table");
setPanelView("player-leaders", "table");

initialise();
