(function () {
  const {
    showStatusBanner = () => {},
    cycleStatusBanner = () => {},
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
  const dateFormatter = new Intl.DateTimeFormat("en-AU", {
    day: "numeric",
    month: "short",
    year: "numeric"
  });
  const dateTimeFormatter = new Intl.DateTimeFormat("en-AU", {
    day: "numeric",
    month: "short",
    hour: "numeric",
    minute: "2-digit"
  });
  const loadingMessages = [
    "Checking the latest completed fixtures…",
    "Finding the sharpest stat lines…",
    "Marking any season or archive highs…"
  ];

  function formatNumber(value) {
    if (value === null || value === undefined || value === "") {
      return "--";
    }

    const numeric = Number(value);
    if (Number.isNaN(numeric)) {
      return `${value}`;
    }

    return numberFormatter.format(numeric);
  }

  function formatDate(value, { includeTime = false } = {}) {
    if (!value) {
      return "--";
    }

    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
      return `${value}`;
    }

    return includeTime ? dateTimeFormatter.format(date) : dateFormatter.format(date);
  }

  function playerProfileUrl(playerId) {
    return `/player/${encodeURIComponent(playerId)}/`;
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

  async function fetchJson(path, query = new URLSearchParams()) {
    const suffix = query.toString();
    const response = await fetch(suffix ? `${path}?${suffix}` : path, {
      headers: {
        Accept: "application/json"
      }
    });
    const bodyText = await response.text();
    let payload = {};

    if (bodyText) {
      try {
        payload = JSON.parse(bodyText);
      } catch (error) {
        throw new Error(`Unexpected response while loading ${path}.`);
      }
    }

    if (!response.ok) {
      throw new Error(payload.error || `Request failed with status ${response.status}.`);
    }

    return payload;
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
    tableBody.replaceChildren();
    const row = document.createElement("tr");
    const cell = document.createElement("td");
    cell.colSpan = tableBody.parentElement.querySelectorAll("thead th").length;
    cell.textContent = message;
    row.appendChild(cell);
    tableBody.appendChild(row);
    syncResponsiveTable(tableBody.closest("table"));
  }

  function createCell(content, className, { primary = false } = {}) {
    const cell = document.createElement("td");
    if (className) {
      cell.className = className;
    }
    if (primary) {
      cell.dataset.stackPrimary = "true";
    }
    cell.textContent = content;
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
    link.textContent = text;
    cell.appendChild(link);
    return cell;
  }

  function createBadge(label) {
    const badge = document.createElement("span");
    badge.className = "record-badge";
    if (/archive/i.test(label)) {
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
      if (Array.isArray(fact.badges) && fact.badges.some((badge) => /archive/i.test(badge))) {
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
      time.textContent = formatDate(match.local_start_time, { includeTime: true });

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

  function standoutValueLabel(entry) {
    const statLabel = entry?.stat_label ? entry.stat_label.toLowerCase() : "value";
    return `${formatNumber(entry?.value)} ${statLabel}`;
  }

  function standoutNote(entry) {
    const notes = [];

    if (Array.isArray(entry?.badges) && entry.badges.length) {
      notes.push(entry.badges.join(" · "));
    }

    if (entry?.season && entry?.round_number) {
      notes.push(`Season ${formatNumber(entry.season)} · Round ${formatNumber(entry.round_number)}`);
    }

    if (entry?.local_start_time) {
      notes.push(formatDate(entry.local_start_time));
    }

    return notes.filter(Boolean).join(" · ") || "Round spotlight";
  }

  function renderStandoutTable(tableBody, rows, type) {
    tableBody.replaceChildren();

    if (!Array.isArray(rows) || !rows.length) {
      clearTable(tableBody, `No ${type} spotlights were available for this round.`);
      return;
    }

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
          createCell(standoutNote(entry), "standout-note")
        );
      } else {
        row.append(
          createCell(entry.title || "Spotlight", "", { primary: true }),
          createCell(entry.subject_name || "Team"),
          createCell(entry.opponent || "--"),
          createCell(standoutValueLabel(entry), "round-standout-value"),
          createCell(standoutNote(entry), "standout-note")
        );
      }

      fragment.appendChild(row);
    });

    tableBody.appendChild(fragment);
    syncResponsiveTable(tableBody.closest("table"));
  }

  function renderSummary(payload) {
    const summary = payload.summary || {};
    const roundLabel = payload.round_label || "Latest completed round";
    const seasonLabel = payload.season ? `${roundLabel}, ${formatNumber(payload.season)}` : roundLabel;

    elements.heroLabel.textContent = seasonLabel;
    elements.heading.textContent = seasonLabel;
    elements.meta.textContent = payload.round_end_time
      ? `Completed by ${formatDate(payload.round_end_time, { includeTime: true })}.`
      : "Latest completed fixtures.";
    elements.heroSummary.textContent = `${formatNumber(summary.total_matches)} matches · ${formatNumber(summary.total_goals)} goals · biggest margin ${formatNumber(summary.biggest_margin)}`;
    elements.intro.textContent = "Every completed result from the round, plus the stat lines and clean-ball moments worth keeping in view.";

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

    elements.playerCaption.textContent = `Player performances from ${seasonLabel}.`;
    elements.teamCaption.textContent = `Team performances from ${seasonLabel}.`;
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
      kicker: "Loading round recap",
      tone: "loading"
    });

    try {
      const payload = await fetchJson("/api/round-summary", buildQuery());
      renderSummary(payload);
      renderFactCards(payload.notable_facts || []);
      renderMatches(payload.matches || []);
      renderStandoutTable(elements.playerBody, payload.standout_players || [], "player");
      renderStandoutTable(elements.teamBody, payload.standout_teams || [], "team");

      showStatusBanner(elements.status, "Round recap loaded.", "success", {
        kicker: "Ready",
        autoHideMs: 2200
      });
    } catch (error) {
      applyEmptyState(error.message || "Could not load the latest completed round.");
      showStatusBanner(elements.status, error.message || "Could not load the round recap.", "error", {
        kicker: "Round unavailable"
      });
    }
  }

  loadRoundRecap();
})();
