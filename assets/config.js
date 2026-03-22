(function () {
  const localHosts = new Set(["localhost", "127.0.0.1"]);
  const pagesHosts = new Set(["netballstats.pages.dev"]);
  const azureHosts = new Set(["ashy-hill-04f165c00.1.azurestaticapps.net"]);
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

  document.addEventListener("DOMContentLoaded", () => {
    document.querySelectorAll(".stack-table").forEach((table) => {
      syncResponsiveTable(table);
    });
  });

  window.NetballStatsUI = Object.assign(
    {},
    window.NetballStatsUI || {},
    {
      clearStatusTimers,
      cycleStatusBanner,
      showStatusBanner,
      syncResponsiveTable
    }
  );
})();
