import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";

const repoRoot = process.cwd();
const css = readFileSync(path.join(repoRoot, "assets", "styles.css"), "utf8");
const appJs = readFileSync(path.join(repoRoot, "assets", "app.js"), "utf8");
const compareJs = readFileSync(path.join(repoRoot, "assets", "compare.js"), "utf8");
const chartPaletteLines = css
  .split("\n")
  .filter((line) => line.includes("--chart-palette-"))
  .join("\n");

function getBlock(source, selector) {
  const start = source.indexOf(selector);
  assert.notStrictEqual(start, -1, `Expected to find selector block for ${selector}`);
  const braceStart = source.indexOf("{", start);
  assert.notStrictEqual(braceStart, -1, `Expected opening brace for ${selector}`);
  let depth = 0;
  for (let index = braceStart; index < source.length; index += 1) {
    const char = source[index];
    if (char === "{") {
      depth += 1;
    } else if (char === "}") {
      depth -= 1;
      if (depth === 0) {
        return source.slice(braceStart + 1, index);
      }
    }
  }
  throw new Error(`Expected closing brace for ${selector}`);
}

assert.ok(
  !css.includes("background-image: url('noise.svg');"),
  "Expected the shared noise overlay to be removed for a quieter whole-site pass."
);

assert.ok(
  !css.includes("radial-gradient(circle at top right"),
  "Expected shared hero variants to drop the loud radial wash."
);

assert.ok(
  !css.includes("background: linear-gradient(135deg, var(--accent) 0%, var(--accent-strong) 100%);"),
  "Expected primary buttons to use a calmer fill instead of the amber gradient."
);

assert.ok(
  !css.includes(".button:hover,\nbutton:hover {\n  transform: translateY(-2px);\n}"),
  "Expected shared button hover states to stop lifting controls vertically."
);

const themeToggleValueBlock = getBlock(css, ".theme-toggle__value");
assert.ok(
  !themeToggleValueBlock.includes("var(--display-font)"),
  "Expected the theme toggle value to stop using the display font."
);

assert.ok(
  !css.includes("animation: status-banner-scan 1.6s linear infinite;"),
  "Expected loading banners to stop using the scanning animation."
);

assert.ok(
  !css.includes("filter: drop-shadow(0 10px 14px rgba(0, 0, 0, 0.16));"),
  "Expected chart bars to lose the decorative drop shadow."
);

assert.ok(
  !css.includes("filter: drop-shadow(0 10px 14px rgba(0, 0, 0, 0.2));"),
  "Expected chart trend lines to lose the decorative drop shadow."
);

assert.ok(
  !css.includes("box-shadow: inset 3px 0 0 var(--row-accent, transparent);"),
  "Expected leaderboard rows to lose the thick accent stripe."
);

for (const loudColour of ["#ff9e9e", "#f4a0d8", "#8ac6ff"]) {
  assert.ok(
    !chartPaletteLines.includes(loudColour) && !appJs.includes(loudColour) && !compareJs.includes(loudColour),
    `Expected louder chart colour ${loudColour} to be removed from the shared palette.`
  );
}

console.log("Quieter shared-style checks passed.");
