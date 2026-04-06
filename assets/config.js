(function () {
  const localHosts = new Set(["localhost", "127.0.0.1"]);
  const pagesHosts = new Set(["netballstats.pages.dev"]);
  const azureHosts = new Set(["ashy-hill-04f165c00.1.azurestaticapps.net", "statsball.net", "www.statsball.net"]);
  const configuredApiBaseUrl = localHosts.has(window.location.hostname)
    ? "http://127.0.0.1:8000"
    : (pagesHosts.has(window.location.hostname)
      || window.location.hostname.endsWith(".pages.dev"))
      ? "https://netballstats-api.onrender.com"
      : (azureHosts.has(window.location.hostname)
        || window.location.hostname.endsWith(".azurestaticapps.net"))
        ? "/api"
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

  function statPrefersLowerValue(stat) {
    return LOW_IS_BETTER_STATS.has(cleanLabel(stat));
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

  document.addEventListener("DOMContentLoaded", () => {
    document.querySelectorAll(".stack-table").forEach((table) => {
      syncResponsiveTable(table);
    });
  });

  window.NetballStatsUI = Object.assign(
    {},
    window.NetballStatsUI || {},
    {
      buildUrl,
      clearStatusTimers,
      cycleStatusBanner,
      fetchJson,
      formatNumber,
      formatStatLabel,
      showStatusBanner,
      statPrefersLowerValue,
      syncResponsiveTable
    }
  );
})();
