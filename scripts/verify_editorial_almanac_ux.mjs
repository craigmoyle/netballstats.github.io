import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const distDir = path.resolve(scriptDir, "..", "dist");
const assetDir = path.join(distDir, "assets");

function readFingerprintedAsset(assetName) {
  const parsed = path.parse(assetName);
  const pattern = new RegExp(`^${parsed.name}\\.[a-f0-9]{10}\\${parsed.ext}$`);
  const match = readdirSync(assetDir).find((entry) => pattern.test(entry));
  assert.ok(match, `Expected built asset for ${assetName}`);
  return readFileSync(path.join(assetDir, match), "utf8");
}

const indexHtml = readFileSync(path.join(distDir, "index.html"), "utf8");
const playerHtml = readFileSync(path.join(distDir, "player", "index.html"), "utf8");
const css = readFingerprintedAsset("styles.css");
const appJs = readFingerprintedAsset("app.js");

assert.match(indexHtml, /archive-control-desk/, "Expected homepage build to include archive-control-desk");
assert.doesNotMatch(indexHtml, /archive-context-note/, "Expected homepage build to remove archive-context-note");
assert.match(indexHtml, /archive-control-desk__header/, "Expected homepage build to include archive-control-desk__header");
assert.match(indexHtml, /id="archive-advanced"/, "Expected homepage build to keep archive advanced controls");
assert.match(playerHtml, /player-dossier/, "Expected player build to include player-dossier");
assert.match(playerHtml, /player-dossier__ledger/, "Expected player build to include player-dossier__ledger");
assert.match(playerHtml, /player-dossier__pillars/, "Expected player build to include player-dossier__pillars");
assert.match(playerHtml, /player-dossier__marginalia/, "Expected player build to include player-dossier__marginalia");
assert.match(playerHtml, /season-ledger__notes/, "Expected player build to include season-ledger__notes");
assert.match(playerHtml, /aria-label="Player dossier notes"/, "Expected player build to include a player dossier notes label");
assert.match(css, /\.archive-control-desk\b/, "Expected built CSS to include .archive-control-desk");
assert.match(css, /\.archive-control-desk__header\b/, "Expected built CSS to include .archive-control-desk__header");
assert.match(css, /\.player-dossier__ledger\b/, "Expected built CSS to include .player-dossier__ledger");
assert.match(css, /\.player-dossier__pillars\b/, "Expected built CSS to include .player-dossier__pillars");
assert.match(css, /\.player-dossier__marginalia\b/, "Expected built CSS to include .player-dossier__marginalia");
assert.match(css, /\.dossier-pillars\b/, "Expected built CSS to include .dossier-pillars");
assert.match(css, /\.player-dossier__context-grid\b/, "Expected built CSS to include .player-dossier__context-grid");
assert.match(appJs, /table-link--dossier/, "Expected built archive script to include table-link--dossier");
assert.match(appJs, /table-link__meta/, "Expected built archive script to include table-link__meta");
assert.match(appJs, /Open dossier/, "Expected built archive script to include dossier helper copy");
assert.match(css, /\.table-link--dossier\b/, "Expected built CSS to include .table-link--dossier");
assert.match(css, /\.table-link__meta\b/, "Expected built CSS to include .table-link__meta");

function extractFunction(source, name, nextName) {
  const start = source.indexOf(`function ${name}`);
  assert.notEqual(start, -1, `Expected built archive script to include function ${name}`);
  const end = nextName ? source.indexOf(`function ${nextName}`, start) : source.length;
  assert.notEqual(end, -1, `Expected built archive script to include function ${nextName} after ${name}`);
  return source.slice(start, end).trim();
}

class FakeTextNode {
  constructor(text) {
    this.nodeType = "text";
    this.value = String(text);
  }

  get textContent() {
    return this.value;
  }

  set textContent(value) {
    this.value = String(value);
  }
}

class FakeFragment {
  constructor() {
    this.children = [];
  }

  append(...nodes) {
    nodes.forEach((node) => this.appendChild(node));
  }

  appendChild(node) {
    if (node instanceof FakeFragment) {
      this.children.push(...node.children);
      return node;
    }
    this.children.push(node);
    return node;
  }
}

