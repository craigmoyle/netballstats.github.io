const config = window.NETBALL_STATS_CONFIG || {};
const API_BASE_URL = (config.apiBaseUrl || "/api").replace(/\/$/, "");
const DEFAULT_TIMEOUT_MS = 30000;
const {
  cycleStatusBanner = () => {}
} = window.NetballStatsUI || {};
const DIRECTORY_LOADING_MESSAGES = [
  "Opening the player ledger…",
  "Indexing career pages across the archive…"
];
const {
  bucketCount = () => "unknown",
  trackEvent = () => {}
} = window.NetballStatsTelemetry || {};

const fmtInt = new Intl.NumberFormat("en-AU", { maximumFractionDigits: 0 });

const state = {
  players: []
};

const elements = {
  directoryStatus: document.getElementById("directory-status"),
  directoryTotal: document.getElementById("directory-total"),
  directorySummary: document.getElementById("directory-summary"),
  directoryResultsMeta: document.getElementById("directory-results-meta"),
  directorySearchInput: document.getElementById("directory-search-input"),
  directoryGrid: document.getElementById("directory-grid")
};

function buildUrl(path, params = {}) {
  const url = new URL(`${API_BASE_URL}${path}`, window.location.href);
  Object.entries(params).forEach(([key, value]) => {
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
      throw new Error(payload.error || `Request failed with status ${response.status}.`);
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

function showStatus(message, tone = "neutral", options = {}) {
  if (!message) {
    window.NetballStatsUI?.showStatusBanner?.(elements.directoryStatus, "");
    return;
  }
  window.NetballStatsUI?.showStatusBanner?.(elements.directoryStatus, message, tone, options);
}

function showLoadingStatus(messages, kicker) {
  cycleStatusBanner(elements.directoryStatus, messages, {
    tone: "loading",
    kicker
  });
}

function formatNumber(value) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) {
    return value ?? "-";
  }

  return fmtInt.format(numeric);
}

function playerProfileUrl(playerId) {
  return `/player/${encodeURIComponent(playerId)}/`;
}

function debounce(fn, ms) {
  let timer;
  return function (...args) {
    clearTimeout(timer);
    timer = setTimeout(() => fn.apply(this, args), ms);
  };
}

function renderPlayers(players) {
  const query = elements.directorySearchInput.value.trim().toLowerCase();
  const filteredPlayers = players.filter((player) => {
    if (!query) {
      return true;
    }

    return `${player.player_name} ${player.search_name || ""}`.toLowerCase().includes(query);
  });

  elements.directoryResultsMeta.textContent = query
    ? `${formatNumber(filteredPlayers.length)} players match "${query}".`
    : `${formatNumber(players.length)} player profiles available.`;

  if (!filteredPlayers.length) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    empty.dataset.kicker = "Search the archive";
    empty.textContent = "No players matched that search. Try a shorter surname or a different spelling.";
    elements.directoryGrid.replaceChildren(empty);
    return;
  }

  const fragment = document.createDocumentFragment();
  filteredPlayers.forEach((player) => {
    const card = document.createElement("a");
    card.href = playerProfileUrl(player.player_id);
    card.className = "directory-card";

    const eyebrow = document.createElement("span");
    eyebrow.className = "directory-card__eyebrow";
    eyebrow.textContent = `Player ${player.player_id}`;

    const title = document.createElement("h2");
    title.className = "directory-card__title";
    title.textContent = player.player_name;

    const meta = document.createElement("p");
    meta.className = "directory-card__meta";
    const spanText = player.first_season && player.last_season
      ? `${player.first_season} to ${player.last_season}`
      : "";
    meta.textContent = spanText
      ? `${formatNumber(player.games_played)} games • ${spanText}`
      : "Open the full profile for career totals, games played, and season-by-season stats.";

    const footer = document.createElement("div");
    footer.className = "directory-card__footer";

    const profileTag = document.createElement("span");
    profileTag.className = "tag";
    profileTag.textContent = "Open profile";

    footer.append(profileTag);

    if (Number.isFinite(Number(player.games_played))) {
      const gamesTag = document.createElement("span");
      gamesTag.className = "tag";
      gamesTag.textContent = `${formatNumber(player.games_played)} matches`;
      footer.append(gamesTag);
    }

    if (spanText) {
      const spanTag = document.createElement("span");
      spanTag.className = "tag";
      spanTag.textContent = spanText;
      footer.append(spanTag);
    }
    card.append(eyebrow, title, meta, footer);
    fragment.appendChild(card);
  });
  elements.directoryGrid.replaceChildren(fragment);
}

async function initialise() {
  showLoadingStatus(DIRECTORY_LOADING_MESSAGES, "Directory in motion");

  try {
    const payload = await fetchJson("/players");
    state.players = payload.data || [];
    elements.directoryTotal.textContent = formatNumber(state.players.length);
    elements.directorySummary.textContent = "Career pages are live for every player currently in the database.";
    renderPlayers(state.players);
    trackEvent("player_directory_loaded", {
      player_count_bucket: bucketCount(state.players.length, [0, 10, 25, 50, 100, 250, 500])
    });
    showStatus("Player directory ready.", "success", { kicker: "Profiles indexed", autoHideMs: 2200 });
  } catch (error) {
    showStatus(error.message || "Unable to load the player directory.", "error", { kicker: "Directory unavailable" });
    elements.directoryResultsMeta.textContent = "Player directory unavailable.";
    elements.directoryGrid.innerHTML = '<div class="empty-state" data-kicker="Archive note">The player directory is taking a breather. Try again shortly.</div>';
  }
}

elements.directorySearchInput.addEventListener("input", debounce(() => {
  renderPlayers(state.players);
}, 150));

initialise();
