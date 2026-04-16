const {
  buildUrl,
  clearEmptyTableState = () => {},
  fetchJson,
  formatNumber,
  getCheckedValues = () => [],
  renderEmptyTableRow = () => {},
  renderSeasonCheckboxes = () => {},
  setCheckedValues = () => {},
  showElementLoadingStatus = () => {},
  showElementStatus = () => {},
  syncResponsiveTable = () => {}
} = window.NetballStatsUI || {};
const {
  trackEvent = () => {}
} = window.NetballStatsTelemetry || {};

const LOADING_MESSAGES = [
  "Reading the scoreflow archive…",
  "Tracing lead and trail patterns…",
  "Pulling comeback records…"
];

const METRIC_SORT_LABELS = {
  comeback_deficit_points: "comeback deficit",
  largest_lead_points: "largest lead",
  deepest_deficit_points: "deepest deficit",
  seconds_leading: "time leading",
  seconds_trailing: "time trailing",
  trailing_share: "trailing share"
};

const state = {
  meta: null,
  gameRecords: null,
  teamSummary: null,
  filters: {
    seasons: [],
    teamId: "",
    opponentId: "",
    scenario: "all",
    metric: "comeback_deficit_points"
  },
  requestToken: 0
};

const elements = {
  status: document.getElementById("scoreflow-status"),
  filters: document.getElementById("scoreflow-filters"),
  seasonChoices: document.getElementById("scoreflow-season-choices"),
  seasonSummary: document.getElementById("scoreflow-season-summary"),
  team: document.getElementById("scoreflow-team"),
  opponent: document.getElementById("scoreflow-opponent"),
  scenario: document.getElementById("scoreflow-scenario"),
  metric: document.getElementById("scoreflow-metric"),
  meta: document.getElementById("scoreflow-meta"),
  recordsTitle: document.getElementById("scoreflow-records-title"),
  recordsCopy: document.getElementById("scoreflow-records-copy"),
  recordsTable: document.getElementById("scoreflow-records-table"),
  recordsBody: document.getElementById("scoreflow-records-body"),
  teamTitle: document.getElementById("scoreflow-team-title"),
  teamTable: document.getElementById("scoreflow-team-table"),
  teamBody: document.getElementById("scoreflow-team-body"),
  glossary: document.getElementById("scoreflow-glossary")
};

function showStatus(message, tone = "neutral", options = {}) {
  showElementStatus(elements.status, message, tone, options);
}

function showLoadingStatus() {
  showElementLoadingStatus(elements.status, LOADING_MESSAGES, "Loading scoreflow");
}

function wait(ms) {
  return new Promise((resolve) => {
    window.setTimeout(resolve, ms);
  });
}

function renderMessageRow(tbody, colspan, message, kicker = "") {
  renderEmptyTableRow(tbody, message, { colSpan: colspan, kicker });
}

function getSelectedSeasons() {
  return getCheckedValues(elements.seasonChoices)
    .sort((a, b) => Number(b) - Number(a));
}

function setSelectedSeasons(values) {
  setCheckedValues(elements.seasonChoices, values);
}

function describeSeasons(seasons) {
  if (!seasons.length) return "all seasons";
  if (seasons.length === 1) return `season ${seasons[0]}`;
  return `${seasons.length} selected seasons`;
}

function updateSeasonSummary() {
  if (!elements.seasonSummary) return;
  const seasons = getSelectedSeasons();
  elements.seasonSummary.textContent = seasons.length
    ? `Showing ${describeSeasons(seasons)}.`
    : "Showing all seasons.";
}

function renderSeasonChoices(seasons = []) {
  renderSeasonCheckboxes(elements.seasonChoices, seasons, {
    inputName: "scoreflow-season-choice",
    onChange: () => {
      updateSeasonSummary();
      state.filters.seasons = getSelectedSeasons();
      syncUrlState();
    }
  });
}

function renderTeamChoices(teams = []) {
  [elements.team, elements.opponent].forEach((select) => {
    if (!select) return;
    const currentValue = select.value;
    while (select.options.length > 1) {
      select.remove(1);
    }
    teams.forEach((team) => {
      const option = document.createElement("option");
      option.value = String(team.squad_id);
      option.textContent = team.squad_name;
      select.appendChild(option);
    });
    if (currentValue) {
      select.value = currentValue;
    }
  });
}

