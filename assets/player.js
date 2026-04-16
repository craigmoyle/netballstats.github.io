const SUPER_SHOT_START_SEASON = 2020;
const {
  buildUrl,
  fetchJson,
  formatNumber,
  formatStatAbbrev = (stat) => stat,
  formatStatLabel = (stat) => stat,
  showElementLoadingStatus = () => {},
  showElementStatus = () => {},
  syncResponsiveTable = () => {}
} = window.NetballStatsUI || {};
const {
  bucketCount = () => "unknown",
  trackEvent = () => {}
} = window.NetballStatsTelemetry || {};
const PLAYER_LOADING_MESSAGES = [
  "Loading player record…",
  "Loading career totals…",
  "Loading season splits…"
];
const PLAYER_STAT_DEFINITIONS = [
  ["netPoints", "Net Points"],
  ["intercepts", "Intercepts"],
  ["obstructionPenalties", "Obstructions"],
  ["contactPenalties", "Contacts"],
  ["generalPlayTurnovers", "General Play Turnovers"],
  ["unforcedTurnovers", "Unforced Turnovers"],
  ["pickups", "Pickups"],
  ["gain", "Gains"],
  ["centrePassReceives", "Centre Pass Receives"],
  ["deflections", "Deflections"],
  ["rebounds", "Rebounds"],
  ["goal1", "1 Point Goals"],
  ["attempts1", "1 Point Goal Attempts"],
  ["goal2", "2 Point Goals"],
  ["attempts2", "2 Point Goal Attempts"],
  ["feeds", "Feeds into Circle"],
  ["goalAssists", "Goal Assists"]
];
const PLAYER_STAT_ORDER = PLAYER_STAT_DEFINITIONS.map(([key]) => key);
const PLAYER_STAT_LABELS = new Map(PLAYER_STAT_DEFINITIONS);
const LEGACY_STAT_ALIASES = new Map([
  ["goal1", "goals"],
  ["attempts1", "goalAttempts"]
]);

const state = {
  metric: "total",
  profile: null
};

const elements = {
  playerStatus: document.getElementById("player-status"),
  playerName: document.getElementById("player-name"),
  playerSubtitle: document.getElementById("player-subtitle"),
  playerIntro: document.getElementById("player-intro"),
  playerSquads: document.getElementById("player-squads"),
  careerSpan: document.getElementById("career-span"),
  careerSpanSummary: document.getElementById("career-span-summary"),
  summaryGames: document.getElementById("summary-games"),
  summarySeasons: document.getElementById("summary-seasons"),
  summaryTeams: document.getElementById("summary-teams"),
  summaryStats: document.getElementById("summary-stats"),
  summaryPrimary: document.getElementById("summary-primary"),
  careerStatsBody: document.getElementById("career-stats-body"),
  seasonTableCaption: document.getElementById("season-table-caption"),
  seasonStatsHead: document.getElementById("season-stats-head"),
  seasonStatsBody: document.getElementById("season-stats-body"),
  playerPillars: document.getElementById("player-pillars"),
  playerMarginalia: document.getElementById("player-marginalia"),
  seasonLedgerNotes: document.getElementById("season-ledger-notes"),
  metricButtons: Array.from(document.querySelectorAll("[data-metric]"))
};

function showStatus(message, tone = "neutral", options = {}) {
  showElementStatus(elements.playerStatus, message, tone, options);
}

function showLoadingStatus(messages, kicker) {
  showElementLoadingStatus(elements.playerStatus, messages, kicker);
}

function createCell(text, label) {
  const cell = document.createElement("td");
  cell.textContent = text;
  if (label) {
    cell.dataset.label = label;
  }
  return cell;
}

function statLabel(statKey) {
  return PLAYER_STAT_LABELS.get(statKey) || formatStatLabel(statKey);
}

function statKeysForProfile(statKey) {
  const legacyAlias = LEGACY_STAT_ALIASES.get(statKey);
  return legacyAlias ? [statKey, legacyAlias] : [statKey];
}

