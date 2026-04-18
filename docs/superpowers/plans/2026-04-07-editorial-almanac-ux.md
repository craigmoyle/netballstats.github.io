# Editorial Almanac UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Rework the archive homepage and player profile pages into a shared editorial almanac system where the archive is the discovery layer and the player page is the richer dossier.

**Architecture:** Keep the existing static HTML + vanilla JS structure, but add a small smoke-check script so the UI work can be validated without introducing a new test framework. Reuse the existing homepage panel primitives (`results-panel--lead`, `results-panel--rail`, `results-panel--anchor`) and the player profile data payload, then layer new markup hooks, rendering helpers, and CSS composition on top so the redesign stays surgical.

**Tech Stack:** Static HTML, vanilla JavaScript, shared CSS in `assets/styles.css`, Node 20+ built-in modules for smoke checks, existing `npm run build` pipeline, Azure Static Web Apps via `azd deploy web`

---

## File Map

- Create: `scripts/verify_editorial_almanac_ux.mjs` — no-dependency smoke check that reads built files from `dist/` and asserts the new archive/profile UX hooks exist.
- Modify: `index.html` — archive homepage hero, control-desk framing, reading-order note, and dossier cues.
- Modify: `player/index.html` — player dossier hero, pillars, marginalia rail, and season ledger framing.
- Modify: `assets/app.js` — archive explanatory copy, player dossier link affordances, and panel-summary behavior.
- Modify: `assets/player.js` — derive dossier pillars and marginalia from the existing `/player-profile` payload; keep all data client-side.
- Modify: `assets/styles.css` — shared editorial surface rules, archive control desk, dossier layout, link affordances, and responsive refinements.

## Validation Commands

Use these exact commands throughout the plan:

- `node --check assets/app.js`
- `node --check assets/player.js`
- `npm run build`
- `node scripts/verify_editorial_almanac_ux.mjs`
- `python3 -m http.server 4173 --directory dist`
- `azd deploy web --no-prompt`

---

### Task 1: Add a smoke-check harness and structural shell hooks

**Files:**
- Create: `scripts/verify_editorial_almanac_ux.mjs`
- Modify: `index.html`
- Modify: `player/index.html`
- Modify: `assets/styles.css`

- [x] **Step 1: Write the failing smoke check**

Create `scripts/verify_editorial_almanac_ux.mjs` with these exact assertions:

```js
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const distDir = path.resolve(scriptDir, "..", "dist");
const indexHtml = readFileSync(path.join(distDir, "index.html"), "utf8");
const playerHtml = readFileSync(path.join(distDir, "player", "index.html"), "utf8");
const css = readFileSync(path.join(distDir, "assets", "styles.css"), "utf8");

assert.match(indexHtml, /archive-control-desk/, "Expected homepage build to include archive-control-desk");
assert.match(indexHtml, /archive-context-note/, "Expected homepage build to include archive-context-note");
assert.match(playerHtml, /player-dossier/, "Expected player build to include player-dossier");
assert.match(playerHtml, /player-dossier__ledger/, "Expected player build to include player-dossier__ledger");
assert.match(css, /\.archive-control-desk\b/, "Expected built CSS to include .archive-control-desk");
assert.match(css, /\.player-dossier__ledger\b/, "Expected built CSS to include .player-dossier__ledger");

console.log("Editorial almanac smoke checks passed");
```

- [x] **Step 2: Run the smoke check to confirm it fails**

Run:

```bash
cd /Users/craig/Git/netballstats
npm run build && node scripts/verify_editorial_almanac_ux.mjs
```

Expected: FAIL with `Expected homepage build to include archive-control-desk`

- [x] **Step 3: Add the minimal homepage and player shell hooks**

Update `index.html` so the archive filter section gains an editorial shell and a dedicated context note:

```html
<section class="panel query-panel query-panel--home archive-control-desk reveal">
  <div class="archive-control-desk__header">
    <div class="panel__heading panel__heading--split">
      <div>
        <p class="panel__eyebrow">Start here</p>
        <h2>Set the archive lens</h2>
        <p class="panel__lead">Pick seasons, a stat, and a mode. Add a player, team, or round if you need a smaller slice.</p>
      </div>
      <p id="active-filter-summary" class="muted filter-summary">Loading query options…</p>
    </div>
    <p id="archive-context-note" class="archive-context-note">Use the archive to find a player or team, then open the deeper dossier or season context below.</p>
  </div>
  <form id="filters-form" class="filters filters--dashboard" novalidate>
```

Update `player/index.html` so the hero and season section expose dossier-oriented hooks:

```html
<section class="hero-panel player-hero player-dossier">
  <div class="hero-copy">
    <p class="eyebrow">Player dossier</p>
```

```html
<section class="panel player-dossier__ledger reveal">
  <div class="player-toolbar">
    <div class="panel__heading">
      <h2>Season ledger</h2>
    </div>
```

Add the matching minimal CSS in `assets/styles.css`:

```css
.archive-control-desk,
.player-dossier__ledger {
  position: relative;
  overflow: hidden;
}

.archive-control-desk__header {
  display: grid;
  gap: var(--space-xs);
  margin-bottom: var(--space-sm);
}

.archive-context-note {
  margin: 0;
  max-width: 58ch;
  color: var(--muted);
  font-size: var(--text-ui-size);
  line-height: 1.65;
}
```

- [x] **Step 4: Run the smoke check again**

Run:

```bash
cd /Users/craig/Git/netballstats
npm run build && node scripts/verify_editorial_almanac_ux.mjs
```

Expected: PASS with `Editorial almanac smoke checks passed`

- [x] **Step 5: Commit**

```bash
cd /Users/craig/Git/netballstats
git add scripts/verify_editorial_almanac_ux.mjs index.html player/index.html assets/styles.css
git commit -m "feat: add editorial almanac layout shells"
```

---

### Task 2: Rework the archive homepage into a control desk plus reading-order surface

**Files:**
- Modify: `scripts/verify_editorial_almanac_ux.mjs`
- Modify: `index.html`
- Modify: `assets/styles.css`

- [x] **Step 1: Extend the smoke check with homepage-specific assertions**

Append these assertions to `scripts/verify_editorial_almanac_ux.mjs` after the existing homepage checks:

```js
assert.match(indexHtml, /archive-results-intro/, "Expected homepage build to include archive-results-intro");
assert.match(indexHtml, /archive-control-desk__header/, "Expected homepage build to include archive-control-desk__header");
assert.match(css, /\.archive-results-intro\b/, "Expected built CSS to include .archive-results-intro");
assert.match(css, /\.archive-control-desk__header\b/, "Expected built CSS to include .archive-control-desk__header");
```

- [x] **Step 2: Run the smoke check to confirm it fails**

Run:

```bash
cd /Users/craig/Git/netballstats
npm run build && node scripts/verify_editorial_almanac_ux.mjs
```

Expected: FAIL with `Expected homepage build to include archive-results-intro`

- [x] **Step 3: Add the archive reading-order module and stronger control-desk styling**

Insert a new intro block at the top of the homepage results grid in `index.html`:

```html
<section class="results-grid results-grid--home" aria-label="Stat tables">
  <section class="archive-results-intro reveal" aria-label="Archive reading guide">
    <p class="results-panel__eyebrow">Archive reading order</p>
    <h2>Start with the leaders, then open the dossier</h2>
    <p class="muted">Use the player leaderboard as the lead surface, season totals as context, and clubs as the supporting counterpoint.</p>
  </section>

  <section class="panel results-panel results-panel--lead reveal">
```

Tighten the archive control-desk and reading-order surfaces in `assets/styles.css`:

```css
.archive-control-desk {
  background:
    linear-gradient(180deg, color-mix(in srgb, var(--accent-cool) 7%, transparent), transparent 38%),
    linear-gradient(180deg, color-mix(in srgb, var(--text) 3%, transparent), transparent 72%),
    var(--panel-solid);
}

.archive-results-intro {
  grid-column: 1 / -1;
  display: grid;
  gap: var(--space-2xs);
  padding: var(--space-sm) var(--space-md);
  border-radius: var(--radius-card);
  background:
    linear-gradient(180deg, color-mix(in srgb, var(--accent) 6%, transparent), transparent 44%),
    color-mix(in srgb, var(--panel-alt) 88%, transparent);
  border: 1px solid color-mix(in srgb, var(--accent) 18%, var(--border));
}

.archive-results-intro h2 {
  margin: 0;
  max-width: 20ch;
}
```

- [x] **Step 4: Re-run the homepage validation**

Run:

```bash
cd /Users/craig/Git/netballstats
npm run build && node scripts/verify_editorial_almanac_ux.mjs
```

Expected: PASS with `Editorial almanac smoke checks passed`

- [x] **Step 5: Commit**

```bash
cd /Users/craig/Git/netballstats
git add scripts/verify_editorial_almanac_ux.mjs index.html assets/styles.css
git commit -m "feat: add archive control desk and reading guide"
```

---

### Task 3: Make archive rows clearly open a player dossier

**Files:**
- Modify: `scripts/verify_editorial_almanac_ux.mjs`
- Modify: `assets/app.js`
- Modify: `assets/styles.css`

- [x] **Step 1: Extend the smoke check for dossier link cues**

Append these lines to `scripts/verify_editorial_almanac_ux.mjs` right after the existing `css` read:

```js
const appJs = readFileSync(path.join(distDir, "assets", "app.js"), "utf8");
```

Then append these assertions:

```js
assert.match(appJs, /table-link--dossier/, "Expected built archive script to include table-link--dossier");
assert.match(appJs, /table-link__meta/, "Expected built archive script to include table-link__meta");
assert.match(appJs, /Open dossier/, "Expected built archive script to include dossier helper copy");
assert.match(css, /\.table-link--dossier\b/, "Expected built CSS to include .table-link--dossier");
assert.match(css, /\.table-link__meta\b/, "Expected built CSS to include .table-link__meta");
```

- [x] **Step 2: Run the smoke check to confirm it fails**

Run:

```bash
cd /Users/craig/Git/netballstats
npm run build && node scripts/verify_editorial_almanac_ux.mjs
```

Expected: FAIL with `Expected built archive script to include table-link--dossier`

- [x] **Step 3: Update archive rendering and dossier link treatment**

In `assets/app.js`, add a dedicated archive-context renderer and a richer player link cell:

```js
function renderArchiveContextNote() {
  if (!elements.archiveContextNote) return;
  const scope = describeSeasonScope();
  elements.archiveContextNote.textContent = isRecordMode()
    ? `Use the archive to surface the sharpest one-game performances in ${scope}, then open the dossier for full career context.`
    : `Use the archive to scan the strongest totals in ${scope}, then open the dossier for season-by-season context.`;
}

function createPlayerLinkCell(playerId, text) {
  const cell = document.createElement("td");
  const link = document.createElement("a");
  link.href = playerProfileUrl(playerId);
  link.className = "table-link table-link--dossier";

  const label = document.createElement("span");
  label.textContent = text;

  const meta = document.createElement("span");
  meta.className = "table-link__meta";
  meta.textContent = "Open dossier";

  link.append(label, meta);
  cell.appendChild(link);
  return cell;
}
```

Wire the new note into the existing render flow by adding the element and calling the renderer:

```js
archiveContextNote: document.getElementById("archive-context-note"),
```

```js
function renderFilterSummary() {
  syncFiltersFromForm();
  // existing summary work...
  renderArchiveContextNote();
}
```

Replace both `createLinkCell(playerProfileUrl(rowData.player_id), rowData.player_name)` calls in `renderPlayerLeaders()` with:

```js
createPlayerLinkCell(rowData.player_id, rowData.player_name)
```

Add dossier link styling in `assets/styles.css`:

```css
.table-link--dossier {
  display: inline-grid;
  gap: 0.18rem;
}

.table-link__meta {
  color: var(--muted);
  font-size: var(--type-xs);
  letter-spacing: 0.06em;
  text-transform: uppercase;
}
```

