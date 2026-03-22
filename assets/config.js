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
      syncResponsiveTable
    }
  );
})();
