(function () {
  const localHosts = new Set(["localhost", "127.0.0.1"]);
  const renderHosts = new Set(["netballstats.pages.dev"]);
  const configuredApiBaseUrl = localHosts.has(window.location.hostname)
    ? "http://127.0.0.1:8000"
    : (renderHosts.has(window.location.hostname) || window.location.hostname.endsWith(".pages.dev"))
      ? "https://netballstats-api.onrender.com"
      : "/api";

  window.NETBALL_STATS_CONFIG = Object.assign(
    {
      apiBaseUrl: configuredApiBaseUrl
    },
    window.NETBALL_STATS_CONFIG || {}
  );
})();
