const {
  buildUrl,
  clearEmptyTableState = () => {},
  fetchJson,
  formatNumber,
  playerProfileUrl = (playerId) => `/player/${encodeURIComponent(playerId)}/`,
  renderEmptyTableRow = () => {},
  showElementLoadingStatus = () => {},
  showElementStatus = () => {},
  syncResponsiveTable = () => {}
} = window.NetballStatsUI || {};
const {
  trackEvent = () => {},
  trackPageView = () => {}
} = window.NetballStatsTelemetry || {};

const LOADING_MESSAGES = [
  "Calculating wins above replacement…",
  "Computing fantasy scores…",
  "Ranking contributions…"
];

const ERA_LABELS = {
  anzc: "ANZC era",
  ssn: "SSN era"
};

const POSITION_GROUP_LABELS = {
  shooter: "Shooters",
  midcourt: "Midcourt",
  defender: "Defenders"
};

const state = {
  seasons: [],
  rows: []
};

const elements = {
  nwarStatus: document.getElementById("nwar-status"),
  nwarHeroLabel: document.getElementById("nwar-hero-label"),
  nwarHeroSummary: document.getElementById("nwar-hero-summary"),
  nwarMeta: document.getElementById("nwar-meta"),
  nwarFilters: document.getElementById("nwar-filters"),
  nwarSeason: document.getElementById("nwar-season"),
  nwarMinGames: document.getElementById("nwar-min-games"),
  nwarEra: document.getElementById("nwar-era"),
  nwarPositionGroup: document.getElementById("nwar-position-group"),
  nwarValueHeading: document.getElementById("nwar-value-heading"),
  nwarTbody: document.getElementById("nwar-tbody")
};

function showStatus(message, tone = "neutral", options = {}) {
  showElementStatus(elements.nwarStatus, message, tone, options);
}

function showLoadingStatus(messages, kicker) {
  showElementLoadingStatus(elements.nwarStatus, messages, kicker);
}

function formatNwar(value) {
  if (value == null || !Number.isFinite(Number(value))) return "—";
  const n = Number(value);
  return n.toFixed(1);
}

function formatDecimal(value) {
  if (value == null || !Number.isFinite(Number(value))) return "—";
  return Number(value).toFixed(2);
}

function isAllSeasonsView() {
  return !elements.nwarSeason?.value;
}

function displayedNwarValue(row, usePerSeason = false) {
  return usePerSeason ? row.nwar_per_season : row.nwar;
}

function updateNwarHeading(usePerSeason = false) {
  if (!elements.nwarValueHeading) return;
  elements.nwarValueHeading.textContent = usePerSeason ? "nWAR/Season" : "nWAR";
}

function syncUrlState() {
  const params = new URLSearchParams();
  if (elements.nwarSeason?.value) params.set("season", elements.nwarSeason.value);
  if (elements.nwarMinGames?.value) params.set("min_games", elements.nwarMinGames.value);
  if (elements.nwarEra?.value) params.set("era", elements.nwarEra.value);
  if (elements.nwarPositionGroup?.value) params.set("position_group", elements.nwarPositionGroup.value);

  const nextUrl = params.toString()
    ? `${window.location.pathname}?${params.toString()}`
    : window.location.pathname;
  window.history.replaceState(null, "", nextUrl);
}

function hydrateFiltersFromUrl() {
  const params = new URLSearchParams(window.location.search);
  if (elements.nwarSeason && params.has("season")) elements.nwarSeason.value = params.get("season");
  if (elements.nwarMinGames && params.has("min_games")) elements.nwarMinGames.value = params.get("min_games");
  if (elements.nwarEra && params.has("era")) elements.nwarEra.value = params.get("era");
  if (elements.nwarPositionGroup && params.has("position_group")) elements.nwarPositionGroup.value = params.get("position_group");
}

function buildContextLabel({ season, era, positionGroup, allSeasonsView }) {
  const bits = [];
  if (season) {
    bits.push(`${season} season`);
  } else if (era) {
    bits.push(ERA_LABELS[era] || "selected era");
  } else {
    bits.push("all seasons");
  }
  if (positionGroup) {
    bits.push(POSITION_GROUP_LABELS[positionGroup] || positionGroup);
  }
  if (allSeasonsView) {
    bits.push("ordered by nWAR per season");
  }
  return bits.join(" — ");
}

function renderMessageRow(message, kicker = "") {
  const tbody = elements.nwarTbody;
  if (!tbody) return;
  renderEmptyTableRow(tbody, message, { colSpan: 9, kicker });
}

