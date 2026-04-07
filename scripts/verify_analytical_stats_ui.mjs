import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const distDir = path.resolve(scriptDir, "..", "dist");
const indexHtml = readFileSync(path.join(distDir, "index.html"), "utf8");
const appJs = readFileSync(path.join(distDir, "assets", "app.js"), "utf8");
const css = readFileSync(path.join(distDir, "assets", "styles.css"), "utf8");

assert.match(indexHtml, /team-stat-note/, "Expected archive build to include team-stat-note");
assert.match(indexHtml, /player-stat-note/, "Expected archive build to include player-stat-note");
assert.match(appJs, /syncAnalyticalStatMode/, "Expected archive app bundle to include syncAnalyticalStatMode");
assert.match(appJs, /renderStatExplainer/, "Expected archive app bundle to include renderStatExplainer");
assert.match(css, /\.field-hint--stat-note\b/, "Expected built CSS to include .field-hint--stat-note");
assert.match(css, /\.filters--analytics-locked\b/, "Expected built CSS to include .filters--analytics-locked");

console.log("Analytical archive UI smoke checks passed");
