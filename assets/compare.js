const MAX_PLAYERS = 6;
const MAX_TEAMS = 8;
const SUPER_SHOT_START_SEASON = 2020;
const DEFAULT_CHART_PALETTE = [
  "#f0c67e",
  "#79d8d0",
  "#ff9e9e",
  "#f4a0d8",
  "#d1c36b",
  "#8ac6ff",
  "#f7b267",
  "#9ad1d4"
];
const LEGACY_STAT_ALIASES = new Map([
  ["goal1", "goals"],
  ["attempts1", "goalAttempts"]
]);
const playerProfileCache = new Map();
const {
  clearChart,
  formatNumber,
  renderTrendChart
} = window.NetballCharts;
const {
  buildUrl,
  clearEmptyTableState = () => {},
  debounce = (fn) => fn,
  getCheckedValues = () => [],
  fetchJson,
  formatStatLabel = (stat) => stat,
  getThemePalette = () => [...DEFAULT_CHART_PALETTE],
  renderEmptyTableRow = () => {},
  renderSeasonCheckboxes = () => {},
  showElementLoadingStatus = () => {},
  showElementStatus = () => {},
  statPrefersLowerValue = () => false,
  setCheckedValues = () => {},
  syncResponsiveTable = () => {}
} = window.NetballStatsUI || {};
const {
  applyMetaConfig = () => {},
  bucketCount = () => "unknown",
  trackEvent = () => {}
} = window.NetballStatsTelemetry || {};
const COMPARE_LOADING_MESSAGES = [
  "Loading seasons…",
  "Lining up the records…",
  "Drawing the comparison…"
];
const COMPARE_META_LOADING_MESSAGES = [
  "Loading comparison options…",
  "Loading teams, players, and seasons…"
];

const state = {
  meta: null,
  mode: "players",
  metric: "total",
  statSelections: {
    players: "points",
    teams: "points"
  },
  selectedPlayers: [],
  selectedTeamIds: [],
  searchResults: [],
  highlightedSearchIndex: -1
};

const elements = {
  statusBanner: document.getElementById("compare-status"),
  compareForm: document.getElementById("compare-form"),
  compareSummary: document.getElementById("compare-summary"),
  heroMode: document.getElementById("compare-hero-mode"),
  heroSummary: document.getElementById("compare-hero-summary"),
  modeButtons: Array.from(document.querySelectorAll("[data-compare-mode]")),
  metricButtons: Array.from(document.querySelectorAll("[data-compare-metric]")),
  playerPickerField: document.getElementById("player-picker-field"),
  playerSearchInput: document.getElementById("compare-player-search"),
  playerSearchResults: document.getElementById("player-search-results"),
  selectedPlayerChips: document.getElementById("selected-player-chips"),
  playerSelectionMeta: document.getElementById("player-selection-meta"),
  teamPickerField: document.getElementById("team-picker-field"),
  teamChoices: document.getElementById("team-choices"),
  teamSelectionMeta: document.getElementById("team-selection-meta"),
  compareStat: document.getElementById("compare-stat"),
  seasonChoices: document.getElementById("compare-season-choices"),
  seasonActionButtons: Array.from(document.querySelectorAll("[data-compare-season-action]")),
  resetCompare: document.getElementById("reset-compare"),
  compareVerdict: document.getElementById("compare-verdict"),
  compareVerdictHeadline: document.getElementById("compare-verdict-headline"),
  compareVerdictDek: document.getElementById("compare-verdict-dek"),
  compareVerdictFacts: document.getElementById("compare-verdict-facts"),
  compareResultsMeta: document.getElementById("compare-results-meta"),
  compareChart: document.getElementById("compare-trend-chart"),
  compareTableCaption: document.getElementById("compare-table-caption"),
  compareTableHead: document.getElementById("compare-table-head"),
  compareTableBody: document.getElementById("compare-table-body"),
  compareTableFoot: document.getElementById("compare-table-foot")
};

function showStatus(message, tone = "neutral", options = {}) {
  showElementStatus(elements.statusBanner, message, tone, options);
}

function showLoadingStatus(messages, kicker) {
  showElementLoadingStatus(elements.statusBanner, messages, kicker);
}

function normaliseColour(value) {
  if (!value || typeof value !== "string") {
    return null;
  }

  const trimmed = value.trim();
  if (/^#[0-9a-f]{6}$/i.test(trimmed) || /^#[0-9a-f]{3}$/i.test(trimmed)) {
    return trimmed;
  }
  if (/^[0-9a-f]{6}$/i.test(trimmed)) {
    return `#${trimmed}`;
  }
  return null;
}

function fallbackColour(index) {
  const palette = getThemePalette(DEFAULT_CHART_PALETTE);
  return palette[index % palette.length];
}

function teamMetaById(teamId) {
  if (!state.meta || !Array.isArray(state.meta.teams)) {
    return null;
  }
  return state.meta.teams.find((team) => `${team.squad_id}` === `${teamId}`) || null;
}

function teamMetaByName(name) {
  if (!state.meta || !Array.isArray(state.meta.teams)) {
    return null;
  }
  return state.meta.teams.find((team) => team.squad_name === name) || null;
}

