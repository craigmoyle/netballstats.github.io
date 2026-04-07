import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const distDir = path.resolve(scriptDir, "..", "dist");
const indexHtml = readFileSync(path.join(distDir, "index.html"), "utf8");
const playerHtml = readFileSync(path.join(distDir, "player", "index.html"), "utf8");
const css = readFileSync(path.join(distDir, "assets", "styles.css"), "utf8");
const appJs = readFileSync(path.join(distDir, "assets", "app.js"), "utf8");

assert.match(indexHtml, /archive-control-desk/, "Expected homepage build to include archive-control-desk");
assert.match(indexHtml, /archive-context-note/, "Expected homepage build to include archive-context-note");
assert.match(indexHtml, /archive-results-intro/, "Expected homepage build to include archive-results-intro");
assert.match(indexHtml, /archive-control-desk__header/, "Expected homepage build to include archive-control-desk__header");
assert.match(playerHtml, /player-dossier/, "Expected player build to include player-dossier");
assert.match(playerHtml, /player-dossier__ledger/, "Expected player build to include player-dossier__ledger");
assert.match(css, /\.archive-control-desk\b/, "Expected built CSS to include .archive-control-desk");
assert.match(css, /\.archive-results-intro\b/, "Expected built CSS to include .archive-results-intro");
assert.match(css, /\.archive-control-desk__header\b/, "Expected built CSS to include .archive-control-desk__header");
assert.match(css, /\.player-dossier__ledger\b/, "Expected built CSS to include .player-dossier__ledger");
assert.match(appJs, /table-link--dossier/, "Expected built archive script to include table-link--dossier");
assert.match(appJs, /table-link__meta/, "Expected built archive script to include table-link__meta");
assert.match(appJs, /Open dossier/, "Expected built archive script to include dossier helper copy");
assert.match(css, /\.table-link--dossier\b/, "Expected built CSS to include .table-link--dossier");
assert.match(css, /\.table-link__meta\b/, "Expected built CSS to include .table-link__meta");

console.log("Editorial almanac smoke checks passed");