function syncUrlState() {
  const params = new URLSearchParams();
  const seasons = getSelectedSeasons();
  if (seasons.length) params.set("seasons", seasons.join(","));
  if (elements.team?.value) params.set("team_id", elements.team.value);
  if (elements.opponent?.value) params.set("opponent_id", elements.opponent.value);
  if (elements.scenario?.value && elements.scenario.value !== "all") params.set("scenario", elements.scenario.value);
  if (elements.metric?.value && elements.metric.value !== "comeback_deficit_points") params.set("metric", elements.metric.value);
  const nextUrl = params.toString()
    ? `${window.location.pathname}?${params.toString()}`
    : window.location.pathname;
  window.history.replaceState(null, "", nextUrl);
}

function hydrateFiltersFromUrl() {
  const params = new URLSearchParams(window.location.search);
  const seasonsParam = params.get("seasons") || params.get("season") || "";
  const seasonValues = seasonsParam.split(",").map((v) => v.trim()).filter(Boolean);
  if (seasonValues.length) {
    setSelectedSeasons(seasonValues);
  }
  if (elements.team && params.has("team_id")) elements.team.value = params.get("team_id");
  if (elements.opponent && params.has("opponent_id")) elements.opponent.value = params.get("opponent_id");
  if (elements.scenario && params.has("scenario")) elements.scenario.value = params.get("scenario");
  if (elements.metric && params.has("metric")) elements.metric.value = params.get("metric");
}

function readFilterState() {
  state.filters.seasons = getSelectedSeasons();
  state.filters.teamId = elements.team?.value || "";
  state.filters.opponentId = elements.opponent?.value || "";
  state.filters.scenario = elements.scenario?.value || "all";
  state.filters.metric = elements.metric?.value || "comeback_deficit_points";
}

function sortKeyForMetric(metric) {
  const map = {
    comeback_deficit_points: "largest_comeback_win_points",
    largest_lead_points: "largest_comeback_win_points",
    deepest_deficit_points: "games_trailed_most",
    seconds_leading: "total_seconds_leading",
    seconds_trailing: "total_seconds_trailing",
    trailing_share: "total_seconds_trailing",
    won_trailing_most: "won_trailing_most"
  };
  return map[metric] || "total_seconds_leading";
}

function formatSeconds(value) {
  const n = Number(value);
  if (!Number.isFinite(n) || n == null) return "—";
  const mins = Math.floor(n / 60);
  return `${formatNumber(mins)} min`;
}

function formatPercent(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return "—";
  return `${(n * 100).toFixed(1)}%`;
}

function createGlossaryItem(term, definition) {
  const dt = document.createElement("dt");
  dt.textContent = term;
  const dd = document.createElement("dd");
  dd.textContent = definition;
  const frag = document.createDocumentFragment();
  frag.append(dt, dd);
  return frag;
}

function renderGlossary() {
  if (!elements.glossary) return;
  elements.glossary.replaceChildren(
    createGlossaryItem("Comeback deficit", "The largest points deficit a team overcame in a match they went on to win."),
    createGlossaryItem("Won trailing most", "Won despite trailing for more than half of the match."),
    createGlossaryItem("Trailing share", "The share of match time spent behind on the scoreboard."),
    createGlossaryItem("Comeback wins", "Matches where the final winner held a deficit they eventually erased."),
    createGlossaryItem("Games led most", "Matches where a team led for more than half of the available scoreflow time."),
    createGlossaryItem("Largest lead", "The maximum points advantage a team held at any single point in the match.")
  );
}

