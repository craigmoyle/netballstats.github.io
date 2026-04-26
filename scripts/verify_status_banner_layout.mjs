import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";

const css = readFileSync(path.join(process.cwd(), "assets", "styles.css"), "utf8");

assert.match(
  css,
  /\.status-banner\s*\{[\s\S]*?position\s*:\s*fixed[\s\S]*?z-index\s*:/,
  "Expected .status-banner to render as a floating layer so it does not participate in panel layout."
);

assert.match(
  css,
  /\.status-banner\s*\{[\s\S]*?left\s*:\s*50%[\s\S]*?transform\s*:\s*translateX\(-50%\)/s,
  "Expected .status-banner to be horizontally centered as a floating toast."
);

console.log("Status banner layout verification passed.");
