import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";

const repoRoot = process.cwd();
const html = readFileSync(path.join(repoRoot, "compare", "index.html"), "utf8");
const css = readFileSync(path.join(repoRoot, "assets", "styles.css"), "utf8");

assert.ok(
  !html.includes('<aside class="hero-aside"'),
  "Expected the compare hero to stop using a separate aside card."
);

assert.ok(
  html.includes('class="compare-hero-dek"'),
  "Expected the compare hero to use an inline dek."
);

assert.ok(
  html.includes('id="compare-step-mode" class="builder-step builder-step--rail"'),
  "Expected compare step 1 to use the lighter rail treatment."
);

assert.ok(
  html.includes('id="compare-step-action" class="builder-step builder-step--action builder-step--rail"'),
  "Expected compare step 4 to use the lighter rail treatment."
);

assert.ok(
  html.includes('class="compare-results-stack"'),
  "Expected compare results to be grouped into one layout stack."
);

assert.ok(
  html.includes('class="panel compare-verdict compare-results-lead reveal"'),
  "Expected the verdict panel to lead the results flow."
);

assert.ok(
  html.includes('compare-results-panel compare-results-panel--chart'),
  "Expected the trend panel to carry a compare-specific results layout class."
);

assert.ok(
  html.includes('compare-results-panel compare-results-panel--table'),
  "Expected the table panel to carry a compare-specific results layout class."
);

assert.ok(
  html.includes('class="table-wrapper compare-table-shell"'),
  "Expected the comparison table wrapper to use a lighter compare-specific shell."
);

for (const selector of [
  ".compare-builder > .builder-step--rail",
  ".compare-results-stack",
  ".compare-results-lead",
  ".compare-results-panel--table .table-wrapper",
  ".compare-page .hero-copy"
]) {
  assert.ok(
    css.includes(selector),
    `Expected compare layout styles for ${selector}.`
  );
}

console.log("Compare layout checks passed.");