function renderRecordsTable() {
  const records = state.gameRecords;
  if (!Array.isArray(records) || !records.length) {
    renderMessageRow(
      elements.recordsBody, 8,
      "No scoreflow records match the current filter set. Try a broader season range or different scenario.",
      "No records"
    );
    syncResponsiveTable(elements.recordsTable);
    return;
  }

  clearEmptyTableState(elements.recordsBody);
  const fragment = document.createDocumentFragment();
  records.forEach((row) => {
    const tr = document.createElement("tr");

    const teamCell = document.createElement("td");
    teamCell.dataset.stackPrimary = "true";
    teamCell.textContent = row.squad_name || row.squad_code || "—";

    const oppCell = document.createElement("td");
    oppCell.textContent = row.opponent_name || row.opponent_code || "—";

    const seasonCell = document.createElement("td");
    seasonCell.textContent = row.season != null ? `${row.season}` : "—";

    const roundCell = document.createElement("td");
    roundCell.textContent = row.round_number != null ? `Rd ${row.round_number}` : "—";

    const resultCell = document.createElement("td");
    if (row.won === 1 || row.won === true) {
      resultCell.textContent = "Win";
      resultCell.dataset.result = "win";
    } else {
      resultCell.textContent = "Loss";
      resultCell.dataset.result = "loss";
    }

    const comebackCell = document.createElement("td");
    const comebackVal = Number(row.comeback_deficit_points);
    comebackCell.textContent = Number.isFinite(comebackVal) && comebackVal > 0 ? `${comebackVal} pts` : "—";

    const leadCell = document.createElement("td");
    const leadVal = Number(row.largest_lead_points);
    leadCell.textContent = Number.isFinite(leadVal) && leadVal > 0 ? `${leadVal} pts` : "—";

    const trailingCell = document.createElement("td");
    trailingCell.textContent = formatPercent(row.trailing_share);

    tr.append(teamCell, oppCell, seasonCell, roundCell, resultCell, comebackCell, leadCell, trailingCell);
    fragment.appendChild(tr);
  });

  elements.recordsBody.replaceChildren(fragment);
  syncResponsiveTable(elements.recordsTable);
}

function updateRecordsHeading() {
  const seasons = state.filters.seasons;
  const metric = state.filters.metric;
  const metricLabel = METRIC_SORT_LABELS[metric] || metric;
  const seasonLabel = describeSeasons(seasons);
  if (elements.recordsTitle) {
    elements.recordsTitle.textContent = `Top games by ${metricLabel} — ${seasonLabel}`;
  }
  if (elements.recordsCopy) {
    const scenario = elements.scenario?.options[elements.scenario.selectedIndex]?.text || "";
    const scenarioNote = scenario && scenario !== "All games" ? ` — filtered to: ${scenario.toLowerCase()}` : "";
    elements.recordsCopy.textContent = `Strongest scoreflow stories from the archive${scenarioNote}.`;
  }
}

function renderTeamSummaryTable() {
  const rows = state.teamSummary;
  if (!Array.isArray(rows) || !rows.length) {
    renderMessageRow(
      elements.teamBody, 5,
      "No team scoreflow data for this filter set.",
      "No data"
    );
    syncResponsiveTable(elements.teamTable);
    return;
  }

  clearEmptyTableState(elements.teamBody);
  const fragment = document.createDocumentFragment();
  rows.forEach((row) => {
    const tr = document.createElement("tr");

    const teamCell = document.createElement("td");
    teamCell.dataset.stackPrimary = "true";
    teamCell.textContent = row.squad_name || row.squad_code || "—";

    const matchesCell = document.createElement("td");
    matchesCell.textContent = row.matches_with_scoreflow != null
      ? formatNumber(Number(row.matches_with_scoreflow))
      : "—";

    const ledMostCell = document.createElement("td");
    ledMostCell.textContent = row.games_led_most != null
      ? formatNumber(Number(row.games_led_most))
      : "—";

    const comebackCell = document.createElement("td");
    comebackCell.textContent = row.comeback_wins != null
      ? formatNumber(Number(row.comeback_wins))
      : "—";

    const biggestCell = document.createElement("td");
    const biggest = Number(row.largest_comeback_win_points);
    biggestCell.textContent = Number.isFinite(biggest) && biggest > 0 ? `${biggest} pts` : "—";

    tr.append(teamCell, matchesCell, ledMostCell, comebackCell, biggestCell);
    fragment.appendChild(tr);
  });

  elements.teamBody.replaceChildren(fragment);
  syncResponsiveTable(elements.teamTable);
}