function resolveTeamColour(name, explicitColour, index) {
  const fromExplicit = normaliseColour(explicitColour);
  if (fromExplicit) {
    return fromExplicit;
  }

  const fromMeta = normaliseColour(teamMetaByName(name)?.squad_colour);
  return fromMeta || fallbackColour(index);
}

function currentStatCatalog() {
  if (!state.meta) {
    return [];
  }
  return state.mode === "players" ? (state.meta.player_stats || []) : (state.meta.team_stats || []);
}

function currentStatKey() {
  return state.statSelections[state.mode];
}

function currentStatLabel() {
  return elements.compareStat.selectedOptions[0]?.textContent || formatStatLabel(currentStatKey()) || "stat";
}

function currentMetricLabel() {
  return state.metric === "average" ? "average per game" : "totals";
}

function describeSeasons(seasons) {
  if (!state.meta || !(state.meta.seasons || []).length) {
    return "available seasons";
  }
  if (!seasons.length) {
    return "all seasons";
  }
  if (seasons.length === 1) {
    return `season ${seasons[0]}`;
  }
  return `${seasons.length} selected seasons`;
}

function promptMessage() {
  return state.mode === "players"
    ? "Choose at least two players."
    : "Choose at least two teams.";
}

function renderEmptyTable(message) {
  elements.compareTableHead.replaceChildren();
  elements.compareTableFoot.replaceChildren();
  renderEmptyTableRow(elements.compareTableBody, message, {
    colSpan: 2,
    rowClassName: "compare-table__placeholder"
  });
}

