const config = window.NETBALL_STATS_CONFIG || {};
const API_BASE_URL = (config.apiBaseUrl || "/api").replace(/\/$/, "");
const DEFAULT_TIMEOUT_MS = 12000;
const TREND_SERIES_LIMIT = 5;
const CHART_PALETTE = [
  "#f0c67e",
  "#79d8d0",
  "#ff9e9e",
  "#f4a0d8",
  "#d1c36b",
  "#8ac6ff"
];

const state = {
  meta: null,
  filters: {
    seasons: [],
    teamId: "",
    round: "",
    teamStat: "goals",
    playerStat: "goals",
    playerSearch: "",
    matchesLimit: "12",
    leadersLimit: "10",
    highsLimit: "10"
  },
  views: {
    "team-leaders": "table",
    "player-leaders": "table"
  }
};

const elements = {
  statusBanner: document.getElementById("status-banner"),
  filtersForm: document.getElementById("filters-form"),
  seasonChoices: document.getElementById("season-choices"),
  seasonSummary: document.getElementById("season-summary"),
  activeFilterSummary: document.getElementById("active-filter-summary"),
  teamId: document.getElementById("team-id"),
  round: document.getElementById("round"),
  teamStat: document.getElementById("team-stat"),
  playerStat: document.getElementById("player-stat"),
  playerSearch: document.getElementById("player-search"),
  matchesLimit: document.getElementById("matches-limit"),
  leadersLimit: document.getElementById("leaders-limit"),
  highsLimit: document.getElementById("highs-limit"),
  resetFilters: document.getElementById("reset-filters"),
  summaryMatches: document.getElementById("summary-matches"),
  summaryTeams: document.getElementById("summary-teams"),
  summaryPlayers: document.getElementById("summary-players"),
  summaryGoals: document.getElementById("summary-goals"),
  summaryRefreshed: document.getElementById("summary-refreshed"),
  matchesTableBody: document.querySelector("#matches-table tbody"),
  teamLeadersBody: document.querySelector("#team-leaders-table tbody"),
  playerLeadersBody: document.querySelector("#player-leaders-table tbody"),
  teamHighsBody: document.querySelector("#team-highs-table tbody"),
  playerHighsBody: document.querySelector("#player-highs-table tbody"),
  teamLeadersChart: document.getElementById("team-leaders-chart"),
  teamTrendChart: document.getElementById("team-trend-chart"),
  playerLeadersChart: document.getElementById("player-leaders-chart"),
  playerTrendChart: document.getElementById("player-trend-chart"),
  teamBarNote: document.getElementById("team-bar-note"),
  teamTrendNote: document.getElementById("team-trend-note"),
  playerBarNote: document.getElementById("player-bar-note"),
  playerTrendNote: document.getElementById("player-trend-note"),
  apiBase: document.getElementById("api-base"),
  seasonActionButtons: document.querySelectorAll("[data-season-action]"),
  panelViewButtons: document.querySelectorAll("[data-panel][data-view-mode]")
};

document.body.classList.remove("is-ready");
elements.apiBase.textContent = API_BASE_URL;

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

    const payload = await response.json().catch(() => ({ error: "The API returned invalid JSON." }));
    if (!response.ok) {
      const message = Array.isArray(payload.error) ? payload.error.join(" ") : payload.error;
      throw new Error(message || `Request failed with status ${response.status}.`);
    }

    return payload;
  } finally {
    window.clearTimeout(timeoutId);
  }
}

function formatNumber(value) {
  if (value === null || value === undefined || value === "") {
    return "-";
  }

  const numeric = Number(value);
  if (!Number.isFinite(numeric)) {
    return value;
  }

  return new Intl.NumberFormat("en-AU", {
    maximumFractionDigits: Number.isInteger(numeric) ? 0 : 2
  }).format(numeric);
}

