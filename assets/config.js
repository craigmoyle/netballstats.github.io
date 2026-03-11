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
})();