- [x] **Step 4: Validate the archive JavaScript and smoke check**

Run:

```bash
cd /Users/craig/Git/netballstats
node --check assets/app.js
npm run build && node scripts/verify_editorial_almanac_ux.mjs
```

Expected:

- `node --check assets/app.js` exits with code `0`
- smoke check prints `Editorial almanac smoke checks passed`

- [x] **Step 5: Commit**

```bash
cd /Users/craig/Git/netballstats
git add scripts/verify_editorial_almanac_ux.mjs assets/app.js assets/styles.css
git commit -m "feat: add dossier cues to archive leaderboards"
```

---

### Task 4: Turn the player page into a dossier with pillars, marginalia, and a season ledger

**Files:**
- Modify: `scripts/verify_editorial_almanac_ux.mjs`
- Modify: `player/index.html`
- Modify: `assets/player.js`
- Modify: `assets/styles.css`

- [x] **Step 1: Extend the smoke check for dossier-specific hooks**

Append these assertions to `scripts/verify_editorial_almanac_ux.mjs`:

```js
assert.match(playerHtml, /player-dossier__pillars/, "Expected player build to include player-dossier__pillars");
assert.match(playerHtml, /player-dossier__marginalia/, "Expected player build to include player-dossier__marginalia");
assert.match(playerHtml, /season-ledger__notes/, "Expected player build to include season-ledger__notes");
assert.match(css, /\.player-dossier__pillars\b/, "Expected built CSS to include .player-dossier__pillars");
assert.match(css, /\.player-dossier__marginalia\b/, "Expected built CSS to include .player-dossier__marginalia");
```

- [x] **Step 2: Run the smoke check to confirm it fails**

Run:

```bash
cd /Users/craig/Git/netballstats
npm run build && node scripts/verify_editorial_almanac_ux.mjs
```

Expected: FAIL with `Expected player build to include player-dossier__pillars`

- [x] **Step 3: Add dossier markup, rendering helpers, and supporting styles**

Update `player/index.html` so the current profile sections become a dossier layout:

```html
<section class="panel player-dossier__pillars reveal" aria-label="Career pillars">
  <div id="player-pillars" class="dossier-pillars"></div>
</section>

<section class="panel reveal">
  <div class="player-dossier__context-grid">
    <div>
      <div class="panel__heading">
        <h2>Career totals</h2>
      </div>
      <div class="table-wrapper table-wrapper--spotlight">
        <!-- existing career table stays here -->
      </div>
    </div>
    <aside class="player-dossier__marginalia" aria-label="Player dossier notes">
      <p class="results-panel__eyebrow">Dossier notes</p>
      <ol id="player-marginalia" class="dossier-notes"></ol>
    </aside>
  </div>
</section>

<section class="panel player-dossier__ledger reveal">
  <div class="player-toolbar">
    <div class="panel__heading">
      <h2>Season ledger</h2>
      <p id="season-ledger-notes" class="season-ledger__notes">Loading season context…</p>
    </div>
```

In `assets/player.js`, add the new DOM hooks:

```js
playerPillars: document.getElementById("player-pillars"),
playerMarginalia: document.getElementById("player-marginalia"),
seasonLedgerNotes: document.getElementById("season-ledger-notes"),
```

Add these helper functions exactly:

```js
function buildDossierPillars(profile, topCareerStat) {
  const overview = profile.overview || {};
  const latestSeason = overview.last_season || null;
  return [
    {
      label: "Career span",
      value: overview.first_season && overview.last_season ? `${overview.first_season}–${overview.last_season}` : "Single season",
      note: `${formatNumber(overview.seasons_played)} seasons`
    },
    {
      label: "Games",
      value: formatNumber(overview.games_played),
      note: `${formatNumber(overview.teams_played)} clubs`
    },
    {
      label: "Primary record",
      value: topCareerStat ? formatNumber(topCareerStat.total_value) : "--",
      note: topCareerStat ? statLabel(topCareerStat.stat) : "No primary stat"
    },
    {
      label: "Latest season",
      value: latestSeason ? `${latestSeason}` : "--",
      note: "Archive dossier"
    }
  ];
}

function buildDossierNotes(profile, topCareerStat) {
  const overview = profile.overview || {};
  const summaries = [...(profile.season_summaries || [])].sort((left, right) => Number(right.season) - Number(left.season));
  const peakSeason = summaries.reduce((best, summary) =>
    !best || Number(summary.matches_played || 0) > Number(best.matches_played || 0) ? summary : best, null);

  return [
    peakSeason ? `Peak workload: ${formatNumber(peakSeason.matches_played)} games in ${peakSeason.season}.` : "Peak workload unavailable.",
    topCareerStat ? `Signature total: ${formatNumber(topCareerStat.total_value)} ${statLabel(topCareerStat.stat).toLowerCase()}.` : "Signature total unavailable.",
    (overview.squad_names || []).length ? `Club trail: ${(overview.squad_names || []).join(" / ")}.` : "Club trail unavailable."
  ];
}

function renderDossierPillars(pillars) {
  if (!elements.playerPillars) return;
  elements.playerPillars.replaceChildren();
  pillars.forEach((pillar) => {
    const article = document.createElement("article");
    article.className = "dossier-pillar";

    const label = document.createElement("span");
    label.className = "summary-card__label";
    label.textContent = pillar.label;

    const value = document.createElement("strong");
    value.className = "summary-card__value";
    value.textContent = pillar.value;

    const note = document.createElement("p");
    note.className = "muted";
    note.textContent = pillar.note;

    article.append(label, value, note);
    elements.playerPillars.appendChild(article);
  });
}

function renderDossierNotes(notes) {
  if (!elements.playerMarginalia) return;
  elements.playerMarginalia.replaceChildren();
  notes.forEach((noteText) => {
    const item = document.createElement("li");
    item.textContent = noteText;
    elements.playerMarginalia.appendChild(item);
  });
}
```

Render them inside `renderProfile(profile)`:

```js
const pillars = buildDossierPillars(profile, topCareerStat);
const notes = buildDossierNotes(profile, topCareerStat);
renderDossierPillars(pillars);
renderDossierNotes(notes);
elements.seasonLedgerNotes.textContent = state.metric === "average"
  ? "Per-game view keeps season shifts readable while the ledger preserves the full table."
  : "Use the ledger to scan peaks, club changes, and long-run consistency.";
```

Add the dossier styles in `assets/styles.css`:

```css
.player-dossier__pillars {
  padding-top: var(--space-sm);
}

.dossier-pillars {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: var(--space-sm);
}

.dossier-pillar {
  display: grid;
  gap: 0.35rem;
  padding: 1rem;
  border-radius: var(--radius-card);
  background:
    linear-gradient(180deg, color-mix(in srgb, var(--accent) 5%, transparent), transparent 48%),
    color-mix(in srgb, var(--panel-alt) 92%, transparent);
}

.player-dossier__context-grid {
  display: grid;
  grid-template-columns: minmax(0, 1.45fr) minmax(18rem, 0.7fr);
  gap: var(--space-md);
  align-items: start;
}

.player-dossier__marginalia {
  padding: var(--space-sm);
  border-radius: var(--radius-card);
  background: color-mix(in srgb, var(--text) 3%, transparent);
}

.season-ledger__notes {
  margin: 0.25rem 0 0;
  color: var(--muted);
  font-size: var(--text-ui-size);
}
```

- [x] **Step 4: Validate the player dossier build**

Run:

```bash
cd /Users/craig/Git/netballstats
node --check assets/player.js
npm run build && node scripts/verify_editorial_almanac_ux.mjs
```

Expected:

- `node --check assets/player.js` exits with code `0`
- smoke check prints `Editorial almanac smoke checks passed`

- [x] **Step 5: Commit**

```bash
cd /Users/craig/Git/netballstats
git add scripts/verify_editorial_almanac_ux.mjs player/index.html assets/player.js assets/styles.css
git commit -m "feat: turn player profile into editorial dossier"
```

---

### Task 5: Finish responsive polish, accessibility cues, and frontend deployment