class FakeElement {
  constructor(tagName) {
    this.tagName = tagName.toUpperCase();
    this.children = [];
    this.dataset = {};
    this.attributes = {};
    this.className = "";
    this._textContent = "";
    this.style = {
      setProperty: () => {}
    };
  }

  append(...nodes) {
    nodes.forEach((node) => this.appendChild(node));
  }

  appendChild(node) {
    if (node instanceof FakeFragment) {
      this.children.push(...node.children);
      return node;
    }
    if (typeof node === "string") {
      this.children.push(new FakeTextNode(node));
      return node;
    }
    this.children.push(node);
    return node;
  }

  replaceChildren(...nodes) {
    this.children = [];
    this._textContent = "";
    if (nodes.length) {
      this.append(...nodes);
    }
  }

  setAttribute(name, value) {
    this.attributes[name] = String(value);
  }

  closest() {
    return {};
  }

  set textContent(value) {
    this._textContent = String(value);
    this.children = [];
  }

  get textContent() {
    if (this.children.length) {
      return this.children.map((child) => child.textContent).join("");
    }
    return this._textContent;
  }
}

const runtimeContext = {
  document: {
    createElement(tagName) {
      return new FakeElement(tagName);
    },
    createDocumentFragment() {
      return new FakeFragment();
    },
    createTextNode(text) {
      return new FakeTextNode(text);
    }
  },
  elements: {
    playerLeadersBody: new FakeElement("tbody")
  },
  state: {
    meta: { seasons: [2024, 2023] },
    filters: { seasons: [], archiveMode: "aggregate" }
  },
  formatNumber(value) {
    return String(value);
  },
  formatStatLabel(value) {
    return String(value);
  },
  formatDate(value) {
    return String(value);
  },
  playerProfileUrl(playerId) {
    return `/player/${encodeURIComponent(playerId)}/`;
  },
  resolvePlayerColour() {
    return "var(--accent)";
  },
  createCell(text) {
    const cell = new FakeElement("td");
    cell.textContent = text;
    return cell;
  },
  createTeamCell(name) {
    const cell = new FakeElement("td");
    cell.textContent = name;
    return cell;
  },
  statValue(row) {
    return row.value ?? row.total_value;
  },
  clearEmptyTableState() {},
  syncResponsiveTable() {}
};

vm.runInNewContext(
  [
    extractFunction(appJs, "describeSeasonScope", "teamLabel"),
    extractFunction(appJs, "isRecordMode", "statModeLabel"),
    extractFunction(appJs, "createPlayerLinkCell", "createTeamCell"),
    extractFunction(appJs, "renderPlayerLeaders", "renderCompetitionSeasonTable")
  ].join("\n\n"),
  runtimeContext
);

function assertRenderedDossierLink(archiveMode) {
  runtimeContext.state.filters.archiveMode = archiveMode;
  runtimeContext.elements.playerLeadersBody = new FakeElement("tbody");
  runtimeContext.renderPlayerLeaders([
    {
      player_id: 80826,
      player_name: "Example Player",
      squad_name: "Swifts",
      opponent: "Fever",
      season: 2024,
      round_number: 1,
      stat: "points",
      total_value: 42,
      matches_played: 10,
      local_start_time: "2024-04-01T12:00:00Z"
    }
  ]);

  const row = runtimeContext.elements.playerLeadersBody.children[0];
  assert.ok(row, `Expected ${archiveMode} player leader rows to render`);

  const playerCell = row.children[1];
  const dossierLink = playerCell?.children[0];
  assert.equal(
    dossierLink?.className,
    "table-link table-link--dossier",
    `Expected ${archiveMode} player rows to render dossier-style links`
  );
  assert.equal(
    dossierLink?.children?.[1]?.textContent,
    "Open dossier",
    `Expected ${archiveMode} player rows to render dossier helper copy`
  );
  assert.equal(
    dossierLink?.href,
    "/player/80826/",
    `Expected ${archiveMode} player rows to link to the player dossier`
  );
}

assertRenderedDossierLink("aggregate");
assertRenderedDossierLink("records");

console.log("Editorial almanac smoke checks passed");
