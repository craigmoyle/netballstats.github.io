import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import vm from "node:vm";

class StorageStub {
  constructor() {
    this.values = new Map();
  }

  getItem(key) {
    return this.values.has(key) ? this.values.get(key) : null;
  }

  setItem(key, value) {
    this.values.set(key, String(value));
  }

  removeItem(key) {
    this.values.delete(key);
  }
}

async function flushMicrotasks(iterations = 6) {
  for (let index = 0; index < iterations; index += 1) {
    await Promise.resolve();
  }
}

async function loadTelemetry({ search = "" } = {}) {
  const localStorage = new StorageStub();
  const sessionStorage = new StorageStub();
  const domListeners = new Map();
  const fetchCalls = [];
  const historyCalls = [];
  const location = {
    href: `https://example.com/query/${search}`,
    origin: "https://example.com",
    pathname: "/query/",
    search
  };

  const fetchStub = async (input, options = {}) => {
    const url = typeof input === "string" ? input : input.toString();
    fetchCalls.push({ url, options });

    if (url === "https://example.com/api/meta") {
      return {
        ok: true,
        async json() {
          return { telemetry: { browser_enabled: true } };
        }
      };
    }

    if (url === "https://example.com/api/telemetry") {
      return { ok: true };
    }

    throw new Error(`Unexpected fetch to ${url}`);
  };

  const context = {
    console,
    Blob,
    URL,
    URLSearchParams,
    fetch: fetchStub,
    navigator: {
      language: "en-AU",
      platform: "MacIntel",
      userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4)",
      sendBeacon: undefined
    },
    document: {
      referrer: "",
      addEventListener(eventName, handler) {
        domListeners.set(eventName, handler);
      }
    },
    window: {
      NETBALL_STATS_CONFIG: {},
      crypto: { randomUUID: () => "11111111-1111-4111-8111-111111111111" },
      location,
      history: {
        replaceState(_state, _title, url) {
          historyCalls.push(url);
        }
      },
      localStorage,
      sessionStorage,
      innerWidth: 1200
    },
    Intl,
    Promise,
    setTimeout,
    clearTimeout
  };

  context.window.fetch = fetchStub;
  context.window.navigator = context.navigator;
  context.window.document = context.document;
  context.window.URL = URL;
  context.window.URLSearchParams = URLSearchParams;
  context.window.Blob = Blob;
  context.window.Intl = Intl;
  context.window.setTimeout = setTimeout;
  context.window.clearTimeout = clearTimeout;

  vm.createContext(context);
  const source = readFileSync(path.join(process.cwd(), "assets", "telemetry.js"), "utf8");
  vm.runInContext(source, context);

  const ready = domListeners.get("DOMContentLoaded");
  assert.equal(typeof ready, "function", "Expected telemetry bootstrap to register a DOMContentLoaded handler.");
  ready();
  await flushMicrotasks();

  return {
    fetchCalls,
    historyCalls,
    localStorage,
    telemetry: context.window.NetballStatsTelemetry
  };
}

const bootWithInternalOverride = await loadTelemetry({ search: "?telemetryTraffic=internal" });
assert.equal(
  typeof bootWithInternalOverride.telemetry.getTrafficClass,
  "function",
  "Expected telemetry helpers to expose getTrafficClass()."
);
assert.equal(
  bootWithInternalOverride.telemetry.getTrafficClass(),
  "internal",
  "Expected hidden query parameter to persist an internal traffic class override."
);
assert.equal(
  bootWithInternalOverride.localStorage.getItem("netballstats.telemetry.traffic_class"),
  "internal",
  "Expected hidden query parameter to save the traffic class in localStorage."
);
assert.equal(
  bootWithInternalOverride.historyCalls.length,
  1,
  "Expected hidden telemetry override query parameter to be removed from the URL after persistence."
);

const pageViewCall = bootWithInternalOverride.fetchCalls.find((call) => call.url === "https://example.com/api/telemetry");
assert.ok(pageViewCall, "Expected telemetry bootstrap to send a page view.");
const pageViewBody = JSON.parse(pageViewCall.options.body);
assert.equal(
  pageViewBody.payload.context.traffic_class,
  "internal",
  "Expected page view telemetry context to include the persisted traffic class."
);

const defaultBoot = await loadTelemetry();
assert.equal(defaultBoot.telemetry.getTrafficClass(), "public", "Expected public traffic by default.");
defaultBoot.telemetry.setTrafficClass("testing");
defaultBoot.telemetry.trackEvent("compare_completed");
await flushMicrotasks();

const lastEventCall = defaultBoot.fetchCalls.filter((call) => call.url === "https://example.com/api/telemetry").at(-1);
assert.ok(lastEventCall, "Expected event tracking to post telemetry.");
const lastEventBody = JSON.parse(lastEventCall.options.body);
assert.equal(
  lastEventBody.payload.context.traffic_class,
  "testing",
  "Expected tracked events to include an updated traffic class override."
);

defaultBoot.telemetry.clearTrafficClassOverride();
assert.equal(defaultBoot.telemetry.getTrafficClass(), "public", "Expected clearing the override to restore public traffic.");

console.log("Telemetry traffic class checks passed.");