**Files:**
- Modify: `scripts/verify_editorial_almanac_ux.mjs`
- Modify: `index.html`
- Modify: `player/index.html`
- Modify: `assets/styles.css`

- [x] **Step 1: Extend the smoke check for final accessibility and polish hooks**

Append these assertions to `scripts/verify_editorial_almanac_ux.mjs`:

```js
assert.match(indexHtml, /aria-label="Archive reading guide"/, "Expected homepage build to include an archive reading guide label");
assert.match(playerHtml, /aria-label="Player dossier notes"/, "Expected player build to include a player dossier notes label");
assert.match(css, /\.dossier-pillars\b/, "Expected built CSS to include .dossier-pillars");
assert.match(css, /\.player-dossier__context-grid\b/, "Expected built CSS to include .player-dossier__context-grid");
```

- [x] **Step 2: Run the smoke check to confirm it fails**

Run:

```bash
cd /Users/craig/Git/netballstats
npm run build && node scripts/verify_editorial_almanac_ux.mjs
```

Expected: FAIL with `Expected homepage build to include an archive reading guide label`

- [x] **Step 3: Add responsive and accessibility refinements**

Ensure the new landmarks are present in markup:

```html
<section class="archive-results-intro reveal" aria-label="Archive reading guide">
```

```html
<aside class="player-dossier__marginalia" aria-label="Player dossier notes">
```

Add responsive CSS in `assets/styles.css` so the new editorial layout collapses cleanly:

```css
@media (max-width: 1100px) {
  .dossier-pillars,
  .player-dossier__context-grid {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 900px) {
  .archive-control-desk__header,
  .archive-results-intro {
    gap: var(--space-xs);
  }

  .table-link__meta {
    font-size: var(--type-xs);
    letter-spacing: 0.04em;
  }
}
```

- [x] **Step 4: Run the full validation pass**

Run:

```bash
cd /Users/craig/Git/netballstats
node --check assets/app.js
node --check assets/player.js
npm run build
node scripts/verify_editorial_almanac_ux.mjs
```

Expected:

- both `node --check` commands exit with code `0`
- `npm run build` finishes with `node scripts/build_static.mjs`
- smoke check prints `Editorial almanac smoke checks passed`

Then start a local preview for manual QA:

```bash
cd /Users/craig/Git/netballstats
python3 -m http.server 4173 --directory dist
```

Manual QA checklist:

- homepage hero, control desk, and reading guide read as one composition at 1440px, 1024px, and 390px
- player rows clearly communicate “Open dossier”
- player dossier pillars stack cleanly on small screens
- season ledger remains readable in both Total and Avg/game modes
- keyboard focus remains visible on links, season chips, and toggle buttons

- [x] **Step 5: Commit**

```bash
cd /Users/craig/Git/netballstats
git add scripts/verify_editorial_almanac_ux.mjs index.html player/index.html assets/styles.css
git commit -m "feat: polish editorial almanac UX"
```

- [x] **Step 6: Deploy the frontend**

Run:

```bash
cd /Users/craig/Git/netballstats
azd deploy web --no-prompt
```

Expected: `SUCCESS: Your application was deployed to Azure`

---

## Self-Review Notes

### Spec coverage

- Shared visual rules and section patterns: covered by Tasks 1, 2, and 5
- Archive homepage hierarchy and control-desk treatment: covered by Tasks 1, 2, and 3
- Player dossier hierarchy and season ledger treatment: covered by Task 4 and Task 5
- Responsive refinement and accessibility verification: covered by Task 5

### Placeholder scan

- No `TODO`, `TBD`, or “similar to Task N” shortcuts remain
- Every task names exact files, commands, and commit messages
- Validation commands use only repo-native tooling plus Node/Python built-ins already available locally

### Type and naming consistency

- `archive-control-desk`, `archive-context-note`, `archive-results-intro`, `player-dossier`, `player-dossier__pillars`, `player-dossier__marginalia`, and `player-dossier__ledger` are the canonical hook names used throughout the plan
- `scripts/verify_editorial_almanac_ux.mjs` is the single smoke-check file reused in every task