function clearComparison(message) {
  clearChart(elements.compareChart, message);
  renderEmptyTable(message);
  elements.compareResultsMeta.textContent = message;
  elements.compareTableCaption.textContent = message;
  if (elements.compareVerdict) {
    elements.compareVerdict.hidden = true;
  }
  if (elements.compareVerdictFacts) {
    elements.compareVerdictFacts.replaceChildren();
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
  renderSeasonCheckboxes(elements.seasonChoices, seasons, { inputName: "compare-season-choice" });
}

function renderTeamChoices(teams) {
  elements.teamChoices.replaceChildren();
  teams.forEach((team, index) => {
    const label = document.createElement("label");
    label.className = "season-choice compare-team-choice";

    const input = document.createElement("input");
    input.type = "checkbox";
    input.name = "compare-team-choice";
    input.value = `${team.squad_id}`;

    const text = document.createElement("span");
    const swatch = document.createElement("span");
    swatch.className = "team-swatch";
    swatch.setAttribute("aria-hidden", "true");
    swatch.style.setProperty("--swatch-color", resolveTeamColour(team.squad_name, team.squad_colour, index));
    const textLabel = document.createElement("span");
    textLabel.className = "compare-team-choice__text";
    textLabel.textContent = team.squad_name;
    text.append(swatch, textLabel);

    label.append(input, text);
    elements.teamChoices.appendChild(label);
  });
}

function setSelectedTeamIds(ids) {
  const selected = new Set(ids.map((value) => `${value}`));
  elements.teamChoices.querySelectorAll("input[type='checkbox']").forEach((input) => {
    input.checked = selected.has(input.value);
  });
  state.selectedTeamIds = [...selected];
}

function getSelectedTeamIds() {
  return [...elements.teamChoices.querySelectorAll("input[type='checkbox']:checked")].map((input) => input.value);
}

function selectedTeams() {
  return state.selectedTeamIds
    .map((teamId, index) => {
      const team = teamMetaById(teamId);
      if (!team) {
        return null;
      }
      return {
        id: `${team.squad_id}`,
        name: team.squad_name,
        colour: resolveTeamColour(team.squad_name, team.squad_colour, index)
      };
    })
    .filter(Boolean);
}

function selectedEntities() {
  return state.mode === "players" ? state.selectedPlayers : selectedTeams();
}

function comparisonTelemetryProperties(entityCount = selectedEntities().length) {
  return {
    mode: state.mode,
    metric: state.metric,
    stat: currentStatKey() || "unknown",
    entity_count_bucket: bucketCount(entityCount, [0, 1, 2, 3, 4, 6, 8]),
    season_count_bucket: bucketCount(getSelectedSeasons().length, [0, 1, 2, 3, 5, 8])
  };
}

function updateSelectionMeta() {
  const playerCount = state.selectedPlayers.length;
  const teamCount = state.selectedTeamIds.length;
  elements.playerSelectionMeta.textContent = `${playerCount} selected · choose 2 to ${MAX_PLAYERS}.`;
  elements.teamSelectionMeta.textContent = `${teamCount} selected · choose 2 to ${MAX_TEAMS}.`;
}

function updateBuilderSummary() {
  const entities = selectedEntities();
  const entityLabel = entities.length
    ? `${entities.length} ${state.mode}`
    : `No ${state.mode} selected`;
  const seasonLabel = describeSeasons(getSelectedSeasons());

  elements.compareSummary.textContent = `${entityLabel} • ${currentStatLabel()} • ${currentMetricLabel()} • ${seasonLabel}`;
  elements.heroMode.textContent = state.mode === "players" ? "Players" : "Teams";
  elements.heroSummary.textContent = entities.length
    ? `${entities.length} selected • ${seasonLabel} • ${currentStatLabel()} ${currentMetricLabel()}`
    : "Add names to start the head-to-head.";
}

function populateStatSelect() {
  const previousValue = state.statSelections[state.mode];
  elements.compareStat.replaceChildren();

  currentStatCatalog().forEach((stat) => {
    const option = document.createElement("option");
    option.value = stat;
    option.textContent = formatStatLabel(stat);
    elements.compareStat.appendChild(option);
  });

  const nextValue = currentStatCatalog().includes(previousValue)
    ? previousValue
    : (currentStatCatalog().includes("points") ? "points" : currentStatCatalog()[0] || "");
  state.statSelections[state.mode] = nextValue;
  elements.compareStat.value = nextValue;
}

function setMode(nextMode) {
  state.mode = nextMode === "teams" ? "teams" : "players";

  elements.modeButtons.forEach((button) => {
    const active = button.dataset.compareMode === state.mode;
    button.classList.toggle("is-active", active);
    button.classList.toggle("button--ghost", !active);
    button.setAttribute("aria-pressed", `${active}`);
  });

  elements.playerPickerField.hidden = state.mode !== "players";
  elements.teamPickerField.hidden = state.mode !== "teams";
  populateStatSelect();
  closePlayerSearchResults();
  updateBuilderSummary();
  syncUrlState();
}

function setMetric(nextMetric) {
  state.metric = nextMetric === "average" ? "average" : "total";
  elements.metricButtons.forEach((button) => {
    const active = button.dataset.compareMetric === state.metric;
    button.classList.toggle("is-active", active);
    button.classList.toggle("button--ghost", !active);
    button.setAttribute("aria-pressed", `${active}`);
  });
  updateBuilderSummary();
  syncUrlState();
}

function closePlayerSearchResults() {
  state.searchResults = [];
  state.highlightedSearchIndex = -1;
  elements.playerSearchResults.replaceChildren();
  elements.playerSearchResults.hidden = true;
  elements.playerSearchInput.setAttribute("aria-expanded", "false");
  elements.playerSearchInput.removeAttribute("aria-activedescendant");
}

function setHighlightedSearchIndex(index) {
  state.highlightedSearchIndex = index;
  [...elements.playerSearchResults.querySelectorAll(".entity-picker__option")].forEach((button, buttonIndex) => {
    const active = buttonIndex === index;
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-selected", `${active}`);
    if (active) {
      button.scrollIntoView({ block: "nearest" });
      elements.playerSearchInput.setAttribute("aria-activedescendant", button.id);
    }
  });

  if (index < 0) {
    elements.playerSearchInput.removeAttribute("aria-activedescendant");
  }
}

function renderPlayerSearchResults(results) {
  elements.playerSearchResults.replaceChildren();

  if (!results.length) {
    closePlayerSearchResults();
    return;
  }

  const fragment = document.createDocumentFragment();
  results.forEach((result, index) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "entity-picker__option";
    button.id = `player-search-option-${result.player_id}`;
    button.setAttribute("role", "option");
    button.setAttribute("aria-selected", "false");
    button.dataset.playerId = `${result.player_id}`;

    const primary = document.createElement("strong");
    primary.textContent = result.player_name;
    const secondary = document.createElement("span");
    secondary.className = "entity-picker__eyebrow";
    secondary.textContent = result.short_display_name || `Player ${result.player_id}`;

    button.append(primary, secondary);
    button.addEventListener("click", () => addSelectedPlayer(result));
    button.addEventListener("focus", () => setHighlightedSearchIndex(index));
    fragment.appendChild(button);

    if (index === 0) {
      button.classList.add("is-active");
      button.setAttribute("aria-selected", "true");
    }
  });

  elements.playerSearchResults.appendChild(fragment);
  elements.playerSearchResults.hidden = false;
  elements.playerSearchInput.setAttribute("aria-expanded", "true");
  state.searchResults = results;
  setHighlightedSearchIndex(0);
}

function renderSelectedPlayers() {
  elements.selectedPlayerChips.replaceChildren();

  state.selectedPlayers.forEach((player) => {
    const chip = document.createElement("span");
    chip.className = "entity-chip";

    if (player.colour) {
      const swatch = document.createElement("span");
      swatch.className = "team-swatch";
      swatch.setAttribute("aria-hidden", "true");
      swatch.style.setProperty("--swatch-color", player.colour);
      chip.appendChild(swatch);
    }

    const label = document.createElement("span");
    label.textContent = player.name;

    const button = document.createElement("button");
    button.type = "button";
    button.dataset.removePlayer = player.id;
    button.setAttribute("aria-label", `Remove ${player.name}`);
    button.textContent = "×";

    chip.append(label, button);
    elements.selectedPlayerChips.appendChild(chip);
  });
}

