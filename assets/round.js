(function () {
const {
  showStatusBanner = () => {},
  cycleStatusBanner = () => {},
  clearEmptyTableState = () => {},
  fetchJson,
  formatDate,
  formatNumber,
  formatStatLabel = (stat) => stat,
  playerProfileUrl = (playerId) => `/player/${encodeURIComponent(playerId)}/`,
  renderEmptyTableRow = () => {},
  syncResponsiveTable = () => {}
} = window.NetballStatsUI || {};

  const elements = {
    status: document.querySelector("#round-status"),
    heroLabel: document.querySelector("#round-hero-label"),
    heroSummary: document.querySelector("#round-hero-summary"),
    heading: document.querySelector("#round-heading"),
    meta: document.querySelector("#round-meta"),
    intro: document.querySelector("#round-intro"),
    summaryMatches: document.querySelector("#round-summary-matches"),
    summaryGoals: document.querySelector("#round-summary-goals"),
    summaryBiggestMargin: document.querySelector("#round-summary-biggest-margin"),
    summaryClosestMargin: document.querySelector("#round-summary-closest-margin"),
    factGrid: document.querySelector("#round-fact-grid"),
    matchGrid: document.querySelector("#round-match-grid"),
    playerBody: document.querySelector("#round-player-body"),
    teamBody: document.querySelector("#round-team-body"),
    playerTable: document.querySelector("#round-player-table"),
    teamTable: document.querySelector("#round-team-table"),
    playerCaption: document.querySelector("#round-player-caption"),
    teamCaption: document.querySelector("#round-team-caption")
  };

  if (!elements.status || !elements.factGrid || !elements.matchGrid || !elements.playerBody || !elements.teamBody) {
    return;
  }

  const numberFormatter = new Intl.NumberFormat("en-AU", {
    maximumFractionDigits: 1
  });
  const loadingMessages = [
    "Loading the latest round…",
    "Loading standout lines…",
    "Checking for records…"
  ];

  function unwrapValue(value) {
    if (Array.isArray(value)) {
      if (!value.length) {
        return null;
      }
      return value.length === 1 ? unwrapValue(value[0]) : value;
    }

    if (value && typeof value === "object" && !Array.isArray(value) && !Object.keys(value).length) {
      return null;
    }

    return value;
  }

  function buildQuery() {
    const source = new URLSearchParams(window.location.search);
    const query = new URLSearchParams();

    const season = source.get("season");
    const round = source.get("round");

    if (season) {
      query.set("season", season);
    }
    if (round) {
      query.set("round", round);
    }

    return query;
  }

  function emptyState(message, kicker) {
    const card = document.createElement("div");
    card.className = "empty-state";
    if (kicker) {
      card.dataset.kicker = kicker;
    }
    card.textContent = message;
    return card;
  }

  function clearTable(tableBody, message) {
    renderEmptyTableRow(tableBody, message);
  }

  function createCell(content, className, { primary = false } = {}) {
    const cell = document.createElement("td");
    if (className) {
      cell.className = className;
    }
    if (primary) {
      cell.dataset.stackPrimary = "true";
    }
    cell.textContent = unwrapValue(content) ?? "";
    return cell;
  }

  function createLinkCell(href, text, className, { primary = false } = {}) {
    const cell = document.createElement("td");
    if (className) {
      cell.className = className;
    }
    if (primary) {
      cell.dataset.stackPrimary = "true";
    }

    const link = document.createElement("a");
    link.href = href;
    link.className = "table-link";
    link.textContent = unwrapValue(text) ?? "";
    cell.appendChild(link);
    return cell;
  }

  function createBadge(label) {
    const badge = document.createElement("span");
    badge.className = "record-badge";
    if (/all-time/i.test(label)) {
      badge.classList.add("record-badge--archive");
    }
    badge.textContent = label;
    return badge;
  }

  function renderFactCards(facts) {
    elements.factGrid.replaceChildren();

    if (!Array.isArray(facts) || !facts.length) {
      elements.factGrid.appendChild(emptyState("No notable fact cards were available for this round.", "Recap"));
      return;
    }

    const fragment = document.createDocumentFragment();

    facts.forEach((fact) => {
      const card = document.createElement("article");
      card.className = "round-fact-card";
      if (Array.isArray(fact.badges) && fact.badges.some((badge) => /all-time/i.test(badge))) {
        card.dataset.highlight = "archive";
      }

      const title = document.createElement("h3");
      title.className = "round-fact-card__title";
      title.textContent = fact.title || "Notable fact";

      const value = document.createElement("p");
      value.className = "round-fact-card__value";
      value.textContent = fact.value || "--";

      const detail = document.createElement("p");
      detail.className = "round-fact-card__detail";
      detail.textContent = fact.detail || "";

      card.append(title, value, detail);

      if (Array.isArray(fact.badges) && fact.badges.length) {
        const badgeList = document.createElement("div");
        badgeList.className = "record-badge-list";
        fact.badges.forEach((badgeLabel) => badgeList.appendChild(createBadge(badgeLabel)));
        card.appendChild(badgeList);
      }

      fragment.appendChild(card);
    });

    elements.factGrid.appendChild(fragment);
  }

  function renderMatches(matches) {
    elements.matchGrid.replaceChildren();

    if (!Array.isArray(matches) || !matches.length) {
      elements.matchGrid.appendChild(emptyState("No completed matches were available for this round.", "Fixtures"));
      return;
    }

    const fragment = document.createDocumentFragment();

    matches.forEach((match, index) => {
      const article = document.createElement("article");
      article.className = "round-match-card";

      const top = document.createElement("div");
      top.className = "round-match-card__top";

      const kicker = document.createElement("span");
      kicker.className = "round-match-card__kicker";
      kicker.textContent = `Game ${formatNumber(match.game_number || index + 1)}`;

      const time = document.createElement("span");
      time.className = "round-match-card__time";
      time.textContent = formatDate(match.local_start_time, { includeTime: true, includeYear: false });

      top.append(kicker, time);

      const title = document.createElement("h3");
      title.className = "round-match-card__title";
      title.textContent = `${match.home_squad_name || "Home"} vs ${match.away_squad_name || "Away"}`;

      const scoreline = document.createElement("div");
      scoreline.className = "round-match-card__scoreline";

      const homeWon = Number(match.home_score) > Number(match.away_score);
      const awayWon = Number(match.away_score) > Number(match.home_score);

      const homeRow = document.createElement("div");
      homeRow.className = `round-match-card__score-row${homeWon ? " is-winner" : ""}`;
      const homeName = document.createElement("span");
      homeName.textContent = match.home_squad_name || "Home";
      const homeScore = document.createElement("strong");
      homeScore.className = "round-match-card__score";
      homeScore.textContent = formatNumber(match.home_score);
      homeRow.append(homeName, homeScore);

      const awayRow = document.createElement("div");
      awayRow.className = `round-match-card__score-row${awayWon ? " is-winner" : ""}`;
      const awayName = document.createElement("span");
      awayName.textContent = match.away_squad_name || "Away";
      const awayScore = document.createElement("strong");
      awayScore.className = "round-match-card__score";
      awayScore.textContent = formatNumber(match.away_score);
      awayRow.append(awayName, awayScore);

      scoreline.append(homeRow, awayRow);

      const meta = document.createElement("ul");
      meta.className = "round-match-card__meta";

      const resultItem = document.createElement("li");
      resultItem.textContent = Number(match.margin) === 0
        ? "Finished level."
        : `${match.winner_name || "Winner"} by ${formatNumber(match.margin)}.`;

      const venueItem = document.createElement("li");
      venueItem.textContent = match.venue_name ? `Venue: ${match.venue_name}` : "Venue unavailable.";

      meta.append(resultItem, venueItem);
      article.append(top, title, scoreline, meta);
      fragment.appendChild(article);
    });

    elements.matchGrid.appendChild(fragment);
  }

  function ordinalSuffix(n) {
    const abs = Math.abs(n);
    const mod100 = abs % 100;
    if (mod100 >= 11 && mod100 <= 13) return `${n}th`;
    switch (abs % 10) {
      case 1: return `${n}st`;
      case 2: return `${n}nd`;
      case 3: return `${n}rd`;
      default: return `${n}th`;
    }
  }

  function standoutValueLabel(entry) {
    const statKey = unwrapValue(entry?.stat);
    const statLabelValue = unwrapValue(entry?.stat_label);
    const statSource = typeof statKey === "string" && statKey
      ? statKey
      : (typeof statLabelValue === "string" ? statLabelValue : "");
    const statLabel = statSource ? formatStatLabel(statSource).toLowerCase() : "value";
    return `${formatNumber(entry?.value)} ${statLabel}`;
  }

  function createNoteCell(entry) {
    const cell = document.createElement("td");
    cell.className = "standout-note";

    const rank = unwrapValue(entry?.historical_rank);
    if (rank != null && !Number.isNaN(Number(rank))) {
      const n = Number(rank);
      const dir = unwrapValue(entry?.ranking) === "lowest" ? "lowest" : "highest";
      const rankSpan = document.createElement("span");
      rankSpan.className = "standout-note__rank";
      rankSpan.textContent = `${ordinalSuffix(n)} ${dir} all-time`;
      cell.appendChild(rankSpan);
    }

    if (Array.isArray(entry?.badges) && entry.badges.length) {
      const list = document.createElement("span");
      list.className = "standout-badge-list";
      entry.badges.forEach((label) => list.appendChild(createBadge(label)));
      cell.appendChild(list);
    }

    if (!cell.childNodes.length) {
      cell.textContent = "—";
    }

    return cell;
  }

  function standoutNote(entry) {
    const notes = [];

    const rank = unwrapValue(entry?.historical_rank);
    if (rank != null && !Number.isNaN(Number(rank))) {
      const n = Number(rank);
      const dir = unwrapValue(entry?.ranking) === "lowest" ? "lowest" : "highest";
      notes.push(`${ordinalSuffix(n)} ${dir} all-time`);
    }

    if (Array.isArray(entry?.badges) && entry.badges.length) {
      notes.push(entry.badges.join(" · "));
    }

    return notes.filter(Boolean).join(" · ") || "—";
  }

  function renderStandoutTable(tableBody, rows, type) {
    tableBody.replaceChildren();

    if (!Array.isArray(rows) || !rows.length) {
      clearTable(tableBody, `No ${type} spotlights were available for this round.`);
      return;
    }

    clearEmptyTableState(tableBody);
    const fragment = document.createDocumentFragment();

    rows.forEach((entry) => {
      const row = document.createElement("tr");

      if (type === "player") {
        row.append(
          createCell(entry.title || "Spotlight", "", { primary: true }),
          createLinkCell(playerProfileUrl(entry.player_id || ""), entry.subject_name || "Player"),
          createCell(entry.squad_name || "--"),
          createCell(entry.opponent || "--"),
          createCell(standoutValueLabel(entry), "round-standout-value"),
          createNoteCell(entry)
        );
      } else {
        row.append(
          createCell(entry.title || "Spotlight", "", { primary: true }),
          createCell(entry.subject_name || "Team"),
          createCell(entry.opponent || "--"),
          createCell(standoutValueLabel(entry), "round-standout-value"),
          createNoteCell(entry)
        );
      }

      fragment.appendChild(row);
    });

    tableBody.appendChild(fragment);
    syncResponsiveTable(tableBody.closest("table"));
  }

  function renderSummary(payload) {
    const summary = payload.summary || {};
    const roundLabel = unwrapValue(payload.round_label) || "Latest completed round";
    const seasonLabel = payload.season ? `${roundLabel}, ${payload.season}` : roundLabel;

    elements.heroLabel.textContent = seasonLabel;
    elements.heading.textContent = seasonLabel;
    elements.meta.textContent = unwrapValue(payload.round_end_time)
      ? `Completed ${formatDate(payload.round_end_time, { includeTime: true, includeYear: false })}.`
      : "Latest completed fixtures.";
    elements.heroSummary.textContent = `${formatNumber(summary.total_matches)} matches · ${formatNumber(summary.total_goals)} goals · biggest margin ${formatNumber(summary.biggest_margin)}`;
    elements.intro.textContent = "Every scoreline, standout line, and low-turnover result from the round.";

    elements.summaryMatches.textContent = formatNumber(summary.total_matches);
    elements.summaryGoals.textContent = formatNumber(summary.total_goals);
    elements.summaryBiggestMargin.textContent = summary.biggest_margin === null || summary.biggest_margin === undefined
      ? "--"
      : `${formatNumber(summary.biggest_margin)} goals`;
    elements.summaryClosestMargin.textContent = summary.closest_margin === null || summary.closest_margin === undefined
      ? "--"
      : Number(summary.closest_margin) === 0
        ? "Draw"
        : `${formatNumber(summary.closest_margin)} goal${Number(summary.closest_margin) === 1 ? "" : "s"}`;

    elements.playerCaption.textContent = `Player spotlights from ${seasonLabel}.`;
    elements.teamCaption.textContent = `Team spotlights from ${seasonLabel}.`;
  }

  function applyEmptyState(message) {
    elements.heroLabel.textContent = "Unavailable";
    elements.heroSummary.textContent = message;
    elements.heading.textContent = "Round recap unavailable";
    elements.meta.textContent = "Try again shortly.";
    elements.intro.textContent = message;
    elements.summaryMatches.textContent = "--";
    elements.summaryGoals.textContent = "--";
    elements.summaryBiggestMargin.textContent = "--";
    elements.summaryClosestMargin.textContent = "--";
    elements.factGrid.replaceChildren(emptyState(message, "Recap"));
    elements.matchGrid.replaceChildren(emptyState(message, "Fixtures"));
    clearTable(elements.playerBody, message);
    clearTable(elements.teamBody, message);
  }

  async function loadRoundRecap() {
    cycleStatusBanner(elements.status, loadingMessages, {
      kicker: "Loading recap",
      tone: "loading"
    });

    try {
      const payload = await fetchJson("/round-summary", Object.fromEntries(buildQuery()));
      renderSummary(payload);
      renderFactCards(payload.notable_facts || []);
      renderMatches(payload.matches || []);
      renderStandoutTable(elements.playerBody, payload.standout_players || [], "player");
      renderStandoutTable(elements.teamBody, payload.standout_teams || [], "team");

      showStatusBanner(elements.status, "Round recap ready.", "success", {
        kicker: "Ready",
        autoHideMs: 2200
      });
    } catch (error) {
      applyEmptyState(error.message || "Couldn't load the latest round.");
      showStatusBanner(elements.status, error.message || "Couldn't load the round recap.", "error", {
        kicker: "Recap unavailable"
      });
    }
  }

  loadRoundRecap();
})();