function formatDate(value) {
  if (!value) {
    return "-";
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return new Intl.DateTimeFormat("en-AU", {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit"
  }).format(date);
}

function clearTable(tableBody, message) {
  tableBody.replaceChildren();
  const row = document.createElement("tr");
  const cell = document.createElement("td");
  cell.colSpan = tableBody.parentElement.querySelectorAll("thead th").length;
  cell.textContent = message;
  row.appendChild(cell);
  tableBody.appendChild(row);
}

function clearChart(container, message) {
  container.replaceChildren();
  container.dataset.state = "empty";
  const empty = document.createElement("p");
  empty.className = "chart-empty";
  empty.textContent = message;
  container.appendChild(empty);
}

function createCell(text, className) {
  const cell = document.createElement("td");
  if (className) {
    cell.className = className;
  }
  cell.textContent = text;
  return cell;
}

function createSvgElement(tagName, attributes = {}, textContent = "") {
  const element = document.createElementNS("http://www.w3.org/2000/svg", tagName);
  Object.entries(attributes).forEach(([key, value]) => {
    if (value !== undefined && value !== null) {
      element.setAttribute(key, `${value}`);
    }
  });
  if (textContent) {
    element.textContent = textContent;
  }
  return element;
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
  const selected = new Set(values.map((value) => `${value}`));
  elements.seasonChoices.querySelectorAll("input[type='checkbox']").forEach((input) => {
    input.checked = selected.has(input.value);
  });
}

function getSelectedSeasons() {
  return [...elements.seasonChoices.querySelectorAll("input[type='checkbox']:checked")]
    .map((input) => input.value)
    .sort((left, right) => Number(right) - Number(left));
}

function renderSeasonChoices(seasons) {
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

function syncFiltersFromForm() {
  state.filters = {
    seasons: getSelectedSeasons(),
    teamId: elements.teamId.value,
    round: elements.round.value,
    teamStat: elements.teamStat.value,
    playerStat: elements.playerStat.value,
    playerSearch: elements.playerSearch.value.trim(),
    matchesLimit: elements.matchesLimit.value,
    leadersLimit: elements.leadersLimit.value,
    highsLimit: elements.highsLimit.value
  };
}

function renderFilterSummary() {
  syncFiltersFromForm();
  const segments = [
    seasonSummaryLabel(state.filters.seasons),
    teamLabel(state.filters.teamId),
    state.filters.round ? `Round ${state.filters.round}` : "All rounds",
    `Team ${state.filters.teamStat || "-"}`,
    `Player ${state.filters.playerStat || "-"}`
  ];

  if (state.filters.playerSearch) {
    segments.push(`Player ${state.filters.playerSearch}`);
  }

  segments.push(
    `${state.filters.matchesLimit} match rows`,
    `${state.filters.leadersLimit} leaderboard rows`,
    `${state.filters.highsLimit} game highs`
  );

  elements.activeFilterSummary.textContent = segments.join(" • ");
  elements.seasonSummary.textContent = seasonSummaryLabel(state.filters.seasons);
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
  elements.matchesLimit.value = "12";
  elements.leadersLimit.value = "10";
  elements.highsLimit.value = "10";
  elements.teamStat.value = meta.team_stats.includes("goals") ? "goals" : meta.team_stats[0] || "";
  elements.playerStat.value = meta.player_stats.includes("goals") ? "goals" : meta.player_stats[0] || "";
  renderFilterSummary();
  setPanelView("team-leaders", state.views["team-leaders"]);
  setPanelView("player-leaders", state.views["player-leaders"]);
}

function renderSummary(summary) {
  elements.summaryMatches.textContent = formatNumber(summary.total_matches);
  elements.summaryTeams.textContent = formatNumber(summary.total_teams);
  elements.summaryPlayers.textContent = formatNumber(summary.total_players);
  elements.summaryGoals.textContent = formatNumber(summary.total_goals);
  elements.summaryRefreshed.textContent = formatDate(summary.refreshed_at);
}

function renderMatches(matches) {
  if (!matches.length) {
    clearTable(elements.matchesTableBody, "No matches found for the selected filters.");
    return;
  }

  elements.matchesTableBody.replaceChildren();
  matches.forEach((match) => {
    const row = document.createElement("tr");
    row.append(
      createCell(`${match.season} ${match.competition_phase}`),
      createCell(`R${match.round_number} G${match.game_number}`),
      createCell(`${match.home_squad_name} ${formatNumber(match.home_score)} - ${formatNumber(match.away_score)} ${match.away_squad_name}`),
      createCell(match.venue_name || "-"),
      createCell(formatDate(match.local_start_time))
    );
    elements.matchesTableBody.appendChild(row);
  });
}

function renderTeamLeaders(rows) {
  if (!rows.length) {
    clearTable(elements.teamLeadersBody, "No team leaderboard rows matched the selected filters.");
    return;
  }

  elements.teamLeadersBody.replaceChildren();
  rows.forEach((rowData, index) => {
    const row = document.createElement("tr");
    row.append(
      createCell(`${index + 1}`),
      createCell(rowData.squad_name),
      createCell(rowData.stat),
      createCell(formatNumber(rowData.total_value)),
      createCell(formatNumber(rowData.matches_played))
    );
    elements.teamLeadersBody.appendChild(row);
  });
}

function renderPlayerLeaders(rows) {
  if (!rows.length) {
    clearTable(elements.playerLeadersBody, "No player leaderboard rows matched the selected filters.");
    return;
  }

  elements.playerLeadersBody.replaceChildren();
  rows.forEach((rowData, index) => {
    const row = document.createElement("tr");
    row.append(
      createCell(`${index + 1}`),
      createCell(rowData.player_name),
      createCell(rowData.squad_name || "-"),
      createCell(rowData.stat),
      createCell(formatNumber(rowData.total_value))
    );
    elements.playerLeadersBody.appendChild(row);
  });
}

function renderTeamHighs(rows) {
  if (!rows.length) {
    clearTable(elements.teamHighsBody, "No team game highs matched the selected filters.");
    return;
  }

  elements.teamHighsBody.replaceChildren();
  rows.forEach((rowData, index) => {
    const row = document.createElement("tr");
    row.append(
      createCell(`${index + 1}`),
      createCell(rowData.squad_name),
      createCell(rowData.opponent || "-"),
      createCell(`${rowData.season}`),
      createCell(`R${rowData.round_number}`),
      createCell(formatNumber(rowData.total_value))
    );
    elements.teamHighsBody.appendChild(row);
  });
}

function renderPlayerHighs(rows) {
  if (!rows.length) {
    clearTable(elements.playerHighsBody, "No player game highs matched the selected filters.");
    return;
  }

  elements.playerHighsBody.replaceChildren();
  rows.forEach((rowData, index) => {
    const row = document.createElement("tr");
    row.append(
      createCell(`${index + 1}`),
      createCell(rowData.player_name),
      createCell(rowData.squad_name || "-"),
      createCell(rowData.opponent || "-"),
      createCell(`${rowData.season}`),
      createCell(`R${rowData.round_number}`),
      createCell(formatNumber(rowData.total_value))
    );
    elements.playerHighsBody.appendChild(row);
  });
}

function clearAllTables(message) {
  clearTable(elements.matchesTableBody, message);
  clearTable(elements.teamLeadersBody, message);
  clearTable(elements.playerLeadersBody, message);
  clearTable(elements.teamHighsBody, message);
  clearTable(elements.playerHighsBody, message);
}

function clearAllCharts(message) {
  clearChart(elements.teamLeadersChart, message);
  clearChart(elements.teamTrendChart, message);
  clearChart(elements.playerLeadersChart, message);
  clearChart(elements.playerTrendChart, message);
}

function truncateLabel(value, maxLength = 18) {
  if (!value || value.length <= maxLength) {
    return value || "-";
  }
  return `${value.slice(0, maxLength - 1)}…`;
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

function renderHorizontalBarChart(container, rows, {
  ariaLabel,
  emptyMessage,
  labelAccessor,
  valueAccessor,
  colourAccessor
}) {
  if (!rows.length) {
    clearChart(container, emptyMessage);
    return;
  }

  const chartRows = rows.map((row, index) => ({
    label: labelAccessor(row, index),
    value: Number(valueAccessor(row, index)) || 0,
    colour: colourAccessor(row, index)
  }));

  const maxValue = Math.max(...chartRows.map((row) => row.value), 1);
  const width = 760;
  const left = 196;
  const right = 84;
  const top = 26;
  const bottom = 20;
  const barHeight = 24;
  const gap = 16;
  const innerWidth = width - left - right;
  const height = top + bottom + (chartRows.length * (barHeight + gap)) - gap;
  const svg = createSvgElement("svg", {
    viewBox: `0 0 ${width} ${height}`,
    class: "chart-svg",
    preserveAspectRatio: "xMidYMid meet"
  });

  [0, 0.25, 0.5, 0.75, 1].forEach((ratio) => {
    const x = left + (innerWidth * ratio);
    svg.appendChild(createSvgElement("line", {
      x1: x,
      x2: x,
      y1: top - 8,
      y2: height - bottom + 4,
      class: "chart-grid-line"
    }));
    svg.appendChild(createSvgElement("text", {
      x,
      y: top - 12,
      "text-anchor": ratio === 0 ? "start" : ratio === 1 ? "end" : "middle",
      class: "chart-grid-label"
    }, formatNumber(maxValue * ratio)));
  });

  chartRows.forEach((row, index) => {
    const y = top + (index * (barHeight + gap));
    const barWidth = maxValue > 0 ? (innerWidth * row.value) / maxValue : 0;

    svg.appendChild(createSvgElement("text", {
      x: left - 12,
      y: y + (barHeight / 2) + 5,
      "text-anchor": "end",
      class: "chart-label"
    }, truncateLabel(row.label, 19)));

    svg.appendChild(createSvgElement("rect", {
      x: left,
      y,
      width: innerWidth,
      height: barHeight,
      rx: 12,
      class: "chart-track"
    }));

    const bar = createSvgElement("rect", {
      x: left,
      y,
      width: Math.max(barWidth, 2),
      height: barHeight,
      rx: 12,
      fill: row.colour,
      class: "chart-bar"
    });
    bar.appendChild(createSvgElement("title", {}, `${row.label}: ${formatNumber(row.value)}`));
    svg.appendChild(bar);

    svg.appendChild(createSvgElement("text", {
      x: width - 8,
      y: y + (barHeight / 2) + 5,
      "text-anchor": "end",
      class: "chart-value"
    }, formatNumber(row.value)));
  });

  container.replaceChildren(svg);
  container.removeAttribute("data-state");
  container.setAttribute("aria-label", ariaLabel);
}

function renderTrendChart(container, rows, {
  ariaLabel,
  emptyMessage,
  singleSeasonMessage,
  idAccessor,
  labelAccessor,
  valueAccessor,
  colourAccessor
}) {
  if (!rows.length) {
    clearChart(container, emptyMessage);
    return;
  }

  const seasons = [...new Set(
    rows
      .map((row) => Number(row.season))
      .filter((value) => Number.isFinite(value))
  )].sort((left, right) => left - right);

  if (seasons.length < 2) {
    clearChart(container, singleSeasonMessage);
    return;
  }

  const grouped = new Map();
  rows.forEach((row) => {
    const id = `${idAccessor(row)}`;
    if (!grouped.has(id)) {
      grouped.set(id, {
        id,
        label: labelAccessor(row),
        colour: colourAccessor(row, grouped.size),
        points: new Map()
      });
    }
    grouped.get(id).points.set(Number(row.season), Number(valueAccessor(row)) || 0);
  });

  const series = [...grouped.values()];
  const maxValue = Math.max(
    ...series.flatMap((entry) => [...entry.points.values()]),
    1
  );

  const width = 760;
  const height = 360;
  const left = 56;
  const right = 20;
  const top = 20;
  const bottom = 54;
  const innerWidth = width - left - right;
  const innerHeight = height - top - bottom;
  const svg = createSvgElement("svg", {
    viewBox: `0 0 ${width} ${height}`,
    class: "chart-svg",
    preserveAspectRatio: "xMidYMid meet"
  });

  const xForSeason = (season) => {
    const index = seasons.indexOf(season);
    const span = Math.max(seasons.length - 1, 1);
    return left + (innerWidth * index) / span;
  };
  const yForValue = (value) => top + innerHeight - ((innerHeight * value) / maxValue);

  [0, 0.25, 0.5, 0.75, 1].forEach((ratio) => {
    const y = top + innerHeight - (innerHeight * ratio);
    svg.appendChild(createSvgElement("line", {
      x1: left,
      x2: width - right,
      y1: y,
      y2: y,
      class: "chart-grid-line"
    }));
    svg.appendChild(createSvgElement("text", {
      x: left - 8,
      y: y + 4,
      "text-anchor": "end",
      class: "chart-grid-label"
    }, formatNumber(maxValue * ratio)));
  });

  svg.appendChild(createSvgElement("line", {
    x1: left,
    x2: left,
    y1: top,
    y2: height - bottom,
    class: "chart-axis-line"
  }));

  seasons.forEach((season) => {
    const x = xForSeason(season);
    svg.appendChild(createSvgElement("line", {
      x1: x,
      x2: x,
      y1: height - bottom,
      y2: height - bottom + 6,
      class: "chart-axis-line"
    }));
    svg.appendChild(createSvgElement("text", {
      x,
      y: height - bottom + 22,
      "text-anchor": "middle",
      class: "chart-axis"
    }, `${season}`));
  });

  series.forEach((entry) => {
    const definedPoints = seasons
      .filter((season) => entry.points.has(season))
      .map((season) => ({
        season,
        value: entry.points.get(season),
        x: xForSeason(season),
        y: yForValue(entry.points.get(season))
      }));

    if (!definedPoints.length) {
      return;
    }

    const path = definedPoints
      .map((point, index) => `${index === 0 ? "M" : "L"} ${point.x} ${point.y}`)
      .join(" ");

    const line = createSvgElement("path", {
      d: path,
      stroke: entry.colour,
      class: "chart-series-line"
    });
    line.appendChild(createSvgElement("title", {}, `${entry.label}`));
    svg.appendChild(line);

    definedPoints.forEach((point) => {
      const dot = createSvgElement("circle", {
        cx: point.x,
        cy: point.y,
        r: 5,
        fill: entry.colour,
        class: "chart-dot"
      });
      dot.appendChild(createSvgElement("title", {}, `${entry.label} • ${point.season}: ${formatNumber(point.value)}`));
      svg.appendChild(dot);
    });
  });

  const legend = document.createElement("div");
  legend.className = "chart-legend";
  series.forEach((entry) => {
    const latestSeason = [...entry.points.keys()].sort((left, right) => right - left)[0];
    const latestValue = latestSeason ? entry.points.get(latestSeason) : null;

    const item = document.createElement("div");
    item.className = "chart-legend__item";

    const swatch = document.createElement("span");
    swatch.className = "chart-legend__swatch";
    swatch.style.background = entry.colour;

    const label = document.createElement("span");
    label.textContent = latestValue === null
      ? entry.label
      : `${truncateLabel(entry.label, 24)} · ${formatNumber(latestValue)}`;

    item.append(swatch, label);
    legend.appendChild(item);
  });

  container.replaceChildren(svg, legend);
  container.removeAttribute("data-state");
  container.setAttribute("aria-label", ariaLabel);
}

function renderTeamCharts(leaderRows, trendRows) {
  elements.teamBarNote.textContent = `${state.filters.teamStat} totals ranked across ${describeSeasonScope()} and the active filters.`;
  elements.teamTrendNote.textContent = `Season totals for the strongest clubs under the current ${state.filters.teamStat} filter.`;

  renderHorizontalBarChart(elements.teamLeadersChart, leaderRows, {
    ariaLabel: `Team leaderboard bar chart for ${state.filters.teamStat}`,
    emptyMessage: "No team leaderboard chart data matched the selected filters.",
    labelAccessor: (row) => row.squad_name,
    valueAccessor: (row) => row.total_value,
    colourAccessor: (row, index) => resolveTeamColour(row.squad_name, row.squad_colour, index)
  });

  renderTrendChart(elements.teamTrendChart, trendRows, {
    ariaLabel: `Team season trend chart for ${state.filters.teamStat}`,
    emptyMessage: "No team trend data matched the selected filters.",
    singleSeasonMessage: "Select at least two seasons to compare team trends over time.",
    idAccessor: (row) => row.squad_id,
    labelAccessor: (row) => row.squad_name,
    valueAccessor: (row) => row.total_value,
    colourAccessor: (row, index) => resolveTeamColour(row.squad_name, row.squad_colour, index)
  });
}

function renderPlayerCharts(leaderRows, trendRows) {
  elements.playerBarNote.textContent = state.filters.playerSearch
    ? `${state.filters.playerStat} totals for players matching “${state.filters.playerSearch}” across ${describeSeasonScope()}.`
    : `${state.filters.playerStat} totals ranked across ${describeSeasonScope()} and the active filters.`;
  elements.playerTrendNote.textContent = state.filters.playerSearch
    ? `Season totals for the strongest matching players under the current ${state.filters.playerStat} filter.`
    : `Season totals for the strongest players under the current ${state.filters.playerStat} filter.`;

  renderHorizontalBarChart(elements.playerLeadersChart, leaderRows, {
    ariaLabel: `Player leaderboard bar chart for ${state.filters.playerStat}`,
    emptyMessage: "No player leaderboard chart data matched the selected filters.",
    labelAccessor: (row) => row.player_name,
    valueAccessor: (row) => row.total_value,
    colourAccessor: (row, index) => resolvePlayerColour(row.player_name, row.squad_name, index)
  });

  renderTrendChart(elements.playerTrendChart, trendRows, {
    ariaLabel: `Player season trend chart for ${state.filters.playerStat}`,
    emptyMessage: "No player trend data matched the selected filters.",
    singleSeasonMessage: "Select at least two seasons to compare player trends over time.",
    idAccessor: (row) => row.player_id,
    labelAccessor: (row) => row.player_name,
    valueAccessor: (row) => row.total_value,
    colourAccessor: (row, index) => resolvePlayerColour(row.player_name, row.squad_name, index)
  });
}

async function runQueries() {
  syncFiltersFromForm();
  renderFilterSummary();
  showStatus("Loading summary, matches, leaderboards, game highs, and charts…");

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
      teamSeriesPayload,
      playerSeriesPayload,
      teamHighsPayload,
      playerHighsPayload
    ] = await Promise.all([
      fetchJson("/summary", baseParams),
      fetchJson("/matches", { ...baseParams, limit: state.filters.matchesLimit }),
      fetchJson("/team-leaders", {
        ...baseParams,
        stat: state.filters.teamStat,
        limit: state.filters.leadersLimit
      }),
      fetchJson("/player-leaders", {
        ...baseParams,
        stat: state.filters.playerStat,
        search: state.filters.playerSearch,
        limit: state.filters.leadersLimit
      }),
      fetchJson("/team-season-series", {
        ...baseParams,
        stat: state.filters.teamStat,
        limit: TREND_SERIES_LIMIT
      }),
      fetchJson("/player-season-series", {
        ...baseParams,
        stat: state.filters.playerStat,
        search: state.filters.playerSearch,
        limit: TREND_SERIES_LIMIT
      }),
      fetchJson("/team-game-highs", {
        ...baseParams,
        stat: state.filters.teamStat,
        limit: state.filters.highsLimit
      }),
      fetchJson("/player-game-highs", {
        ...baseParams,
        stat: state.filters.playerStat,
        search: state.filters.playerSearch,
        limit: state.filters.highsLimit
      })
    ]);

    renderSummary(summary);
    renderMatches(matchesPayload.data || []);
    renderTeamLeaders(teamLeadersPayload.data || []);
    renderPlayerLeaders(playerLeadersPayload.data || []);
    renderTeamCharts(teamLeadersPayload.data || [], teamSeriesPayload.data || []);
    renderPlayerCharts(playerLeadersPayload.data || [], playerSeriesPayload.data || []);
    renderTeamHighs(teamHighsPayload.data || []);
    renderPlayerHighs(playerHighsPayload.data || []);
    showStatus("Query completed successfully.", "success");
    document.body.classList.add("is-ready");
  } catch (error) {
    showStatus(error.message || "The query failed.", "error");
    clearAllTables("Unable to load data from the API.");
    clearAllCharts("Unable to load chart data from the API.");
    document.body.classList.add("is-ready");
  }
}

async function initialise() {
  clearAllTables("Loading data…");
  clearAllCharts("Loading chart data…");

  try {
    const meta = await fetchJson("/meta");
    applyMeta(meta);
    await runQueries();
  } catch (error) {
    const baseMessage = error.message || "Unable to load the API metadata.";
    const hint = isLocalApiConfigured()
      ? " Build the database and run the API before using the site."
      : " The statistics API is currently unavailable. Please try again shortly.";
    showStatus(
      `${baseMessage}${hint}`,
      "error"
    );
    clearAllTables("API metadata is unavailable.");
    clearAllCharts("API metadata is unavailable.");
    document.body.classList.add("is-ready");
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
