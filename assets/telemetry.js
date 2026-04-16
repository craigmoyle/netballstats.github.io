(function () {
  const state = {
    appInsights: null,
    browserConfig: null,
    initPromise: null,
    metaPromise: null,
    pageViewSent: false,
    queue: [],
    userId: null,
    sessionId: null,
    operationId: null,
    deviceContext: null,
    deviceContextPromise: null
  };

  function apiBaseUrl() {
    return (window.NETBALL_STATS_CONFIG?.apiBaseUrl || "/api").replace(/\/$/, "");
  }

  function buildApiUrl(path) {
    return new URL(`${apiBaseUrl()}${path}`, window.location.href);
  }

  function trimString(value, maxLength = 120) {
    return `${value || ""}`.replace(/\s+/g, " ").trim().slice(0, maxLength);
  }

  function sanitiseProperties(properties = {}) {
    const output = {};

    Object.entries(properties).forEach(([key, value]) => {
      if (value === undefined || value === null || value === "") {
        return;
      }

      if (typeof value === "boolean") {
        output[key] = value ? "true" : "false";
        return;
      }

      if (typeof value === "number" && Number.isFinite(value)) {
        output[key] = `${value}`;
        return;
      }

      if (Array.isArray(value)) {
        const joined = trimString(value.join(","), 120);
        if (joined) {
          output[key] = joined;
        }
        return;
      }

      const stringValue = trimString(value, 120);
      if (stringValue) {
        output[key] = stringValue;
      }
    });

    return output;
  }

  function createId(prefix = "t") {
    if (window.crypto && typeof window.crypto.randomUUID === "function") {
      return `${prefix}-${window.crypto.randomUUID()}`;
    }
    return `${prefix}-${Math.random().toString(36).slice(2, 10)}${Date.now().toString(36)}`;
  }

  function getStorage(name) {
    try {
      return window[name] || null;
    } catch (error) {
      return null;
    }
  }

  function getOrCreateStorageValue(storageName, key, prefix) {
    const storage = getStorage(storageName);
    if (!storage) {
      return createId(prefix);
    }

    const existingValue = storage.getItem(key);
    if (existingValue) {
      return existingValue;
    }

    const createdValue = createId(prefix);
    storage.setItem(key, createdValue);
    return createdValue;
  }

  function ensureTelemetryIds() {
    if (!state.userId) {
      state.userId = getOrCreateStorageValue("localStorage", "netballstats.telemetry.user_id", "u");
    }
    if (!state.sessionId) {
      state.sessionId = getOrCreateStorageValue("sessionStorage", "netballstats.telemetry.session_id", "s");
    }
    if (!state.operationId) {
      state.operationId = createId("op");
    }

    return {
      userId: state.userId,
      sessionId: state.sessionId,
      operationId: state.operationId
    };
  }

  function referrerHost() {
    if (!document.referrer) {
      return "";
    }

    try {
      return new URL(document.referrer).host;
    } catch (error) {
      return "";
    }
  }

  function viewportBucket() {
    const width = Number(window.innerWidth || 0);
    if (!Number.isFinite(width) || width <= 0) {
      return "unknown";
    }
    if (width < 640) {
      return "xs";
    }
    if (width < 960) {
      return "sm";
    }
    if (width < 1280) {
      return "md";
    }
    return "lg";
  }

  function normaliseOsName(value = "") {
    const lower = `${value || ""}`.toLowerCase();

    if (!lower) {
      return "";
    }
    if (lower.includes("mac")) {
      return "macOS";
    }
    if (lower.includes("iphone") || lower.includes("ipad") || lower.includes("ipod") || lower.includes("ios")) {
      return "iOS";
    }
    if (lower.includes("android")) {
      return "Android";
    }
    if (lower.includes("windows")) {
      return "Windows";
    }
    if (lower.includes("cros") || lower.includes("chrome os")) {
      return "Chrome OS";
    }
    if (lower.includes("linux")) {
      return "Linux";
    }

    return trimString(value, 40);
  }

  function normaliseOsVersion(value = "") {
    return trimString(`${value || ""}`.replace(/_/g, "."), 40);
  }

  function formatDeviceOsVersion(deviceOs, version) {
    if (!deviceOs) {
      return version;
    }
    if (!version) {
      return deviceOs;
    }
    if (version.toLowerCase().startsWith(deviceOs.toLowerCase())) {
      return trimString(version, 80);
    }
    return trimString(`${deviceOs} ${version}`, 80);
  }

  function inferDeviceContextFromNavigator() {
    const platform = trimString(navigator.platform || navigator.userAgentData?.platform || "", 40);
    const userAgent = navigator.userAgent || "";
    let deviceOs = normaliseOsName(platform);
    let version = "";

    if (/android/i.test(userAgent)) {
      deviceOs = "Android";
      version = normaliseOsVersion(userAgent.match(/Android\s+([\d._]+)/i)?.[1] || "");
    } else if (/iPhone|iPad|iPod/i.test(userAgent)) {
      deviceOs = "iOS";
      version = normaliseOsVersion(userAgent.match(/OS\s+([\d_]+)/i)?.[1] || "");
    } else if (/Mac OS X/i.test(userAgent) || deviceOs === "macOS") {
      deviceOs = "macOS";
      version = normaliseOsVersion(userAgent.match(/Mac OS X\s+([\d_]+)/i)?.[1] || "");
    } else if (/Windows NT/i.test(userAgent) || deviceOs === "Windows") {
      deviceOs = "Windows";
      version = normaliseOsVersion(userAgent.match(/Windows NT\s+([\d.]+)/i)?.[1] || "");
    } else if (/CrOS/i.test(userAgent)) {
      deviceOs = "Chrome OS";
      version = normaliseOsVersion(userAgent.match(/CrOS [^ ]+ ([\d.]+)/i)?.[1] || "");
    } else if (/Linux/i.test(userAgent) || deviceOs === "Linux") {
      deviceOs = "Linux";
    }

    return {
      deviceType: "Browser",
      deviceOs,
      deviceOsVersion: formatDeviceOsVersion(deviceOs, version)
    };
  }

  function currentDeviceContext() {
    if (!state.deviceContext) {
      state.deviceContext = inferDeviceContextFromNavigator();
    }

    return state.deviceContext;
  }

  async function ensureDeviceContext() {
    if (state.deviceContextPromise) {
      return state.deviceContextPromise;
    }

    const fallback = currentDeviceContext();
    const uaData = navigator.userAgentData;
    if (!uaData || typeof uaData.getHighEntropyValues !== "function") {
      state.deviceContextPromise = Promise.resolve(fallback);
      return state.deviceContextPromise;
    }

    state.deviceContextPromise = uaData
      .getHighEntropyValues(["platform", "platformVersion"])
      .then((values) => {
        const deviceOs = normaliseOsName(values?.platform || uaData.platform || fallback.deviceOs);
        const version = normaliseOsVersion(values?.platformVersion || "");
        state.deviceContext = {
          deviceType: "Browser",
          deviceOs: deviceOs || fallback.deviceOs,
          deviceOsVersion: formatDeviceOsVersion(deviceOs || fallback.deviceOs, version) || fallback.deviceOsVersion
        };
        return state.deviceContext;
      })
      .catch(() => fallback);

    return state.deviceContextPromise;
  }

  function telemetryContext() {
    const ids = ensureTelemetryIds();
    const device = currentDeviceContext();
    const timezone = typeof Intl !== "undefined"
      ? Intl.DateTimeFormat().resolvedOptions().timeZone || ""
      : "";

    return {
      user_id: ids.userId,
      session_id: ids.sessionId,
      operation_id: ids.operationId,
      viewport_bucket: viewportBucket(),
      browser_language: trimString(navigator.language || "", 20),
      referrer_host: trimString(referrerHost(), 80),
      timezone: trimString(timezone, 60),
      device_type: trimString(device.deviceType || "Browser", 20),
      device_os: trimString(device.deviceOs || "", 40),
      device_os_version: trimString(device.deviceOsVersion || "", 80)
    };
  }

  function bucketCount(value, breakpoints = [0, 1, 2, 3, 5, 10, 25, 50]) {
    const numeric = Number(value);
    if (!Number.isFinite(numeric) || numeric < 0) {
      return "unknown";
    }

    if (numeric <= breakpoints[0]) {
      return `${breakpoints[0]}`;
    }

    for (let index = 1; index < breakpoints.length; index += 1) {
      const lower = breakpoints[index - 1];
      const upper = breakpoints[index];
      if (numeric === upper) {
        return `${upper}`;
      }
      if (numeric > lower && numeric < upper) {
        return `${lower + 1}-${upper - 1}`;
      }
    }

    return `${breakpoints[breakpoints.length - 1]}+`;
  }

  function sanitisePathname(pathname = window.location.pathname) {
    if (!pathname) {
      return "/";
    }

    return pathname
      .replace(/\/player\/\d+(?=\/|$)/, "/player/:id")
      .replace(/\/+$/, "") || "/";
  }

  function pageTypeFromPath(pathname = sanitisePathname()) {
    if (pathname === "/") {
      return "archive-home";
    }
    if (pathname === "/round") {
      return "round-recap";
    }
    if (pathname === "/query") {
      return "ask-stats";
    }
    if (pathname === "/compare") {
      return "compare";
    }
    if (pathname === "/players") {
      return "player-directory";
    }
    if (pathname === "/player/:id") {
      return "player-profile";
    }
    if (pathname === "/scoreflow") {
      return "scoreflow-archive";
    }
    return trimString(pathname.replace(/\//g, "-").replace(/^-+|-+$/g, ""), 60) || "unknown-page";
  }

  function pageViewPayload(extraProperties = {}) {
    const pathname = sanitisePathname();
    return {
      name: pageTypeFromPath(pathname),
      uri: `${window.location.origin}${pathname === "/" ? "/" : `${pathname}/`}`,
      context: telemetryContext(),
      properties: sanitiseProperties({
        page_type: pageTypeFromPath(pathname),
        ...extraProperties
      })
    };
  }

  function flushQueue() {
    if (!state.appInsights || !state.queue.length) {
      return;
    }

    const pending = state.queue.splice(0, state.queue.length);
    pending.forEach((entry) => {
      if (entry.kind === "pageView") {
        state.appInsights.trackPageView(entry.payload);
      } else if (entry.kind === "event") {
        state.appInsights.trackEvent(
          { name: entry.payload.name },
          entry.payload.properties,
          entry.payload.context
        );
      }
    });
  }

  function sendTelemetry(kind, payload) {
    const body = JSON.stringify({ kind, payload });
    const endpoint = buildApiUrl("/telemetry").toString();

    if (navigator.sendBeacon) {
      const beacon = new Blob([body], { type: "application/json" });
      if (navigator.sendBeacon(endpoint, beacon)) {
        return;
      }
    }

    void fetch(endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body,
      keepalive: true
    }).catch(() => {});
  }

  function enqueue(kind, payload) {
    state.queue.push({ kind, payload });
    void ensureClient();
  }

  function applyMetaConfig(meta) {
    const telemetry = meta?.telemetry;
    if (!telemetry || telemetry.browser_enabled !== true) {
      return;
    }

    state.browserConfig = {
      enabled: true
    };
    state.metaPromise = Promise.resolve(state.browserConfig);
    if (!state.appInsights) {
      state.initPromise = null;
      void ensureClient();
    }
  }

  async function fetchMetaConfig() {
    if (state.browserConfig) {
      return state.browserConfig;
    }

    if (!state.metaPromise) {
      state.metaPromise = fetch(buildApiUrl("/meta"), {
        headers: {
          Accept: "application/json"
        }
      })
        .then((response) => response.ok ? response.json() : null)
        .then((meta) => {
          applyMetaConfig(meta);
          return state.browserConfig;
        })
        .catch(() => null);
    }

    return state.metaPromise;
  }

  async function ensureClient() {
    if (state.appInsights) {
      return state.appInsights;
    }

    if (!state.initPromise) {
      state.initPromise = (async () => {
        const browserConfig = state.browserConfig || await fetchMetaConfig();
        if (!browserConfig?.enabled) {
          return null;
        }

        state.appInsights = {
          trackPageView(payload) {
            sendTelemetry("pageView", payload);
          },
          trackEvent(eventDescriptor, properties) {
            sendTelemetry("event", {
              name: eventDescriptor?.name || "",
              properties: properties || {},
              context: arguments[2] || {}
            });
          },
          flush() {}
        };
        window.appInsights = state.appInsights;
        flushQueue();
        return state.appInsights;
      })().catch(() => {
        state.initPromise = null;
        return null;
      });
    }

    return state.initPromise;
  }

  function trackPageView(properties = {}) {
    if (state.pageViewSent) {
      return;
    }

    state.pageViewSent = true;
    const payload = pageViewPayload(properties);

    if (state.appInsights) {
      state.appInsights.trackPageView(payload);
      return;
    }

    enqueue("pageView", payload);
  }

  function trackEvent(name, properties = {}) {
    void ensureDeviceContext();
    const payload = {
      name,
      context: telemetryContext(),
      properties: sanitiseProperties({
        page_type: pageTypeFromPath(),
        ...properties
      })
    };

    if (state.appInsights) {
      state.appInsights.trackEvent({ name: payload.name }, payload.properties, payload.context);
      return;
    }

    enqueue("event", payload);
  }

  document.addEventListener("DOMContentLoaded", () => {
    void ensureDeviceContext().finally(() => {
      trackPageView();
    });
    void ensureClient();
  });

  window.NetballStatsTelemetry = Object.assign(
    {},
    window.NetballStatsTelemetry || {},
    {
      applyMetaConfig,
      bucketCount,
      pageTypeFromPath,
      sanitisePathname,
      trackEvent,
      trackPageView
    }
  );
})();
