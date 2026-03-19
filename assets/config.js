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

  // Reveal animations: use IntersectionObserver so content is visible
  // immediately — not gated on API calls completing.
  var revealObserver = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (entry.isIntersecting) {
        entry.target.classList.add("is-visible");
        revealObserver.unobserve(entry.target);
      }
    });
  }, { threshold: 0.04, rootMargin: "0px 0px 80px 0px" });

  document.querySelectorAll(".reveal").forEach(function (el) {
    revealObserver.observe(el);
  });
})();
