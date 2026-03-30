const {
  buildUrl,
  cycleStatusBanner = () => {},
  fetchJson,
  formatNumber
} = window.NetballStatsUI || {};
const DIRECTORY_LOADING_MESSAGES = [
  "Loading player directory…",
  "Indexing profile pages…"
];
const {
  bucketCount = () => "unknown",
  trackEvent = () => {}
} = window.NetballStatsTelemetry || {};

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
      : "Open the profile for career totals and season splits.";

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
  showLoadingStatus(DIRECTORY_LOADING_MESSAGES, "Loading directory");

  try {
    const payload = await fetchJson("/players");
    state.players = payload.data || [];
    elements.directoryTotal.textContent = formatNumber(state.players.length);
    elements.directorySummary.textContent = "Profiles are live for every player in the archive.";
    renderPlayers(state.players);
    trackEvent("player_directory_loaded", {
      player_count_bucket: bucketCount(state.players.length, [0, 10, 25, 50, 100, 250, 500])
    });
    showStatus("Player directory ready.", "success", { kicker: "Profiles indexed", autoHideMs: 2200 });
  } catch (error) {
    showStatus(error.message || "Unable to load the player directory.", "error", { kicker: "Directory unavailable" });
    elements.directoryResultsMeta.textContent = "Player directory unavailable.";
    const empty = document.createElement('div');
    empty.className = 'empty-state';
    empty.dataset.kicker = 'Archive note';
    empty.textContent = 'The player directory is unavailable. Try again shortly.';
    elements.directoryGrid.replaceChildren(empty);
  }
}

elements.directorySearchInput.addEventListener("input", debounce(() => {
  renderPlayers(state.players);
}, 150));

initialise();