function renderTable(rows, usePerSeason = false) {
  const tbody = elements.nwarTbody;
  if (!tbody) return;
  updateNwarHeading(usePerSeason);
  if (!rows || !rows.length) {
    renderMessageRow("No qualifying players found for these filters. Try a lower minimum-games threshold.", "No data");
    return;
  }

  clearEmptyTableState(tbody);
  const fragment = document.createDocumentFragment();
  rows.forEach((row, index) => {
    const rank = index + 1;
    const tr = document.createElement("tr");
    tr.dataset.rank = String(rank);

    const nwarValue = Number(displayedNwarValue(row, usePerSeason));

    const playerCell = document.createElement("td");
    const playerLink = document.createElement("a");
    playerLink.className = "table-link";
    playerLink.href = playerProfileUrl(row.player_id);
    playerLink.textContent = row.player_name;
    playerCell.appendChild(playerLink);

    const rankCell = document.createElement("td");
    rankCell.textContent = formatNumber(rank);

    const teamCell = document.createElement("td");
    teamCell.textContent = row.squad_name || "—";

    const positionCell = document.createElement("td");
    positionCell.textContent = row.position_group || "—";

    const gamesCell = document.createElement("td");
    gamesCell.textContent = formatNumber(row.games_played);

    const avgCell = document.createElement("td");
    avgCell.textContent = formatDecimal(row.avg_fantasy_score);

    const replCell = document.createElement("td");
    replCell.textContent = formatDecimal(row.replacement_level);

    const nparCell = document.createElement("td");
    nparCell.textContent = formatDecimal(row.npar);

    const nwarCell = document.createElement("td");
    const nwarStrong = document.createElement("strong");
    if (nwarValue < 0) nwarStrong.className = "result-loser";
    nwarStrong.textContent = formatNwar(displayedNwarValue(row, usePerSeason));
    nwarCell.appendChild(nwarStrong);

    tr.append(rankCell, playerCell, teamCell, positionCell, gamesCell, avgCell, replCell, nparCell, nwarCell);
    fragment.appendChild(tr);
  });

  tbody.replaceChildren(fragment);
  syncResponsiveTable(document.getElementById("nwar-table"));
}

async function loadMetadata() {
  try {
    const meta = await fetchJson("/meta");
    state.seasons = (meta.seasons || []).slice();
    const seasonSelect = elements.nwarSeason;
    if (!seasonSelect) return;
    const currentValue = seasonSelect.value;
    while (seasonSelect.options.length > 1) {
      seasonSelect.remove(1);
    }
    state.seasons.forEach((season) => {
      const opt = document.createElement("option");
      opt.value = String(season);
      opt.textContent = String(season);
      seasonSelect.appendChild(opt);
    });
    if (currentValue) seasonSelect.value = currentValue;
  } catch (_) {
    // metadata failure is non-fatal — season filter just stays empty
  }
}

async function loadNwar() {
  if (!elements.nwarSeason || !elements.nwarMinGames || !elements.nwarTbody) return;
  const season = elements.nwarSeason.value;
  const minGames = elements.nwarMinGames.value;
  const era = elements.nwarEra?.value || "";
  const positionGroup = elements.nwarPositionGroup?.value || "";
  const allSeasonsView = isAllSeasonsView();
  showLoadingStatus(LOADING_MESSAGES, "Calculating nWAR");

  const params = { limit: "100" };
  if (season) params.season = season;
  if (minGames) params.min_games = minGames;
  if (era) params.era = era;
  if (positionGroup) params.position_group = positionGroup;
  syncUrlState();

  try {
    const payload = await fetchJson("/nwar", params);
    state.rows = payload.data || [];
    renderTable(state.rows, allSeasonsView);

    const contextLabel = buildContextLabel({
      season,
      era: season ? "" : era,
      positionGroup,
      allSeasonsView
    });

    if (elements.nwarMeta) {
      elements.nwarMeta.textContent = `${formatNumber(state.rows.length)} players ranked — ${contextLabel}.`;
    }

    const topPlayer = state.rows[0];
    if (topPlayer) {
      const topMetric = displayedNwarValue(topPlayer, allSeasonsView);
      if (elements.nwarHeroLabel) {
        elements.nwarHeroLabel.textContent = allSeasonsView
          ? `${topPlayer.player_name} — ${formatNwar(topMetric)} nWAR/season`
          : `${topPlayer.player_name} — ${formatNwar(topMetric)} nWAR`;
      }
      if (elements.nwarHeroSummary) {
        elements.nwarHeroSummary.textContent = allSeasonsView
          ? `${formatNumber(topPlayer.seasons_played)} seasons, ${formatNumber(topPlayer.games_played)} games, ${formatNwar(topPlayer.nwar)} career nWAR.`
          : `${formatNumber(topPlayer.games_played)} games, ${formatDecimal(topPlayer.avg_fantasy_score)} avg fantasy pts.`;
      }
    } else {
      if (elements.nwarHeroLabel) elements.nwarHeroLabel.textContent = "No qualifying players";
      if (elements.nwarHeroSummary) elements.nwarHeroSummary.textContent = "Try adjusting the minimum games filter.";
    }

    trackEvent("nwar_loaded", {
      season: season || "all",
      player_count: state.rows.length
    });
    showStatus("nWAR leaderboard ready.", "success", { kicker: "Rankings updated", autoHideMs: 2200 });
  } catch (error) {
    showStatus(error.message || "Unable to load nWAR rankings.", "error", { kicker: "Rankings unavailable" });
    if (elements.nwarMeta) elements.nwarMeta.textContent = "nWAR rankings unavailable.";
    updateNwarHeading(allSeasonsView);
    renderMessageRow("The nWAR rankings are unavailable. Try again shortly.", "Archive note");
    if (elements.nwarHeroLabel) elements.nwarHeroLabel.textContent = "Unavailable";
    if (elements.nwarHeroSummary) elements.nwarHeroSummary.textContent = "Unable to load the nWAR leaderboard.";
  }
}

if (elements.nwarFilters) {
  elements.nwarFilters.addEventListener("submit", (event) => {
    event.preventDefault();
    loadNwar();
  });
}

async function initialise() {
  trackPageView("nwar");
  await loadMetadata();
  hydrateFiltersFromUrl();
  await loadNwar();
}

initialise();