function roundStatValue(value) {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

function normalizedSeasonStatMap(summary) {
  const statMap = new Map((summary.stats || []).map((entry) => [entry.stat, entry]));
  const season = Number(summary.season || 0);

  if (season < SUPER_SHOT_START_SEASON) {
    if (!statMap.has("goal1") && statMap.has("goals")) {
      statMap.set("goal1", { ...statMap.get("goals"), stat: "goal1" });
    }

    if (!statMap.has("attempts1") && statMap.has("goalAttempts")) {
      statMap.set("attempts1", { ...statMap.get("goalAttempts"), stat: "attempts1" });
    }
  }

  return statMap;
}

function aggregateCareerStat(profile, statKey) {
  const seasonEntries = (profile.season_summaries || [])
    .map((summary) => normalizedSeasonStatMap(summary).get(statKey))
    .filter(Boolean);

  if (!seasonEntries.length) {
    return null;
  }

  const totalValue = seasonEntries.reduce((sum, entry) => sum + Number(entry.total_value || 0), 0);
  const matchesPlayed = seasonEntries.reduce((sum, entry) => sum + Number(entry.matches_played || 0), 0);

  return {
    stat: statKey,
    total_value: roundStatValue(totalValue),
    average_value: matchesPlayed > 0 ? roundStatValue(totalValue / matchesPlayed) : null,
    matches_played: matchesPlayed
  };
}

function selectedCareerStats(profile) {
  return PLAYER_STAT_ORDER
    .map((stat) => aggregateCareerStat(profile, stat))
    .filter(Boolean);
}

function selectedStatsForProfile(profile) {
  const availableStats = new Set(profile.available_stats || []);
  const seasonSummaries = profile.season_summaries || [];

  return PLAYER_STAT_ORDER.filter((stat) =>
    statKeysForProfile(stat).some((key) => availableStats.has(key)) ||
    seasonSummaries.some((summary) => normalizedSeasonStatMap(summary).has(stat))
  );
}

function metricValue(entry) {
  if (!entry) {
    return "-";
  }

  return state.metric === "average" ? entry.average_value : entry.total_value;
}

function parsePlayerId() {
  const url = new URL(window.location.href);
  const fromQuery = url.searchParams.get("player_id");
  if (fromQuery && /^\d+$/.test(fromQuery)) {
    return Number(fromQuery);
  }

  const segments = window.location.pathname.split("/").filter(Boolean);
  const playerIndex = segments.indexOf("player");
  const rawSegment = playerIndex >= 0 ? segments[playerIndex + 1] : "";
  const match = rawSegment ? rawSegment.match(/^(\d+)/) : null;
  return match ? Number(match[1]) : NaN;
}

function renderSquads(squadNames) {
  elements.playerSquads.replaceChildren();
  (squadNames || []).forEach((squadName) => {
    const tag = document.createElement("span");
    tag.className = "tag";
    tag.textContent = squadName;
    elements.playerSquads.appendChild(tag);
  });
}

function renderCareerStats(careerStats) {
  elements.careerStatsBody.replaceChildren();

  if (!careerStats.length) {
    const row = document.createElement("tr");
    const cell = document.createElement("td");
    cell.colSpan = 4;
    cell.textContent = "No career stats for this player.";
    row.appendChild(cell);
    elements.careerStatsBody.appendChild(row);
    syncResponsiveTable(elements.careerStatsBody.closest("table"));
    return;
  }

  careerStats.forEach((entry) => {
    const row = document.createElement("tr");
    row.append(
      createCell(statLabel(entry.stat)),
      createCell(formatNumber(entry.total_value)),
      createCell(formatNumber(entry.average_value)),
      createCell(formatNumber(entry.matches_played))
    );
    elements.careerStatsBody.appendChild(row);
  });
  syncResponsiveTable(elements.careerStatsBody.closest("table"));
}

function renderSeasonTable(profile) {
  const stats = selectedStatsForProfile(profile);
  const seasonSummaries = profile.season_summaries || [];

  elements.seasonTableCaption.textContent = state.metric === "average"
    ? "Per-game averages for key stats."
    : "Season totals for key stats.";

  elements.seasonStatsHead.replaceChildren();
  ["Season", "Clubs"].forEach((label) => {
    const cell = document.createElement("th");
    cell.scope = "col";
    cell.textContent = label;
    elements.seasonStatsHead.appendChild(cell);
  });
  [{ abbrev: "Gms", label: "Games", key: null }, ...stats.map((s) => ({ abbrev: formatStatAbbrev(s), label: statLabel(s), key: s }))].forEach(({ abbrev, label }) => {
    const cell = document.createElement("th");
    cell.scope = "col";
    cell.className = "season-table__stat-head";
    cell.textContent = abbrev;
    cell.title = label;
    elements.seasonStatsHead.appendChild(cell);
  });

  elements.seasonStatsBody.replaceChildren();

  if (!seasonSummaries.length) {
    const row = document.createElement("tr");
    const cell = document.createElement("td");
    cell.colSpan = 3 + stats.length;
    cell.textContent = "No season summaries for this player.";
    row.appendChild(cell);
    elements.seasonStatsBody.appendChild(row);
    return;
  }

  seasonSummaries.forEach((summary) => {
    const statMap = normalizedSeasonStatMap(summary);
    const row = document.createElement("tr");
    row.className = "season-table__row";
    row.append(
      createCell(`${summary.season}`, "Season"),
      createCell((summary.squad_names || []).join(" / ") || "-", "Clubs"),
      createCell(formatNumber(summary.matches_played), "Games")
    );

    stats.forEach((stat) => {
      row.appendChild(createCell(formatNumber(metricValue(statMap.get(stat))), statLabel(stat)));
    });

    elements.seasonStatsBody.appendChild(row);
  });
}

function buildDossierPillars(profile, topCareerStat) {
  const overview = profile.overview || {};
  const latestSeason = overview.last_season || null;
  return [
    {
      label: "Career span",
      value: overview.first_season && overview.last_season ? `${overview.first_season}–${overview.last_season}` : "Single season",
      note: `${formatNumber(overview.seasons_played)} seasons`
    },
    {
      label: "Games",
      value: formatNumber(overview.games_played),
      note: `${formatNumber(overview.teams_played)} clubs`
    },
    {
      label: "Primary record",
      value: topCareerStat ? formatNumber(topCareerStat.total_value) : "--",
      note: topCareerStat ? statLabel(topCareerStat.stat) : "No primary stat"
    },
    {
      label: "Latest season",
      value: latestSeason ? `${latestSeason}` : "--",
      note: "Archive dossier"
    }
  ];
}

function buildDossierNotes(profile, topCareerStat) {
  const overview = profile.overview || {};
  const summaries = [...(profile.season_summaries || [])].sort((left, right) => Number(right.season) - Number(left.season));
  const peakSeason = summaries.reduce((best, summary) =>
    !best || Number(summary.matches_played || 0) > Number(best.matches_played || 0) ? summary : best, null);

  return [
    peakSeason ? `Peak workload: ${formatNumber(peakSeason.matches_played)} games in ${peakSeason.season}.` : "Peak workload unavailable.",
    topCareerStat ? `Signature total: ${formatNumber(topCareerStat.total_value)} ${statLabel(topCareerStat.stat).toLowerCase()}.` : "Signature total unavailable.",
    (overview.squad_names || []).length ? `Club trail: ${(overview.squad_names || []).join(" / ")}.` : "Club trail unavailable."
  ];
}

function renderDossierPillars(pillars) {
  if (!elements.playerPillars) return;
  elements.playerPillars.replaceChildren();
  pillars.forEach((pillar) => {
    const article = document.createElement("article");
    article.className = "dossier-pillar";

    const label = document.createElement("span");
    label.className = "summary-card__label";
    label.textContent = pillar.label;

    const value = document.createElement("strong");
    value.className = "summary-card__value";
    value.textContent = pillar.value;

    const note = document.createElement("p");
    note.className = "muted";
    note.textContent = pillar.note;

    article.append(label, value, note);
    elements.playerPillars.appendChild(article);
  });
}

function renderDossierNotes(notes) {
  if (!elements.playerMarginalia) return;
  elements.playerMarginalia.replaceChildren();
  notes.forEach((noteText) => {
    const item = document.createElement("li");
    item.textContent = noteText;
    elements.playerMarginalia.appendChild(item);
  });
}

function updateSeasonLedgerNotes() {
  if (!elements.seasonLedgerNotes) return;
  elements.seasonLedgerNotes.textContent = state.metric === "average"
    ? "Per-game view keeps season shifts readable while the ledger preserves the full table."
    : "Use the ledger to scan peaks, club changes, and long-run consistency.";
}

function setMetric(nextMetric) {
  state.metric = nextMetric;
  elements.metricButtons.forEach((button) => {
    const isActive = button.dataset.metric === nextMetric;
    button.classList.toggle("is-active", isActive);
    button.classList.toggle("button--ghost", !isActive);
    button.setAttribute("aria-pressed", `${isActive}`);
  });

  if (state.profile) {
    renderSeasonTable(state.profile);
    updateSeasonLedgerNotes();
  }
}

function renderProfile(profile) {
  state.profile = profile;

  const playerName = profile.player?.canonical_name || profile.player?.player_name || "Unknown player";
  const overview = profile.overview || {};
  const careerStats = selectedCareerStats(profile);
  const topCareerStat = careerStats
    .slice()
    .sort((left, right) => Number(right.total_value || 0) - Number(left.total_value || 0))[0];
  const pillars = buildDossierPillars(profile, topCareerStat);
  const notes = buildDossierNotes(profile, topCareerStat);

  document.title = `${playerName} | Netball Stats Database`;
  elements.playerName.textContent = playerName;
  elements.playerSubtitle.textContent = `Archive record ${profile.player?.player_id ?? ""}`.trim();
  elements.playerIntro.textContent = `${overview.first_season && overview.last_season ? `${overview.first_season}\u2013${overview.last_season}` : "Single-season"} dossier · ${formatNumber(overview.games_played)} games across ${formatNumber(overview.seasons_played)} seasons and ${formatNumber(overview.teams_played)} clubs.`;
  elements.careerSpan.textContent = overview.first_season && overview.last_season
    ? `${overview.first_season} to ${overview.last_season}`
    : "Single season";
  elements.careerSpanSummary.textContent = (overview.squad_names || []).length
    ? `Filed under ${(overview.squad_names || []).join(", ")}`
    : "Club history unavailable.";

  elements.summaryGames.textContent = formatNumber(overview.games_played);
  elements.summarySeasons.textContent = formatNumber(overview.seasons_played);
  elements.summaryTeams.textContent = formatNumber(overview.teams_played);
  elements.summaryStats.textContent = formatNumber(careerStats.length);
  elements.summaryPrimary.textContent = topCareerStat
    ? `${statLabel(topCareerStat.stat)} · ${formatNumber(topCareerStat.total_value)}`
    : "No totals yet";

  renderSquads(overview.squad_names || []);
  renderCareerStats(careerStats);
  renderDossierPillars(pillars);
  renderDossierNotes(notes);
  updateSeasonLedgerNotes();
  renderSeasonTable(profile);
}

async function initialise() {
  const playerId = parsePlayerId();
  if (!Number.isFinite(playerId)) {
    showStatus("No player ID was found in the page URL.", "error");
    return;
  }

  showLoadingStatus(PLAYER_LOADING_MESSAGES, "Loading profile");

  try {
    const profile = await fetchJson("/player-profile", { player_id: playerId });
    renderProfile(profile);
    trackEvent("player_profile_loaded", {
      metric: state.metric,
      season_count_bucket: bucketCount(profile.overview?.seasons_played, [0, 1, 2, 3, 5, 8, 12]),
      team_count_bucket: bucketCount(profile.overview?.teams_played, [0, 1, 2, 3, 5]),
      stat_count_bucket: bucketCount((profile.available_stats || []).length, [0, 1, 3, 5, 10, 15, 20])
    });
    showStatus("Player profile ready.", "success", { kicker: "Ready", autoHideMs: 2200 });
  } catch (error) {
    showStatus(error.message || "Unable to load the player profile.", "error", { kicker: "Profile unavailable" });
  }
}

elements.metricButtons.forEach((button) => {
  button.addEventListener("click", () => {
    setMetric(button.dataset.metric || "total");
  });
});

initialise();
