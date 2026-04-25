import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const distDir = path.resolve(scriptDir, "..", "dist");
const pageHtml = readFileSync(path.join(distDir, "round-preview", "index.html"), "utf8");
const stylesheetHrefMatch = pageHtml.match(/<link rel="stylesheet" href="(\/assets\/styles\.[^"]+\.css)">/);

assert.ok(stylesheetHrefMatch, "Expected the built round preview page to reference a fingerprinted stylesheet.");
const stylesheetPath = path.join(distDir, stylesheetHrefMatch[1].replace(/^\//, ""));
const stylesheet = readFileSync(stylesheetPath, "utf8");
assert.match(pageHtml, /round-preview-page/, "Expected the built page to include round-preview-page.");
assert.match(pageHtml, /round-preview-status/, "Expected the built page to include round-preview-status.");
assert.match(pageHtml, /round-preview-match-grid/, "Expected the built page to include round-preview-match-grid.");
assert.match(pageHtml, /id="round-preview-hero-label"/, "Expected the built page to include round-preview-hero-label.");
assert.match(pageHtml, /id="round-preview-hero-summary"/, "Expected the built page to include round-preview-hero-summary.");
assert.match(pageHtml, /href="\/round-preview\/"/, "Expected the built page to include the round preview nav link.");
assert.match(pageHtml, /\/assets\/round-preview\.[^"]+\.js/, "Expected the built page to include the fingerprinted round-preview asset.");
assert.doesNotMatch(
  stylesheet,
  /\.round-preview-team__logo\s*\{[^}]*border-radius:\s*50%/s,
  "Expected actual round preview crest images to render without a circular crop mask."
);
assert.match(
  stylesheet,
  /\.round-preview-team__logo--fallback\s*\{[^}]*border-radius:\s*50%/s,
  "Expected round preview fallback initials to keep their circular badge treatment."
);

console.log("Round preview UI smoke checks passed");

// Nav discoverability: every built page must link to /round-preview/
const navPages = [
  "index.html",
  "changelog/index.html",
  "compare/index.html",
  "home-court-advantage/index.html",
  "league-composition/index.html",
  "nwar/index.html",
  "player/index.html",
  "players/index.html",
  "query/index.html",
  "round/index.html",
  "round-preview/index.html",
  "scoreflow/index.html",
];

for (const relPath of navPages) {
  const html = readFileSync(path.join(distDir, relPath), "utf8");
  assert.match(
    html,
    /href="\/round-preview\/"/,
    `Expected ${relPath} to contain href="/round-preview/"`
  );
}

console.log("Nav discoverability checks passed");
