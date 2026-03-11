(function () {
  const localHosts = new Set(["localhost", "127.0.0.1"]);
  const frontendHosts = new Set(["netballstats.pages.dev", "craigmoyle.github.io"]);
  const configuredApiBaseUrl = localHosts.has(window.location.hostname)
    ? "http://127.0.0.1:8000"
    : (frontendHosts.has(window.location.hostname)
      || window.location.hostname.endsWith(".pages.dev")
      || window.location.hostname.endsWith(".github.io"))
      ? "https://netballstats-api.onrender.com"
      : "/api";

  window.NETBALL_STATS_CONFIG = Object.assign(
    {
      apiBaseUrl: configuredApiBaseUrl
    },
    window.NETBALL_STATS_CONFIG || {}
  );
})();
