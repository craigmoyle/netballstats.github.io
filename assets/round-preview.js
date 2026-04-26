(function () {
  const {
    showStatusBanner = () => {},
    cycleStatusBanner = () => {},
    fetchJson,
    formatDate,
    unwrapValue = (value) => value
  } = window.NetballStatsUI || {};

  const elements = {
    status: document.querySelector("#round-preview-status"),
    heroLabel: document.querySelector("#round-preview-hero-label"),
    heroSummary: document.querySelector("#round-preview-hero-summary"),
    heading: document.querySelector("#round-preview-heading"),
    matchGrid: document.querySelector("#round-preview-match-grid")
  };

  if (!elements.status || !elements.matchGrid) {
    return;
  }

  const loadingMessages = [
    "Loading upcoming fixtures\u2026",
    "Fetching head-to-head records\u2026",
    "Checking recent form\u2026"
  ];

  function isPlainObject(value) {
    return !!value && typeof value === "object" && !Array.isArray(value);
  }

  function cardLabel(text) {
    const span = document.createElement("span");
    span.className = "card-label";
    span.textContent = text;
    return span;
  }

  function createTeamHeading(fixture, side) {
    const teamName = side === "home" ? fixture.home_team : fixture.away_team;
    const logoUrl = side === "home" ? fixture.home_logo_url : fixture.away_logo_url;

    const div = document.createElement("div");
    div.className = "round-preview-team";

    if (logoUrl) {
      const img = document.createElement("img");
      img.className = "round-preview-team__logo";
      img.src = logoUrl;
      img.alt = teamName || "";
      img.width = 44;
      img.height = 44;
      div.appendChild(img);
    } else {
      const fallback = document.createElement("span");
      fallback.className = "round-preview-team__logo round-preview-team__logo--fallback";
      fallback.textContent = teamName ? teamName.slice(0, 2).toUpperCase() : "?";
      fallback.setAttribute("aria-hidden", "true");
      div.appendChild(fallback);
    }

    const name = document.createElement("span");
    name.textContent = teamName || "Team";
    div.appendChild(name);
    return div;
  }

  function renderFormChips(results, teamName, streak) {
    const row = document.createElement("div");
    row.className = "form-row";

    const label = document.createElement("span");
    label.className = "form-row__label";
    label.textContent = teamName;
    row.appendChild(label);

    const right = document.createElement("span");
    right.className = "form-row__right";

    const chips = document.createElement("span");
    chips.className = "form-chips";
    // Reverse so oldest result is leftmost (reads as a timeline)
    const ordered = [...(results || [])].reverse();
    ordered.forEach((r) => {
      const chip = document.createElement("span");
      chip.className = `form-chip form-chip--${String(r || "d").toLowerCase()}`;
      chip.textContent = r || "?";
      chip.setAttribute("aria-label", r === "W" ? "Win" : r === "L" ? "Loss" : "Draw");
      chips.appendChild(chip);
    });
    right.appendChild(chips);

    if (streak && streak.summary) {
      const note = document.createElement("span");
      note.className = "form-streak";
      note.textContent = streak.summary;
      right.appendChild(note);
    }

    row.appendChild(right);
    return row;
  }

  function normalizeMatch(match) {
    if (!isPlainObject(match)) {
      return null;
    }

    return {
      fixture: isPlainObject(match.fixture) ? match.fixture : {},
      headToHead: isPlainObject(match.head_to_head) ? match.head_to_head : null,
      recentForm: isPlainObject(match.recent_form) ? match.recent_form : null,
      streaks: isPlainObject(match.streaks) ? match.streaks : null,
      factCards: Array.isArray(match.fact_cards) ? match.fact_cards : [],
      playerWatch: Array.isArray(match.player_watch) ? match.player_watch : []
    };
  }

  function renderMatches(matches) {
    elements.matchGrid.replaceChildren();

    if (!Array.isArray(matches) || !matches.length) {
      const empty = document.createElement("div");
      empty.className = "empty-state";
      const text = document.createTextNode("No upcoming fixtures are available. ");
      const link = document.createElement("a");
      link.href = "/round/";
      link.className = "table-link";
      link.textContent = "See the latest completed round.";
      empty.append(text, link);
      elements.matchGrid.appendChild(empty);
      return;
    }

    const fragment = document.createDocumentFragment();

    matches.forEach((match) => {
      const safeMatch = normalizeMatch(match);
      if (!safeMatch) return;

      const { fixture, headToHead, recentForm, streaks, factCards, playerWatch } = safeMatch;

      const article = document.createElement("article");
      article.className = "round-preview-card";

      // Header: teams + vs + kickoff time
      const header = document.createElement("div");
      header.className = "round-preview-card__header";

      header.appendChild(createTeamHeading(fixture, "home"));

      const vs = document.createElement("div");
      vs.className = "round-preview-card__vs";
      const vsText = document.createElement("span");
      vsText.textContent = "vs";
      const timeEl = document.createElement("span");
      timeEl.className = "round-preview-card__time";
      timeEl.textContent = formatDate
        ? formatDate(fixture.local_start_time, { includeTime: true, includeYear: false }) || "TBC"
        : fixture.local_start_time || "TBC";
      vs.append(vsText, timeEl);

      header.appendChild(vs);
      header.appendChild(createTeamHeading(fixture, "away"));
      article.appendChild(header);

      const details = document.createElement("div");
      details.className = "round-preview-card__details";

      // Context: venue + head-to-head series record
      const contextBlock = document.createElement("div");
      contextBlock.className = "round-preview-card__context";

      if (fixture.venue) {
        const venueLine = document.createElement("div");
        venueLine.className = "round-preview-card__venue";
        venueLine.append(cardLabel("Location"), document.createTextNode(fixture.venue));
        contextBlock.appendChild(venueLine);
      }

      if (headToHead && headToHead.summary) {
        const h2hLine = document.createElement("div");
        h2hLine.className = "round-preview-card__h2h";
        h2hLine.append(cardLabel("Series"), document.createTextNode(headToHead.summary));
        contextBlock.appendChild(h2hLine);
      }

      if (contextBlock.children.length) {
        details.appendChild(contextBlock);
      }

      // Form: W/L chip rows per team, with streak summary inline
      const homeResults = recentForm && recentForm.home && Array.isArray(recentForm.home.results)
        ? recentForm.home.results : null;
      const awayResults = recentForm && recentForm.away && Array.isArray(recentForm.away.results)
        ? recentForm.away.results : null;

      const extras = document.createElement("details");
      extras.className = "round-preview-card__extras";
      const extrasSummary = document.createElement("summary");
      extrasSummary.className = "round-preview-card__extras-summary";
      extrasSummary.textContent = "Form and player watch";
      extras.appendChild(extrasSummary);

      if (homeResults || awayResults) {
        const formSection = document.createElement("div");
        formSection.className = "round-preview-card__form";

        if (homeResults && homeResults.length) {
          formSection.appendChild(renderFormChips(homeResults, fixture.home_team, streaks && streaks.home));
        }
        if (awayResults && awayResults.length) {
          formSection.appendChild(renderFormChips(awayResults, fixture.away_team, streaks && streaks.away));
        }

        if (formSection.children.length) {
          extras.appendChild(formSection);
        }
      }

      // Amber callout: last meeting highlight + sparse history note
      if (factCards.length) {
        const facts = document.createElement("div");
        facts.className = "round-preview-card__fact";
        factCards.forEach((factText) => {
          if (!factText) return;
          const p = document.createElement("p");
          p.textContent = factText;
          facts.appendChild(p);
        });
        if (facts.children.length) {
          details.appendChild(facts);
        }
      }

      // Player watch: one team heading per group, facts listed beneath
      if (playerWatch.length) {
        const watchList = document.createElement("ul");
        watchList.className = "round-preview-card__watch-list";

        // Group consecutive notes by team
        const groups = [];
        playerWatch.forEach((note) => {
          const summary = unwrapValue(note?.summary);
          if (!note || !summary) return;
          const team = unwrapValue(note.team) || null;
          const last = groups[groups.length - 1];
          if (last && last.team === team) {
            last.notes.push(summary);
          } else {
            groups.push({ team, notes: [summary] });
          }
        });

        groups.forEach(({ team, notes }) => {
          const item = document.createElement("li");
          item.className = "round-preview-card__watch-group";
          if (team) {
            const heading = document.createElement("span");
            heading.className = "card-label card-label--watch";
            heading.textContent = team;
            item.appendChild(heading);
          }
          const factList = document.createElement("ul");
          factList.className = "round-preview-card__watch-facts";
          notes.forEach((text) => {
            const fact = document.createElement("li");
            fact.textContent = text;
            factList.appendChild(fact);
          });
          item.appendChild(factList);
          watchList.appendChild(item);
        });

        if (watchList.children.length) {
          extras.appendChild(watchList);
        }
      }

      if (extras.children.length > 1) {
        details.appendChild(extras);
      }

      article.appendChild(details);
      fragment.appendChild(article);
    });

    elements.matchGrid.appendChild(fragment);
  }

  async function loadRoundPreview() {
    cycleStatusBanner(elements.status, loadingMessages, {
      kicker: "Loading preview",
      tone: "loading"
    });

    try {
      const params = {};
      const source = new URLSearchParams(window.location.search);
      const season = source.get("season");
      if (season) {
        params.season = season;
      }

      const payload = await fetchJson("/round-preview-summary", params);

      const roundLabel = payload.round_label || "Upcoming round";
      const seasonLabel = payload.season ? `${roundLabel}, ${payload.season}` : roundLabel;

      if (elements.heroLabel) {
        elements.heroLabel.textContent = seasonLabel;
      }
      if (elements.heading) {
        elements.heading.textContent = seasonLabel;
      }
      if (elements.heroSummary) {
        elements.heroSummary.textContent = payload.round_intro || "Fixtures and context for the next round.";
      }

      renderMatches(payload.matches || []);

      showStatusBanner(elements.status, "Round preview ready.", "success", {
        kicker: "Ready",
        autoHideMs: 2200
      });
    } catch (error) {
      const message = error.message || "Couldn't load the round preview.";

      if (elements.heroLabel) {
        elements.heroLabel.textContent = "Unavailable";
      }
      if (elements.heroSummary) {
        elements.heroSummary.textContent = message;
      }
      if (elements.heading) {
        elements.heading.textContent = "Round preview unavailable";
      }

      elements.matchGrid.replaceChildren();

      showStatusBanner(elements.status, message, "error", {
        kicker: "Preview unavailable"
      });
    }
  }

  loadRoundPreview();
})();
