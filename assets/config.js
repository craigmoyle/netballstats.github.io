(function () {
  const localHosts = new Set(["localhost", "127.0.0.1"]);
  const configuredApiBaseUrl = localHosts.has(window.location.hostname)
    ? "http://127.0.0.1:8000"
    : "/api";

  window.NETBALL_STATS_CONFIG = Object.assign(
    {
      apiBaseUrl: configuredApiBaseUrl
    },
    window.NETBALL_STATS_CONFIG || {}
  );

  function cleanLabel(text) {
    return `${text || ""}`.replace(/\s+/g, " ").trim();
  }

  const STAT_LABEL_OVERRIDES = Object.freeze({
    attempt_from_zone1: "Zone 1 Attempts",
    attempt_from_zone2: "Zone 2 Attempts",
    attempts1: "1 Point Goal Attempts",
    attempts2: "Super Shot Attempts",
    centrePassReceives: "Centre Pass Receives",
    contactPenalties: "Contacts",
    defensiveRebounds: "Defensive Rebounds",
    deflectionPossessionGain: "Deflection Possession Gains",
    deflectionWithGain: "Deflections (with Gain)",
    deflectionWithNoGain: "Deflections (no Gain)",
    disposals: "Disposals",
    feedWithAttempt: "Feeds with Attempt",
    feeds: "Feeds into Circle",
    gain: "Gains",
    gamesPlayed: "Games Played",
    generalPlayTurnovers: "General Play Turnovers",
    goal1: "1 Point Goals",
    goal2: "Super Shots",
    goal_from_zone1: "Zone 1 Goals",
    goal_from_zone2: "Zone 2 Goals",
    goalAssists: "Goal Assists",
    goalAttempts: "Goal Attempts",
    goals1: "1 Point Goals",
    goals2: "Super Goals",
    goalsFromCentrePass: "Goals from Centre Pass",
    goalsFromGain: "Goals from Gain",
    goalsFromTurnovers: "Goals from Turnovers",
    interceptPassThrown: "Intercept Passes Thrown",
    missedGoalTurnover: "Missed Goal Turnovers",
    netPoints: "Net Points",
    obstructionPenalties: "Obstructions",
    offensiveRebounds: "Offensive Rebounds",
    points: "Points",
    possessionChanges: "Possession Changes",
    possessions: "Possessions",
    secondPhaseReceive: "Second Phase Receives",
    timeInPossession: "Time in Possession",
    tossUpWin: "Toss Up Wins",
    turnoverHeld: "Turnovers Held",
    unforcedTurnovers: "Unforced Turnovers"
  });

  const STAT_ABBREV_OVERRIDES = Object.freeze({
    attempt_from_zone1: "Z1 Att",
    attempt_from_zone2: "Z2 Att",
    attempts1: "1Pt Att",
    attempts2: "SS Att",
    centrePassReceives: "CPR",
    contactPenalties: "Contacts",
    defensiveRebounds: "Def Reb",
    deflectionPossessionGain: "DPG",
    deflectionWithGain: "DWG",
    deflectionWithNoGain: "DWNG",
    deflections: "Defl",
    disposals: "Disp",
    feedWithAttempt: "FwA",
    feeds: "Feeds",
    gain: "Gains",
    gamesPlayed: "GP",
    generalPlayTurnovers: "GPT",
    goal1: "1Pt G",
    goal2: "SS",
    goal_from_zone1: "Z1 G",
    goal_from_zone2: "Z2 G",
    goalAssists: "G Ast",
    goalAttempts: "G Att",
    goalMisses: "G Miss",
    goals: "Goals",
    goals1: "1Pt G",
    goals2: "SS",
    goalsFromCentrePass: "GfCP",
    goalsFromGain: "GfG",
    goalsFromTurnovers: "GfTO",
    intercepts: "INT",
    interceptPassThrown: "IPT",
    missedGoalTurnover: "MGT",
    netPoints: "Net Pts",
    obstructionPenalties: "OBS",
    offensiveRebounds: "Off Reb",
    penalties: "Pen",
    pickups: "PKU",
    points: "Pts",
    possessionChanges: "PC",
    possessions: "Poss",
    rebounds: "Reb",
    secondPhaseReceive: "2P Rec",
    timeInPossession: "TiP",
    tossUpWin: "Toss",
    turnoverHeld: "TO Held",
    turnovers: "TO",
    unforcedTurnovers: "UTO",
  });

  const LOW_IS_BETTER_STATS = new Set([
    "contactPenalties",
    "generalPlayTurnovers",
    "interceptPassThrown",
    "obstructionPenalties",
    "unforcedTurnovers"
  ]);

  function formatStatLabel(stat) {
    const normalized = cleanLabel(stat);
    if (!normalized) {
      return "";
    }

    if (STAT_LABEL_OVERRIDES[normalized]) {
      return STAT_LABEL_OVERRIDES[normalized];
    }

    const spaced = normalized
      .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
      .replace(/_/g, " ");

    return cleanLabel(spaced.replace(/\b[a-z]/g, (match) => match.toUpperCase()));
  }

  function formatStatAbbrev(stat) {
    const normalized = cleanLabel(stat);
    if (!normalized) {
      return "";
    }
    return STAT_ABBREV_OVERRIDES[normalized] || formatStatLabel(normalized);
  }

  function statPrefersLowerValue(stat) {
    return LOW_IS_BETTER_STATS.has(cleanLabel(stat));
  }

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

  const statusState = new WeakMap();

  function clearStatusTimers(element) {
    const activeState = statusState.get(element);
    if (!activeState) {
      return;
    }
    if (activeState.intervalId) {
      window.clearInterval(activeState.intervalId);
    }
    if (activeState.timeoutId) {
      window.clearTimeout(activeState.timeoutId);
    }
    statusState.delete(element);
  }

  function renderStatusBanner(element, message, tone = "neutral", options = {}) {
    if (!element) {
      return;
    }
    element.textContent = message || "";
    if (message) {
      element.dataset.tone = tone;
      if (options.kicker) {
        element.dataset.kicker = options.kicker;
      } else {
        element.removeAttribute("data-kicker");
      }
      element.role = tone === "error" ? "alert" : "status";
      element.hidden = false;
    } else {
      element.hidden = true;
      element.removeAttribute("data-kicker");
      element.removeAttribute("data-tone");
    }
  }

  function showStatusBanner(element, message, tone = "neutral", options = {}) {
    clearStatusTimers(element);
    renderStatusBanner(element, message, tone, options);

    if (!element || !message || !options.autoHideMs) {
      return;
    }

    const timeoutId = window.setTimeout(() => {
      renderStatusBanner(element, "");
      clearStatusTimers(element);
    }, options.autoHideMs);

    statusState.set(element, { timeoutId });
  }

  function cycleStatusBanner(element, messages, options = {}) {
    if (!element) {
      return;
    }

    const sequence = (messages || []).map((message) => `${message || ""}`.trim()).filter(Boolean);
    if (!sequence.length) {
      showStatusBanner(element, options.fallbackMessage || "", options.tone || "neutral", options);
      return;
    }

    clearStatusTimers(element);

    let index = 0;
    renderStatusBanner(element, sequence[index], options.tone || "loading", options);

    if (sequence.length === 1) {
      return;
    }

    const intervalId = window.setInterval(() => {
      index = (index + 1) % sequence.length;
      renderStatusBanner(element, sequence[index], options.tone || "loading", options);
    }, options.intervalMs || 1800);

    statusState.set(element, { intervalId });
  }

  function showElementStatus(element, message, tone = "neutral", options = {}) {
    showStatusBanner(element, message || "", tone, options);
  }

  function showElementLoadingStatus(element, messages, kicker, options = {}) {
    cycleStatusBanner(element, messages, {
      ...options,
      tone: "loading",
      kicker
    });
  }

  function syncResponsiveTable(table) {
    if (!table) {
      return;
    }

    const labels = Array.from(table.querySelectorAll("thead tr:first-child > th, thead tr:first-child > td"))
      .map((cell) => cleanLabel(cell.textContent));

    ["tbody", "tfoot"].forEach((section) => {
      table.querySelectorAll(`${section} tr`).forEach((row) => {
        const cells = Array.from(row.children).filter((cell) => cell.matches("th, td"));
        const hasManualPrimary = cells.some((cell) => cell.dataset.stackPrimary === "true");

        cells.forEach((cell, index) => {
          const colSpan = Number(cell.getAttribute("colspan") || 1);
          if (colSpan > 1) {
            cell.removeAttribute("data-label");
            cell.removeAttribute("data-stack-primary");
            return;
          }

          const label = labels[index];
          if (label) {
            cell.dataset.label = label;
          } else {
            cell.removeAttribute("data-label");
          }

          if (hasManualPrimary) {
            if (cell.dataset.stackPrimary !== "true") {
              cell.removeAttribute("data-stack-primary");
            }
            return;
          }

          if (index === 0) {
            cell.dataset.stackPrimary = "true";
          } else {
            cell.removeAttribute("data-stack-primary");
          }
        });
      });
    });
  }

  const apiBaseUrl = (window.NETBALL_STATS_CONFIG.apiBaseUrl || "/api").replace(/\/$/, "");
  const defaultTimeoutMs = 30000;
  const fmtInt = new Intl.NumberFormat("en-AU", { maximumFractionDigits: 0 });
  const fmtDecimal = new Intl.NumberFormat("en-AU", { maximumFractionDigits: 2 });
  const dateFormatter = new Intl.DateTimeFormat("en-AU", {
    day: "numeric",
    month: "short",
    year: "numeric"
  });
  const dateTimeFormatter = new Intl.DateTimeFormat("en-AU", {
    day: "numeric",
    month: "short",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit"
  });
  const dateTimeFormatterNoYear = new Intl.DateTimeFormat("en-AU", {
    day: "numeric",
    month: "short",
    hour: "numeric",
    minute: "2-digit"
  });

  function buildUrl(path, params = {}) {
    const url = new URL(`${apiBaseUrl}${path}`, window.location.href);
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
    const timeoutId = window.setTimeout(() => controller.abort(), defaultTimeoutMs);

    try {
      const response = await fetch(buildUrl(path, params), {
        headers: {
          Accept: "application/json"
        },
        signal: controller.signal
      });

      const payload = await response.json().catch(() => ({ error: "Unexpected server response." }));
      if (!response.ok) {
        const message = Array.isArray(payload.error) ? payload.error.join(" ") : payload.error;
        throw new Error(message || `Request failed with status ${response.status}.`);
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

  function formatNumber(value) {
    if (value === null || value === undefined || value === "") {
      return "-";
    }

    const numeric = Number(value);
    if (!Number.isFinite(numeric)) {
      return value;
    }

    return (Number.isInteger(numeric) ? fmtInt : fmtDecimal).format(numeric);
  }

  function formatDate(value, { includeTime = false, includeYear = true } = {}) {
    value = unwrapValue(value);

    if (!value) {
      return "--";
    }

    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
      return `${value}`;
    }

    if (includeTime) {
      return (includeYear ? dateTimeFormatter : dateTimeFormatterNoYear).format(date);
    }

    return dateFormatter.format(date);
  }

  function playerProfileUrl(playerId) {
    playerId = unwrapValue(playerId);
    return `/player/${encodeURIComponent(playerId)}/`;
  }

  function debounce(fn, delay = 200) {
    let timeoutId = null;
    return function (...args) {
      window.clearTimeout(timeoutId);
      timeoutId = window.setTimeout(() => fn.apply(this, args), delay);
    };
  }

  function getCheckedValues(container) {
    if (!container) {
      return [];
    }

    return [...container.querySelectorAll("input[type='checkbox']:checked")]
      .map((input) => input.value);
  }

  function setCheckedValues(container, values) {
    if (!container) {
      return;
    }

    const selected = new Set((values || []).map((value) => `${value}`));
    container.querySelectorAll("input[type='checkbox']").forEach((input) => {
      input.checked = selected.has(input.value);
    });
  }

  function renderCheckboxChoices(container, values = [], {
    className = "season-choice",
    inputName = "",
    selectedValues = [],
    onChange = null,
    renderLabel = (value) => `${value}`
  } = {}) {
    if (!container) {
      return;
    }

    const selected = new Set((selectedValues || []).map((value) => `${value}`));
    container.replaceChildren();
    const fragment = document.createDocumentFragment();

    values.forEach((value, index) => {
      const label = document.createElement("label");
      label.className = className;

      const input = document.createElement("input");
      input.type = "checkbox";
      if (inputName) {
        input.name = inputName;
      }
      input.value = `${value}`;
      input.checked = selected.has(input.value);

      const text = document.createElement("span");
      text.textContent = renderLabel(value, index);

      label.append(input, text);
      fragment.appendChild(label);

      if (onChange) {
        input.addEventListener("change", onChange);
      }
    });

    container.appendChild(fragment);
  }

  function renderSeasonCheckboxes(container, seasons = [], options = {}) {
    renderCheckboxChoices(container, seasons, {
      className: "season-choice",
      ...options
    });
  }

  function normalisePathname(pathname = "/") {
    const raw = `${pathname || "/"}`.trim() || "/";
    if (raw === "/") {
      return raw;
    }
    const withLeadingSlash = raw.startsWith("/") ? raw : `/${raw}`;
    return withLeadingSlash.endsWith("/") ? withLeadingSlash : `${withLeadingSlash}/`;
  }

  function navRouteForPath(pathname = "/") {
    const normalized = normalisePathname(pathname);
    if (normalized.startsWith("/player/")) {
      return "/players/";
    }
    return normalized;
  }

  function markCurrentNavLinks(root = document) {
    if (!root?.querySelectorAll || !window.location) {
      return;
    }

    const currentRoute = navRouteForPath(window.location.pathname);
    root.querySelectorAll(".page-nav__link").forEach((link) => {
      const href = link.getAttribute("href");
      if (!href) {
        link.removeAttribute("aria-current");
        return;
      }

      let targetRoute = "";
      try {
        targetRoute = navRouteForPath(new URL(href, window.location.origin).pathname);
      } catch {
        link.removeAttribute("aria-current");
        return;
      }

      if (targetRoute === currentRoute && currentRoute !== "/") {
        link.setAttribute("aria-current", "page");
      } else {
        link.removeAttribute("aria-current");
      }
    });
  }

  function clearEmptyTableState(tableBody) {
    if (!tableBody) {
      return;
    }

    const table = tableBody.closest("table");
    const wrapper = tableBody.closest(".table-wrapper");
    table?.classList.remove("is-empty");
    wrapper?.classList.remove("is-empty");
  }

  function renderEmptyTableRow(tableBody, message, {
    colSpan,
    kicker = "",
    rowClassName = ""
  } = {}) {
    if (!tableBody) {
      return;
    }

    const table = tableBody.closest("table");
    const wrapper = tableBody.closest(".table-wrapper");
    table?.classList.add("is-empty");
    wrapper?.classList.add("is-empty");

    const row = document.createElement("tr");
    if (rowClassName) {
      row.className = rowClassName;
    }

    const cell = document.createElement("td");
    cell.colSpan = colSpan || tableBody.parentElement?.querySelectorAll("thead th").length || 1;
    cell.className = "empty-state";
    if (kicker) {
      cell.dataset.kicker = kicker;
    }
    cell.textContent = message;
    row.appendChild(cell);
    tableBody.replaceChildren(row);
    syncResponsiveTable(table || tableBody.closest("table"));
  }

  function getThemePalette(fallback = []) {
    if (!window.getComputedStyle || !document?.documentElement) {
      return Array.isArray(fallback) ? [...fallback] : [];
    }

    const style = window.getComputedStyle(document.documentElement);
    const palette = [];
    for (let index = 1; index <= 8; index += 1) {
      const value = style.getPropertyValue(`--chart-palette-${index}`).trim();
      if (value) {
        palette.push(value);
      }
    }

    if (palette.length) {
      return palette;
    }

    return Array.isArray(fallback) ? [...fallback] : [];
  }

  document.addEventListener("DOMContentLoaded", () => {
    markCurrentNavLinks();
    document.querySelectorAll(".stack-table").forEach((table) => {
      syncResponsiveTable(table);
    });
  });

  window.NetballStatsUI = Object.assign(
    {},
    window.NetballStatsUI || {},
    {
      buildUrl,
      clearEmptyTableState,
      clearStatusTimers,
      cycleStatusBanner,
      debounce,
      fetchJson,
      formatDate,
      formatNumber,
      formatStatAbbrev,
      formatStatLabel,
      getThemePalette,
      getCheckedValues,
      markCurrentNavLinks,
      showStatusBanner,
      showElementLoadingStatus,
      showElementStatus,
      playerProfileUrl,
      renderCheckboxChoices,
      renderEmptyTableRow,
      renderSeasonCheckboxes,
      setCheckedValues,
      statPrefersLowerValue,
      syncResponsiveTable
    }
  );
})();