function addSelectedPlayer(result) {
  if (state.selectedPlayers.some((player) => player.id === `${result.player_id}`)) {
    closePlayerSearchResults();
    elements.playerSearchInput.value = "";
    return;
  }

  if (state.selectedPlayers.length >= MAX_PLAYERS) {
    showStatus(`Choose no more than ${MAX_PLAYERS} players.`, "error");
    return;
  }

  state.selectedPlayers.push({
    id: `${result.player_id}`,
    name: result.player_name,
    colour: null
  });
  renderSelectedPlayers();
  updateSelectionMeta();
  updateBuilderSummary();
  syncUrlState();
  elements.playerSearchInput.value = "";
  closePlayerSearchResults();
}

function removeSelectedPlayer(playerId) {
  state.selectedPlayers = state.selectedPlayers.filter((player) => player.id !== `${playerId}`);
  renderSelectedPlayers();
  updateSelectionMeta();
  updateBuilderSummary();
  syncUrlState();
}

let playerSearchSeq = 0;
const searchPlayersDebounced = debounce(async (query) => {
  const trimmed = query.trim();
  if (trimmed.length < 2) {
    closePlayerSearchResults();
    return;
  }

  const seq = ++playerSearchSeq;
  try {
    const payload = await fetchJson("/players", { search: trimmed, limit: 10 });
    if (seq !== playerSearchSeq) {
      return;
    }

    const available = (payload.data || []).filter((result) =>
      !state.selectedPlayers.some((player) => player.id === `${result.player_id}`)
    );
    renderPlayerSearchResults(available);
  } catch (error) {
    if (seq !== playerSearchSeq) {
      return;
    }
    showStatus(error.message || "Couldn't search players.", "error");
    closePlayerSearchResults();
  }
}, 200);

function syncUrlState() {
  const params = new URLSearchParams();
  params.set("mode", state.mode);
  params.set("metric", state.metric);
  if (currentStatKey()) {
    params.set("stat", currentStatKey());
  }

  const ids = state.mode === "players"
    ? state.selectedPlayers.map((player) => player.id)
    : state.selectedTeamIds;
  if (ids.length) {
    params.set("ids", ids.join(","));
  }

  const seasons = getSelectedSeasons();
  if (seasons.length) {
    params.set("seasons", seasons.join(","));
  }

  const nextUrl = params.toString()
    ? `${window.location.pathname}?${params.toString()}`
    : window.location.pathname;
  window.history.replaceState(null, "", nextUrl);
}

function defaultRecentSeasons() {
  return (state.meta?.seasons || []).slice(0, 3).map((season) => `${season}`);
}

function resetState() {
  state.mode = "players";
  state.metric = "total";
  state.selectedPlayers = [];
  state.selectedTeamIds = [];
  state.searchResults = [];
  state.highlightedSearchIndex = -1;
  state.statSelections.players = state.meta?.player_stats?.includes("points") ? "points" : (state.meta?.player_stats?.[0] || "");
  state.statSelections.teams = state.meta?.team_stats?.includes("points") ? "points" : (state.meta?.team_stats?.[0] || "");

  setMode("players");
  setMetric("total");
  setSelectedSeasons(defaultRecentSeasons());
  setSelectedTeamIds([]);
  renderSelectedPlayers();
  elements.playerSearchInput.value = "";
  updateSelectionMeta();
  updateBuilderSummary();
  closePlayerSearchResults();
  syncUrlState();
}

async function getPlayerProfile(playerId) {
  const key = `${playerId}`;
  if (!playerProfileCache.has(key)) {
    playerProfileCache.set(key, fetchJson("/player-profile", { player_id: key }));
  }
  return playerProfileCache.get(key);
}

function latestSquadName(profile) {
  const sortedSummaries = [...(profile.season_summaries || [])].sort((left, right) => Number(right.season) - Number(left.season));
  for (const summary of sortedSummaries) {
    if (Array.isArray(summary.squad_names) && summary.squad_names.length) {
      return summary.squad_names[0];
    }
  }
  return (profile.overview?.squad_names || [])[0] || "";
}