function updateMetaLine() {
  if (!elements.meta) return;
  const seasons = state.filters.seasons;
  const teamName = state.meta?.teams?.find((t) => `${t.squad_id}` === state.filters.teamId)?.squad_name || "";
  const parts = [];
  parts.push(describeSeasons(seasons));
  if (teamName) parts.push(teamName);
  elements.meta.textContent = parts.join(" · ");
}

async function loadScoreflowData() {
  const seasons = getSelectedSeasons().join(",");
  const teamId = elements.team?.value || "";
  const opponentId = elements.opponent?.value || "";
  const scenario = elements.scenario?.value || "all";
  const metric = elements.metric?.value || "comeback_deficit_points";

  const recordParams = { limit: 25 };
  if (seasons) recordParams.seasons = seasons;
  if (teamId) recordParams.team_id = teamId;
  if (opponentId) recordParams.opponent_id = opponentId;
  if (scenario !== "all") recordParams.scenario = scenario;
  if (metric !== "comeback_deficit_points") recordParams.metric = metric;

  const teamParams = { min_matches: 1, limit: 10 };
  if (seasons) teamParams.seasons = seasons;
  if (teamId) teamParams.team_id = teamId;
  teamParams.sort_by = sortKeyForMetric(metric);

  const [records, teams] = await Promise.all([
    fetchJson("/scoreflow-game-records", recordParams),
    fetchJson("/scoreflow-team-summary", teamParams)
  ]);

  state.gameRecords = Array.isArray(records?.data) ? records.data : [];
  state.teamSummary = Array.isArray(teams?.data) ? teams.data : [];
}

async function loadMetadata(retries = 1) {
  let attempt = 0;
  let lastError = null;
  while (attempt <= retries) {
    try {
      const meta = await fetchJson("/meta");
      state.meta = meta;
      renderSeasonChoices(meta.seasons || []);
      renderTeamChoices(meta.teams || []);
      return meta;
    } catch (error) {
      lastError = error;
      if (attempt >= retries) break;
      await wait(1500 * (attempt + 1));
      attempt += 1;
    }
  }
  throw lastError;
}

function renderAll() {
  updateMetaLine();
  updateRecordsHeading();
  renderRecordsTable();
  renderTeamSummaryTable();
}

async function loadAndRender() {
  const requestToken = ++state.requestToken;
  readFilterState();
  syncUrlState();
  showLoadingStatus();
  try {
    await loadScoreflowData();
    if (requestToken !== state.requestToken) return;
    renderAll();
    trackEvent("scoreflow_loaded", {
      seasons: state.filters.seasons.join(",") || "all",
      team_id: state.filters.teamId || "all",
      scenario: state.filters.scenario,
      metric: state.filters.metric
    });
    showStatus("Scoreflow records ready.", "success", {
      kicker: "Archive updated",
      autoHideMs: 2200
    });
  } catch (error) {
    if (requestToken !== state.requestToken) return;
    state.gameRecords = null;
    state.teamSummary = null;
    renderMessageRow(elements.recordsBody, 8, "Scoreflow records unavailable. Try again shortly.", "Archive note");
    renderMessageRow(elements.teamBody, 5, "Team summary unavailable. Try again shortly.", "Archive note");
    if (elements.meta) elements.meta.textContent = "Scoreflow unavailable.";
    showStatus(error.message || "Unable to load scoreflow data.", "error", {
      kicker: "Archive unavailable"
    });
  }
}

if (elements.filters) {
  elements.filters.addEventListener("submit", (event) => {
    event.preventDefault();
    loadAndRender();
  });
}

async function initScoreflowPage() {
  renderGlossary();
  try {
    await loadMetadata(1);
  } catch (error) {
    if (elements.meta) {
      elements.meta.textContent = "Archive metadata is taking longer than usual.";
    }
  }
  hydrateFiltersFromUrl();
  if (!getSelectedSeasons().length && state.meta?.default_season) {
    setSelectedSeasons([String(state.meta.default_season)]);
  }
  updateSeasonSummary();
  await loadAndRender();
}

document.addEventListener("DOMContentLoaded", () => {
  void initScoreflowPage();
});
