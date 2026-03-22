(function () {
  const SDK_URL = "https://js.monitor.azure.com/scripts/b/ai.3.gbl.min.js";
  const state = {
    appInsights: null,
    browserConfig: null,
    initPromise: null,
    metaPromise: null,
    pageViewSent: false,
    queue: []
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
    return trimString(pathname.replace(/\//g, "-").replace(/^-+|-+$/g, ""), 60) || "unknown-page";
  }

  function pageViewPayload(extraProperties = {}) {
    const pathname = sanitisePathname();
    return {
      name: pageTypeFromPath(pathname),
      uri: `${window.location.origin}${pathname === "/" ? "/" : `${pathname}/`}`,
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
        state.appInsights.trackEvent({ name: entry.payload.name }, entry.payload.properties);
      }
    });
  }

  function enqueue(kind, payload) {
    state.queue.push({ kind, payload });
    void ensureClient();
  }

  function bootAppInsights(connectionString) {
    return new Promise((resolve, reject) => {
      if (window.appInsights && typeof window.appInsights.trackEvent === "function") {
        resolve(window.appInsights);
        return;
      }

      const timeoutId = window.setTimeout(() => {
        reject(new Error("Telemetry SDK initialization timed out."));
      }, 15000);

      !(function (cfg) {
        function onInit() {
          cfg.onInit && cfg.onInit(instance);
        }

        let lowerCase;
        let crossOriginAttr;
        let postMethod;
        let sdkInstanceName;
        let instanceName;
        let instance;
        const win = window;
        const doc = document;
        const location = win.location;
        const scriptTag = "script";
        const ingestionEndpointField = "ingestionendpoint";
        const disableExceptionTracking = "disableExceptionTracking";
        const devicePrefix = "ai.device.";
        "instrumentationKey"[(lowerCase = "toLowerCase")]();
        crossOriginAttr = "crossOrigin";
        postMethod = "POST";
        sdkInstanceName = "appInsightsSDK";
        instanceName = cfg.name || "appInsights";
        (cfg.name || win[sdkInstanceName]) && (win[sdkInstanceName] = instanceName);
        instance = win[instanceName] || function (snippetConfig) {
          let loadFailed = false;
          let reportedFailure = false;
          const queueingInstance = {
            initialize: true,
            queue: [],
            sv: "8",
            version: 2,
            config: snippetConfig
          };

          function telemetryEnvelope(iKey, envelopeType) {
            const tags = {};
            const device = "Browser";

            function pad(value) {
              const asString = `${value}`;
              return asString.length === 1 ? `0${asString}` : asString;
            }

            tags[`${devicePrefix}id`] = device[lowerCase]();
            tags[`${devicePrefix}type`] = device;
            tags["ai.operation.name"] = location && location.pathname || "_unknown_";
            tags["ai.internal.sdkVersion"] = `javascript:snippet_${queueingInstance.sv || queueingInstance.version}`;

            const time = new Date();
            return {
              time: `${time.getUTCFullYear()}-${pad(time.getUTCMonth() + 1)}-${pad(time.getUTCDate())}T${pad(time.getUTCHours())}:${pad(time.getUTCMinutes())}:${pad(time.getUTCSeconds())}.${(time.getUTCMilliseconds() / 1e3).toFixed(3).slice(2, 5)}Z`,
              iKey,
              name: `Microsoft.ApplicationInsights.${iKey.replace(/-/g, "")}.${envelopeType}`,
              sampleRate: 100,
              tags,
              data: {
                baseData: {
                  ver: 2
                }
              },
              ver: undefined,
              seq: "1",
              aiDataContract: undefined
            };
          }

          let activeNavigator;
          let integrityMatch;
          let integrityHandler;
          let xhr;
          let xhrResponseHandler;
          let loadRetryIndex = -1;
          let loadRetryCount = 0;
          const fallbackHosts = [
            "js.monitor.azure.com",
            "js.cdn.applicationinsights.io",
            "js.cdn.monitor.azure.com",
            "js0.cdn.applicationinsights.io",
            "js0.cdn.monitor.azure.com",
            "js2.cdn.applicationinsights.io",
            "js2.cdn.monitor.azure.com",
            "az416426.vo.msecnd.net"
          ];
          let sdkUrl = snippetConfig.url || cfg.src;
          const retry = function () {
            return loadSdk(sdkUrl, null);
          };

          function loadSdk(nextUrl, integrityValue) {
            if ((activeNavigator = navigator) && (~(activeNavigator = (activeNavigator.userAgent || "").toLowerCase()).indexOf("msie") || ~activeNavigator.indexOf("trident/")) && ~nextUrl.indexOf("ai.3")) {
              nextUrl = nextUrl.replace(/(\/)(ai\.3\.)([^\d]*)$/, function (matched, slash, version, suffix) {
                return `${slash}ai.2${suffix}`;
              });
            }

            if (cfg.cr !== false) {
              for (let index = 0; index < fallbackHosts.length; index += 1) {
                if (nextUrl.indexOf(fallbackHosts[index]) > 0) {
                  loadRetryIndex = index;
                  break;
                }
              }
            }

            function loadFailedHandler() {
              let iKey;
              let endpoint;
              let messageEnvelope;
              let exceptionEnvelope;

              queueingInstance.queue = [];
              if (reportedFailure) {
                return;
              }

              if (loadRetryIndex >= 0 && loadRetryCount + 1 < fallbackHosts.length) {
                const fallbackIndex = (loadRetryIndex + loadRetryCount + 1) % fallbackHosts.length;
                loadRetryCount += 1;
                addScript(nextUrl.replace(/^(.*\/\/)([\w\.]*)(\/.*)$/, function (matched, prefix, host, path) {
                  return `${prefix}${fallbackHosts[fallbackIndex]}${path}`;
                }));
                return;
              }

              loadFailed = reportedFailure = true;
              if (cfg.dle === true) {
                return;
              }

              const parsedConnectionString = function () {
                const fields = {};
                const connection = snippetConfig.connectionString;
                if (connection) {
                  const parts = connection.split(";");
                  for (let index = 0; index < parts.length; index += 1) {
                    const values = parts[index].split("=");
                    if (values.length === 2) {
                      fields[values[0][lowerCase]()] = values[1];
                    }
                  }
                }

                if (!fields[ingestionEndpointField]) {
                  const endpointSuffix = fields.endpointsuffix;
                  const locationName = endpointSuffix ? fields.location : null;
                  fields[ingestionEndpointField] = `https://${locationName ? `${locationName}.` : ""}dc.${endpointSuffix || "services.visualstudio.com"}`;
                }

                return fields;
              }();

              iKey = parsedConnectionString.instrumentationkey || snippetConfig.instrumentationKey || "";
              endpoint = parsedConnectionString[ingestionEndpointField];
              endpoint = endpoint && endpoint.slice(-1) === "/" ? endpoint.slice(0, -1) : endpoint;
              endpoint = (endpoint ? `${endpoint}/v2/track` : snippetConfig.endpointUrl);
              endpoint = snippetConfig.userOverrideEndpointUrl || endpoint;

              exceptionEnvelope = telemetryEnvelope(iKey, "Exception");
              exceptionEnvelope.data.baseType = "ExceptionData";
              exceptionEnvelope.data.baseData.exceptions = [{
                typeName: "SDKLoadFailed",
                message: "SDK LOAD Failure: Failed to load Application Insights SDK script (See stack for details)".replace(/\./g, "-"),
                hasFullStack: false,
                stack: `SDK LOAD Failure: Failed to load Application Insights SDK script (See stack for details)\nSnippet failed to load [${nextUrl}] -- Telemetry is disabled\nHelp Link: https://go.microsoft.com/fwlink/?linkid=2128109\nHost: ${(location && location.pathname) || "_unknown_"}\nEndpoint: ${endpoint}`,
                parsedStack: []
              }];

              messageEnvelope = telemetryEnvelope(iKey, "Message");
              messageEnvelope.data.baseType = "MessageData";
              messageEnvelope.data.baseData.message = `AI (Internal): 99 message:"${`SDK LOAD Failure: Failed to load Application Insights SDK script (See stack for details) (${nextUrl})`.replace(/\"/g, "")}"`;
              messageEnvelope.data.baseData.properties = { endpoint };

              const payload = [exceptionEnvelope, messageEnvelope];
              if (JSON) {
                const send = win.fetch;
                if (send && !cfg.useXhr) {
                  send(endpoint, { method: postMethod, body: JSON.stringify(payload), mode: "cors" });
                } else if (XMLHttpRequest) {
                  const fallbackXhr = new XMLHttpRequest();
                  fallbackXhr.open(postMethod, endpoint);
                  fallbackXhr.setRequestHeader("Content-type", "application/json");
                  fallbackXhr.send(JSON.stringify(payload));
                }
              }
            }

            function loadHandler(value, skipRetry) {
              if (!reportedFailure) {
                setTimeout(function () {
                  if (!skipRetry && !queueingInstance.core) {
                    loadFailedHandler();
                  }
                }, 500);
              }
              loadFailed = false;
            }

            function addScript(url) {
              const sdkScript = doc.createElement(scriptTag);
              sdkScript.src = url;
              if (integrityValue) {
                sdkScript.integrity = integrityValue;
              }
              sdkScript.setAttribute("data-ai-name", instanceName);
              const attrValue = cfg[crossOriginAttr];
              if ((attrValue || attrValue === "") && typeof sdkScript[crossOriginAttr] !== "undefined") {
                sdkScript[crossOriginAttr] = attrValue;
              }
              sdkScript.onload = loadHandler;
              sdkScript.onerror = loadFailedHandler;
              sdkScript.onreadystatechange = function (event, completed) {
                if (sdkScript.readyState === "loaded" || sdkScript.readyState === "complete") {
                  loadHandler(0, completed);
                }
              };
              if (cfg.ld && cfg.ld < 0) {
                doc.getElementsByTagName("head")[0].appendChild(sdkScript);
              } else {
                setTimeout(function () {
                  doc.getElementsByTagName(scriptTag)[0].parentNode.appendChild(sdkScript);
                }, cfg.ld || 0);
              }
              return sdkScript;
            }

            addScript(nextUrl);
          }

          if (cfg.sri && (integrityMatch = sdkUrl.match(/^((http[s]?:\/\/.*\/)\w+(\.\d+){1,5})\.(([\w]+\.){0,2}js)$/)) && integrityMatch.length === 6) {
            const integrityUrl = `${integrityMatch[1]}.integrity.json`;
            const extensionKey = `@${integrityMatch[4]}`;
            const fetchFn = window.fetch;

            integrityHandler = function (response) {
              if (!response.ext || !response.ext[extensionKey] || !response.ext[extensionKey].file) {
                throw new Error("Error Loading JSON response");
              }

              const integrity = response.ext[extensionKey].integrity || null;
              sdkUrl = `${integrityMatch[2]}${response.ext[extensionKey].file}`;
              loadSdk(sdkUrl, integrity);
            };

            if (fetchFn && !cfg.useXhr) {
              fetchFn(integrityUrl, { method: "GET", mode: "cors" })
                .then(function (response) {
                  return response.json().catch(function () {
                    return {};
                  });
                })
                .then(integrityHandler)
                .catch(retry);
            } else if (XMLHttpRequest) {
              xhr = new XMLHttpRequest();
              xhr.open("GET", integrityUrl);
              xhr.onreadystatechange = function () {
                if (xhr.readyState !== XMLHttpRequest.DONE) {
                  return;
                }

                if (xhr.status === 200) {
                  try {
                    integrityHandler(JSON.parse(xhr.responseText));
                    return;
                  } catch (error) {
                    reject(error);
                  }
                }

                retry();
              };
              xhr.send();
            }
          } else if (sdkUrl) {
            retry();
          }

          try {
            queueingInstance.cookie = doc.cookie;
          } catch (error) {
            // Ignore cookie access issues.
          }

          function proxy(methods) {
            while (methods.length) {
              (function (methodName) {
                queueingInstance[methodName] = function () {
                  const args = arguments;
                  if (!loadFailed) {
                    queueingInstance.queue.push(function () {
                      queueingInstance[methodName].apply(queueingInstance, args);
                    });
                  }
                };
              })(methods.pop());
            }
          }

          let extensionConfig;
          let exceptionCallback;
          proxy([
            "trackEvent",
            "trackPageView",
            "trackException",
            "trackTrace",
            "trackDependencyData",
            "trackMetric",
            "trackPageViewPerformance",
            "startTrackPage",
            "stopTrackPage",
            "startTrackEvent",
            "stopTrackEvent",
            "addTelemetryInitializer",
            "setAuthenticatedUserContext",
            "clearAuthenticatedUserContext",
            "flush"
          ]);
          queueingInstance.SeverityLevel = {
            Verbose: 0,
            Information: 1,
            Warning: 2,
            Error: 3,
            Critical: 4
          };
          extensionConfig = (snippetConfig.extensionConfig || {}).ApplicationInsightsAnalytics || {};
          if (snippetConfig[disableExceptionTracking] !== true && extensionConfig[disableExceptionTracking] !== true) {
            proxy([`_${(exceptionCallback = "onerror")}`]);
            const originalOnError = win[exceptionCallback];
            win[exceptionCallback] = function (message, url, lineNumber, columnNumber, error) {
              const handled = originalOnError && originalOnError(message, url, lineNumber, columnNumber, error);
              if (handled !== true) {
                queueingInstance[`_${exceptionCallback}`]({
                  message,
                  url,
                  lineNumber,
                  columnNumber,
                  error,
                  evt: win.event
                });
              }
              return handled;
            };
            snippetConfig.autoExceptionInstrumented = true;
          }

          return queueingInstance;
        }(cfg.cfg);

        (win[instanceName] = instance).queue && instance.queue.length === 0 ? instance.queue.push(onInit) : onInit();
      })({
        src: SDK_URL,
        crossOrigin: "anonymous",
        onInit: function (sdk) {
          window.clearTimeout(timeoutId);
          resolve(sdk);
        },
        cfg: {
          connectionString,
          disableAjaxTracking: true,
          disableFetchTracking: true,
          disableCorrelationHeaders: true,
          enableAutoRouteTracking: false
        }
      });
    });
  }

  function applyMetaConfig(meta) {
    const telemetry = meta?.telemetry;
    if (!telemetry || telemetry.browser_enabled !== true || !telemetry.connection_string) {
      return;
    }

    state.browserConfig = {
      connectionString: telemetry.connection_string
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
        if (!browserConfig?.connectionString) {
          return null;
        }

        const appInsights = await bootAppInsights(browserConfig.connectionString);
        if (!appInsights) {
          return null;
        }

        state.appInsights = appInsights;
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
    const payload = {
      name,
      properties: sanitiseProperties({
        page_type: pageTypeFromPath(),
        ...properties
      })
    };

    if (state.appInsights) {
      state.appInsights.trackEvent({ name: payload.name }, payload.properties);
      return;
    }

    enqueue("event", payload);
  }

  document.addEventListener("DOMContentLoaded", () => {
    trackPageView();
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