function playerDescriptorFromProfile(profile, index = 0) {
  const id = `${profile.player?.player_id || ""}`;
  const name = profile.player?.canonical_name || profile.player?.player_name || `Player ${id}`;
  const squadName = latestSquadName(profile);
  return {
    id,
    name,
    colour: resolveTeamColour(squadName, null, index)
  };
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

function selectedStatEntry(summary, statKey) {
  const map = normalizedSeasonStatMap(summary);
  const entry = map.get(statKey);
  if (entry) {
    return entry;
  }

  const legacy = LEGACY_STAT_ALIASES.get(statKey);
  return legacy ? map.get(legacy) : null;
}

function metricDisplayValue(row) {
  return state.metric === "average" ? row.average_value : row.total_value;
}

function aggregateEntityValue(rows, entityId) {
  const entityRows = rows.filter((row) => `${row.entity_id}` === `${entityId}`);
  if (!entityRows.length) {
    return null;
  }

  const totalValue = entityRows.reduce((sum, row) => sum + Number(row.total_value || 0), 0);
  const matchesPlayed = entityRows.reduce((sum, row) => sum + Number(row.matches_played || 0), 0);
  if (state.metric === "average") {
    return matchesPlayed > 0 ? totalValue / matchesPlayed : null;
  }
  return totalValue;
}

function comparisonWinnerSort(leftValue, rightValue) {
  const lowIsBetter = statPrefersLowerValue(currentStatKey());
  if (!Number.isFinite(leftValue) && !Number.isFinite(rightValue)) return 0;
  if (!Number.isFinite(leftValue)) return 1;
  if (!Number.isFinite(rightValue)) return -1;
  return lowIsBetter ? leftValue - rightValue : rightValue - leftValue;
}

function sortPreferredEntries(entries) {
  return entries.slice().sort((left, right) => {
    const byValue = comparisonWinnerSort(left.value, right.value);
    if (byValue !== 0) {
      return byValue;
    }
    return `${left.entity.name}`.localeCompare(`${right.entity.name}`);
  });
}

function preferredRow(rows) {
  return rows.reduce((best, row) => {
    if (!best) {
      return row;
    }
    return comparisonWinnerSort(Number(metricDisplayValue(row)), Number(metricDisplayValue(best))) < 0
      ? row
      : best;
  }, null);
}

function seasonLeaders(rows, entities) {
  const rowMap = new Map(rows.map((row) => [`${row.entity_id}:${row.season}`, row]));
  const seasons = [...new Set(rows.map((row) => Number(row.season)).filter((value) => Number.isFinite(value)))]
    .sort((left, right) => left - right);

  return seasons.map((season) => {
    const candidates = entities
      .map((entity) => {
        const row = rowMap.get(`${entity.id}:${season}`);
        if (!row) {
          return null;
        }
        return {
          entity,
          row,
          value: Number(metricDisplayValue(row))
        };
      })
      .filter((entry) => entry && Number.isFinite(entry.value));

    if (!candidates.length) {
      return null;
    }

    const winner = sortPreferredEntries(candidates)[0];
    return {
      season,
      entity: winner.entity,
      value: winner.value
    };
  }).filter(Boolean);
}

function createVerdictFact(label, value, detail) {
  const article = document.createElement("article");
  article.className = "compare-verdict__fact";

  const labelElement = document.createElement("span");
  labelElement.className = "compare-verdict__fact-label";
  labelElement.textContent = label;

  const valueElement = document.createElement("strong");
  valueElement.className = "compare-verdict__fact-value";
  valueElement.textContent = value;

  const detailElement = document.createElement("p");
  detailElement.className = "compare-verdict__fact-detail";
  detailElement.textContent = detail;

  article.append(labelElement, valueElement, detailElement);
  return article;
}

function renderComparisonVerdict(entities, rows) {
  if (!elements.compareVerdict || !elements.compareVerdictHeadline || !elements.compareVerdictDek || !elements.compareVerdictFacts) {
    return;
  }

  const aggregates = entities
    .map((entity) => ({
      entity,
      value: aggregateEntityValue(rows, entity.id)
    }))
    .filter((entry) => Number.isFinite(entry.value));

  if (aggregates.length < 2) {
    elements.compareVerdict.hidden = true;
    elements.compareVerdictFacts.replaceChildren();
    return;
  }

  const ranked = sortPreferredEntries(aggregates);
  const leader = ranked[0];
  const runnerUp = ranked[1];
  const gap = Math.abs(Number(leader.value) - Number(runnerUp.value));
  const gapDirection = statPrefersLowerValue(currentStatKey()) ? "lower" : "higher";
  const seasonLabel = describeSeasons(getSelectedSeasons());
  const bestSeason = preferredRow(rows);
  const winners = seasonLeaders(rows, entities);
  const leadChanges = winners.reduce((count, winner, index) => {
    if (index === 0) {
      return count;
    }
    return count + (winner.entity.id !== winners[index - 1].entity.id ? 1 : 0);
  }, 0);
  const latestWinner = winners[winners.length - 1];

  elements.compareVerdict.hidden = false;
  elements.compareVerdictHeadline.textContent = gap === 0
    ? `${leader.entity.name} and ${runnerUp.entity.name} are level on ${currentStatLabel()}.`
    : `${leader.entity.name} hold the edge in ${currentStatLabel()}.`;
  elements.compareVerdictDek.textContent = gap === 0
    ? `Across ${seasonLabel}, the selected ${currentMetricLabel()} finish dead level at the top of this matchup.`
    : `${leader.entity.name} finish ${formatNumber(gap)} ${gapDirection} than ${runnerUp.entity.name} across ${seasonLabel} on the selected ${currentMetricLabel()}.`;

  elements.compareVerdictFacts.replaceChildren(
    createVerdictFact(
      "Selected edge",
      gap === 0 ? "Level" : `${formatNumber(gap)} ${gapDirection}`,
      gap === 0
        ? `No daylight between ${leader.entity.name} and ${runnerUp.entity.name} on the selected frame.`
        : `${leader.entity.name} sits ahead of ${runnerUp.entity.name} on the aggregate comparison.`
    ),
    createVerdictFact(
      "Peak season",
      bestSeason ? `${formatNumber(metricDisplayValue(bestSeason))} in ${bestSeason.season}` : "--",
      bestSeason
        ? `${bestSeason.entity_name} posted the sharpest single-season mark in this comparison.`
        : "No single-season peak was available."
    ),
    createVerdictFact(
      "Lead changes",
      winners.length <= 1 ? "Single season" : `${leadChanges} swing${leadChanges === 1 ? "" : "s"}`,
      latestWinner
        ? `${latestWinner.entity.name} lead the latest selected season (${latestWinner.season}).`
        : "Pick more than one season to see the baton move."
    )
  );
}

async function hydratePlayersFromIds(ids) {
  const descriptors = await Promise.all(ids.map(async (playerId, index) => {
    try {
      const profile = await getPlayerProfile(playerId);
      return playerDescriptorFromProfile(profile, index);
    } catch {
      return null;
    }
  }));

  state.selectedPlayers = descriptors.filter(Boolean);
  renderSelectedPlayers();
  updateSelectionMeta();
  updateBuilderSummary();
}

async function fetchPlayerComparisonRows() {
  const selectedSeasons = new Set(getSelectedSeasons().map((season) => `${season}`));
  const profiles = await Promise.all(state.selectedPlayers.map((player) => getPlayerProfile(player.id)));

  state.selectedPlayers = profiles.map((profile, index) => playerDescriptorFromProfile(profile, index));
  renderSelectedPlayers();

  return profiles.flatMap((profile, index) => {
    const descriptor = state.selectedPlayers[index];
    return (profile.season_summaries || [])
      .filter((summary) => !selectedSeasons.size || selectedSeasons.has(`${summary.season}`))
      .map((summary) => {
        const entry = selectedStatEntry(summary, currentStatKey());
        if (!entry) {
          return null;
        }

        return {
          entity_id: descriptor.id,
          entity_name: descriptor.name,
          colour: descriptor.colour || fallbackColour(index),
          season: Number(summary.season),
          total_value: Number(entry.total_value || 0),
          average_value: Number(entry.average_value || 0),
          matches_played: Number(entry.matches_played || summary.matches_played || 0)
        };
      })
      .filter(Boolean);
  });
}

async function fetchTeamComparisonRows() {
  const teams = selectedTeams();
  const payloads = await Promise.all(teams.map((team) =>
    fetchJson("/team-season-series", {
      seasons: getSelectedSeasons(),
      team_id: team.id,
      stat: currentStatKey(),
      metric: state.metric,
      limit: 10
    })
  ));

  return payloads.flatMap((payload, index) => {
    const team = teams[index];
    return (payload.data || []).map((row) => ({
      entity_id: team.id,
      entity_name: team.name,
      colour: team.colour,
      season: Number(row.season),
      total_value: Number(row.total_value || 0),
      average_value: Number(row.average_value || 0),
      matches_played: Number(row.matches_played || 0)
    }));
  });
}

function renderComparisonChart(rows, entities) {
  renderTrendChart(elements.compareChart, rows, {
    ariaLabel: `${state.mode === "players" ? "Player" : "Team"} comparison trend chart for ${currentStatLabel()}`,
    emptyMessage: "No comparison data for these filters.",
    singleSeasonMessage: "Choose two or more seasons for a trend.",
    idAccessor: (row) => row.entity_id,
    labelAccessor: (row) => row.entity_name,
    valueAccessor: (row) => metricDisplayValue(row),
    colourAccessor: (row, index) => {
      const entity = entities.find((entry) => entry.id === `${row.entity_id}`);
      return entity?.colour || row.colour || fallbackColour(index);
    }
  });
}

function createEntityHeaderContent(entity) {
  const wrapper = document.createElement("span");
  wrapper.className = "compare-table__entity";

  if (entity.colour) {
    const swatch = document.createElement("span");
    swatch.className = "team-swatch";
    swatch.setAttribute("aria-hidden", "true");
    swatch.style.setProperty("--swatch-color", entity.colour);
    wrapper.appendChild(swatch);
  }

  if (state.mode === "players") {
    const link = document.createElement("a");
    link.href = `/player/${encodeURIComponent(entity.id)}/`;
    link.className = "table-link compare-table__entity-link";
    link.textContent = entity.name;
    wrapper.appendChild(link);
  } else {
    const text = document.createElement("span");
    text.textContent = entity.name;
    wrapper.appendChild(text);
  }

  return wrapper;
}

function renderComparisonTable(rows, entities) {
  clearEmptyTableState(elements.compareTableBody);
  const selectedSeasons = getSelectedSeasons();
  const seasons = (selectedSeasons.length
    ? selectedSeasons.map((season) => Number(season))
    : [...new Set(rows.map((row) => Number(row.season)).filter((value) => Number.isFinite(value)))])
    .sort((left, right) => left - right);

  if (!seasons.length) {
    renderEmptyTable("No comparison data for these filters.");
    return;
  }

  const rowMap = new Map(rows.map((row) => [`${row.entity_id}:${row.season}`, row]));

  elements.compareTableHead.replaceChildren();
  const headRow = document.createElement("tr");
  const seasonHead = document.createElement("th");
  seasonHead.scope = "col";
  seasonHead.textContent = "Season";
  headRow.appendChild(seasonHead);

  entities.forEach((entity) => {
    const th = document.createElement("th");
    th.scope = "col";
    th.appendChild(createEntityHeaderContent(entity));
    headRow.appendChild(th);
  });
  elements.compareTableHead.appendChild(headRow);

  elements.compareTableBody.replaceChildren();
  seasons.forEach((season) => {
    const bodyRow = document.createElement("tr");
    const seasonCell = document.createElement("th");
    seasonCell.scope = "row";
    seasonCell.className = "compare-table__season";
    seasonCell.textContent = `${season}`;
    bodyRow.appendChild(seasonCell);

    const values = entities
      .map((entity) => rowMap.get(`${entity.id}:${season}`))
      .filter(Boolean)
      .map((row) => Number(metricDisplayValue(row)))
      .filter((value) => Number.isFinite(value));
    const preferredValue = values.length
      ? (statPrefersLowerValue(currentStatKey()) ? Math.min(...values) : Math.max(...values))
      : null;

    entities.forEach((entity) => {
      const rowData = rowMap.get(`${entity.id}:${season}`);
      const cell = document.createElement("td");
      if (rowData) {
        const value = Number(metricDisplayValue(rowData));
        cell.textContent = formatNumber(value);
        if (values.length > 1 && value === preferredValue) {
          cell.classList.add("compare-table__best");
        }
      } else {
        cell.textContent = "-";
      }
      bodyRow.appendChild(cell);
    });

    elements.compareTableBody.appendChild(bodyRow);
  });

  elements.compareTableFoot.replaceChildren();
  const footRow = document.createElement("tr");
  const totalLabel = document.createElement("th");
  totalLabel.scope = "row";
  totalLabel.textContent = state.metric === "average" ? "Selected average" : "Selected total";
  footRow.appendChild(totalLabel);

  const aggregateValues = entities.map((entity) => aggregateEntityValue(rows, entity.id));
  const numericAggregates = aggregateValues.filter((value) => Number.isFinite(value));
  const preferredAggregate = numericAggregates.length
    ? (statPrefersLowerValue(currentStatKey()) ? Math.min(...numericAggregates) : Math.max(...numericAggregates))
    : null;

  aggregateValues.forEach((value) => {
    const cell = document.createElement("td");
    cell.textContent = value === null || value === undefined ? "-" : formatNumber(value);
    if (numericAggregates.length > 1 && value === preferredAggregate) {
      cell.classList.add("compare-table__best");
    }
    footRow.appendChild(cell);
  });
  elements.compareTableFoot.appendChild(footRow);
  syncResponsiveTable(elements.compareTableBody.closest("table"));
}

function renderComparisonSummary(entities, rows) {
  const entityLabel = `${entities.length} ${state.mode}`;
  const seasonLabel = describeSeasons(getSelectedSeasons());
  elements.compareResultsMeta.textContent = `${entityLabel} • ${currentStatLabel()} • ${currentMetricLabel()} • ${seasonLabel}`;
  elements.compareTableCaption.textContent = `${currentStatLabel()} comparison by season for the selected ${state.mode}.`;
  renderComparisonVerdict(entities, rows);
}

async function runComparison() {
  const entities = selectedEntities();
  if (entities.length < 2) {
    clearComparison(promptMessage());
    showStatus(promptMessage(), "error");
    return;
  }

  trackEvent("compare_submitted", comparisonTelemetryProperties(entities.length));
  showLoadingStatus(COMPARE_LOADING_MESSAGES, "Loading comparison");
  try {
    let rows;
    if (state.mode === "players") {
      rows = await fetchPlayerComparisonRows();
    } else {
      rows = await fetchTeamComparisonRows();
    }

    if (!rows.length) {
      clearComparison("No comparison data for these filters.");
      trackEvent("compare_completed", {
        ...comparisonTelemetryProperties(entities.length),
        outcome: "no_data"
      });
      showStatus("No comparison data for these filters.", "error", { kicker: "No overlap" });
      return;
    }

    const nextEntities = selectedEntities();
    renderComparisonChart(rows, nextEntities);
    renderComparisonTable(rows, nextEntities);
    renderComparisonSummary(nextEntities, rows);
    trackEvent("compare_completed", {
      ...comparisonTelemetryProperties(nextEntities.length),
      outcome: "success"
    });
    showStatus("Comparison ready.", "success", { kicker: "Ready", autoHideMs: 2200 });
  } catch (error) {
    clearComparison("Couldn't load comparison data.");
    trackEvent("compare_completed", {
      ...comparisonTelemetryProperties(entities.length),
      outcome: "error"
    });
    showStatus(error.message || "Couldn't load comparison data.", "error", { kicker: "Comparison unavailable" });
  }
}

function applyMeta(meta) {
  state.meta = meta;
  renderSeasonChoices(meta.seasons || []);
  renderTeamChoices(meta.teams || []);
  resetState();
}

async function applyUrlState() {
  const url = new URL(window.location.href);
  const mode = url.searchParams.get("mode");
  const metric = url.searchParams.get("metric");
  const stat = url.searchParams.get("stat");
  const seasons = (url.searchParams.get("seasons") || "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  const ids = (url.searchParams.get("ids") || "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);

  if (mode === "players" || mode === "teams") {
    setMode(mode);
  }
  if (metric === "total" || metric === "average") {
    setMetric(metric);
  }
  if (seasons.length) {
    setSelectedSeasons(seasons);
  }
  if (stat && currentStatCatalog().includes(stat)) {
    state.statSelections[state.mode] = stat;
    populateStatSelect();
  }

  if (state.mode === "players" && ids.length) {
    await hydratePlayersFromIds(ids);
  }
  if (state.mode === "teams" && ids.length) {
    setSelectedTeamIds(ids);
  }

  updateSelectionMeta();
  updateBuilderSummary();
  syncUrlState();
}

function initialiseEventListeners() {
  elements.compareForm.addEventListener("submit", (event) => {
    event.preventDefault();
    runComparison();
  });

  elements.modeButtons.forEach((button) => {
    button.addEventListener("click", () => {
      setMode(button.dataset.compareMode || "players");
      clearComparison(promptMessage());
    });
  });

  elements.metricButtons.forEach((button) => {
    button.addEventListener("click", () => {
      setMetric(button.dataset.compareMetric || "total");
    });
  });

  elements.compareStat.addEventListener("change", () => {
    state.statSelections[state.mode] = elements.compareStat.value;
    updateBuilderSummary();
    syncUrlState();
  });

  elements.seasonChoices.addEventListener("change", () => {
    updateBuilderSummary();
    syncUrlState();
  });

  elements.seasonActionButtons.forEach((button) => {
    button.addEventListener("click", () => {
      const action = button.dataset.compareSeasonAction;
      if (action === "all") {
        setSelectedSeasons((state.meta?.seasons || []).map((season) => `${season}`));
      } else if (action === "clear") {
        setSelectedSeasons([]);
      } else {
        setSelectedSeasons(defaultRecentSeasons());
      }
      updateBuilderSummary();
      syncUrlState();
    });
  });

  elements.teamChoices.addEventListener("change", (event) => {
    const checkedIds = getSelectedTeamIds();
    if (checkedIds.length > MAX_TEAMS) {
      event.target.checked = false;
      showStatus(`Choose no more than ${MAX_TEAMS} teams.`, "error");
      return;
    }

    state.selectedTeamIds = getSelectedTeamIds();
    updateSelectionMeta();
    updateBuilderSummary();
    syncUrlState();
  });

  elements.playerSearchInput.addEventListener("input", () => {
    searchPlayersDebounced(elements.playerSearchInput.value);
  });

  elements.playerSearchInput.addEventListener("focus", () => {
    if (state.searchResults.length) {
      elements.playerSearchResults.hidden = false;
      elements.playerSearchInput.setAttribute("aria-expanded", "true");
      setHighlightedSearchIndex(Math.max(state.highlightedSearchIndex, 0));
    }
  });

  elements.playerSearchInput.addEventListener("keydown", (event) => {
    if (!state.searchResults.length) {
      return;
    }

    if (event.key === "ArrowDown") {
      event.preventDefault();
      const nextIndex = (state.highlightedSearchIndex + 1) % state.searchResults.length;
      setHighlightedSearchIndex(nextIndex);
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      const nextIndex = state.highlightedSearchIndex <= 0
        ? state.searchResults.length - 1
        : state.highlightedSearchIndex - 1;
      setHighlightedSearchIndex(nextIndex);
    } else if (event.key === "Enter") {
      event.preventDefault();
      const activeResult = state.searchResults[state.highlightedSearchIndex];
      if (activeResult) {
        addSelectedPlayer(activeResult);
      }
    } else if (event.key === "Escape") {
      closePlayerSearchResults();
    }
  });

  elements.selectedPlayerChips.addEventListener("click", (event) => {
    const button = event.target.closest("button[data-remove-player]");
    if (!button) {
      return;
    }
    removeSelectedPlayer(button.dataset.removePlayer);
  });

  elements.playerPickerField.addEventListener("focusout", (event) => {
    window.setTimeout(() => {
      const nextFocus = event.relatedTarget || document.activeElement;
      if (!nextFocus || !elements.playerPickerField.contains(nextFocus)) {
        closePlayerSearchResults();
      }
    }, 0);
  });

  elements.resetCompare.addEventListener("click", () => {
    trackEvent("compare_reset", comparisonTelemetryProperties(selectedEntities().length));
    resetState();
    clearComparison(promptMessage());
    showStatus("");
  });

  document.addEventListener("click", (event) => {
    if (!elements.playerPickerField.contains(event.target)) {
      closePlayerSearchResults();
    }
  });
}

async function initialise() {
  clearComparison("Loading comparison options…");
  showLoadingStatus(COMPARE_META_LOADING_MESSAGES, "Loading builder");

  try {
    const meta = await fetchJson("/meta");
    applyMetaConfig(meta);
    applyMeta(meta);
    await applyUrlState();
    initialiseEventListeners();

    if (selectedEntities().length >= 2) {
      await runComparison();
    } else {
      clearComparison(promptMessage());
      showStatus("");
    }
  } catch (error) {
    showStatus(error.message || "Couldn't load comparison options.", "error", { kicker: "Builder unavailable" });
    clearComparison("Stats unavailable.");
  }
}

initialise();
