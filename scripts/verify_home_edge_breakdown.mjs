import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const distDir = path.resolve(scriptDir, "..", "dist");
const indexHtml = readFileSync(path.join(distDir, "home-court-advantage", "index.html"), "utf8");
const stylesheetHrefMatch = indexHtml.match(/<link rel="stylesheet" href="(\/assets\/styles\.[^"]+\.css)">/);

assert.ok(stylesheetHrefMatch, "Expected the built Home Court Advantage page to reference a fingerprinted stylesheet.");

const cssPath = path.join(distDir, stylesheetHrefMatch[1].replace(/^\//, ""));
const css = readFileSync(cssPath, "utf8");

assert.match(indexHtml, /<legend>Seasons<\/legend>/, "Expected the Home Court Advantage filters to include a Seasons fieldset.");
assert.match(indexHtml, /id="home-edge-season-choices"/, "Expected the built page to include home-edge-season-choices.");
assert.match(indexHtml, /id="home-edge-season-summary"/, "Expected the built page to include home-edge-season-summary.");
assert.match(indexHtml, /<legend>Stat lens<\/legend>/, "Expected the Home Court Advantage filters to include a Stat lens fieldset.");
assert.match(indexHtml, /id="home-edge-stat-groups"/, "Expected the built page to include home-edge-stat-groups.");
assert.match(indexHtml, /id="home-edge-stat-body"/, "Expected the built page to include home-edge-stat-body.");
assert.match(indexHtml, /id="home-edge-opposition-body"/, "Expected the built page to include home-edge-opposition-body.");
assert.match(indexHtml, /id="home-edge-opposition-stat-body"/, "Expected the built page to include home-edge-opposition-stat-body.");
assert.match(indexHtml, /id="home-edge-team-venue-stat-heading"/, "Expected the built page to include home-edge-team-venue-stat-heading.");
assert.match(indexHtml, /id="home-edge-team-venue-stat-body"/, "Expected the built page to include home-edge-team-venue-stat-body.");
assert.match(indexHtml, /class="home-edge-chip-group season-choices"/, "Expected the built page to include the season chip group.");

assert.match(css, /\.home-edge-stat-grid\b/, "Expected built CSS to include .home-edge-stat-grid.");
assert.match(css, /\.home-edge-chip-group\b/, "Expected built CSS to include .home-edge-chip-group.");
assert.match(css, /\.home-edge-chip\b/, "Expected built CSS to include .home-edge-chip.");

console.log("Home Court Advantage breakdown smoke checks passed");
