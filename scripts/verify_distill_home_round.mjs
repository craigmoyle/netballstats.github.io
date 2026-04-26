import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";

const repoRoot = process.cwd();
const homeHtml = readFileSync(path.join(repoRoot, "index.html"), "utf8");
const roundHtml = readFileSync(path.join(repoRoot, "round", "index.html"), "utf8");
const roundPreviewHtml = readFileSync(path.join(repoRoot, "round-preview", "index.html"), "utf8");
const appJs = readFileSync(path.join(repoRoot, "assets", "app.js"), "utf8");
const roundJs = readFileSync(path.join(repoRoot, "assets", "round.js"), "utf8");
const roundPreviewJs = readFileSync(path.join(repoRoot, "assets", "round-preview.js"), "utf8");
const css = readFileSync(path.join(repoRoot, "assets", "styles.css"), "utf8");

const archiveAdvancedStart = homeHtml.indexOf('id="archive-advanced"');
assert.notStrictEqual(archiveAdvancedStart, -1, "Expected homepage advanced archive details.");

for (const id of ['id="archive-mode"', 'id="stat-mode"', 'id="ranking-mode"']) {
  const index = homeHtml.indexOf(id);
  assert.ok(index > archiveAdvancedStart, `Expected ${id} to live inside the advanced archive details block.`);
}

assert.ok(
  !homeHtml.includes('id="archive-context-note"'),
  "Expected the homepage to remove the extra archive context note."
);

assert.ok(
  !homeHtml.includes('scoreflow-teaser'),
  "Expected the homepage to remove the scoreflow teaser band."
);

assert.ok(
  !appJs.includes("loadScoreflowHomeCards"),
  "Expected homepage JS to remove the scoreflow teaser loader."
);

assert.ok(
  !roundHtml.includes('<aside class="hero-aside"'),
  "Expected the round recap hero to remove the summary aside."
);

assert.ok(
  !roundHtml.includes('id="round-fact-grid"'),
  "Expected the round recap to remove the standalone notable facts grid."
);

assert.ok(
  roundHtml.includes('id="round-fact-strip"'),
  "Expected the round recap to add an inline facts strip inside the match recap flow."
);

assert.ok(
  roundJs.includes("renderFactStrip"),
  "Expected round.js to render the simplified inline fact strip."
);

assert.ok(
  !roundPreviewHtml.includes('<aside class="hero-aside"'),
  "Expected the round preview hero to remove the summary aside."
);

assert.ok(
  roundPreviewJs.includes('document.createElement("details")') &&
  roundPreviewJs.includes("round-preview-card__extras"),
  "Expected round preview cards to use progressive disclosure for extra context."
);

for (const selector of [".round-fact-strip", ".round-preview-card__extras", ".round-preview-card__extras-summary"]) {
  assert.ok(
    css.includes(selector),
    `Expected distill styles for ${selector}.`
  );
}

console.log("Home and round distill checks passed.");
