import { readFileSync } from "node:fs";
import path from "node:path";

const repoRoot = process.cwd();
const html = readFileSync(path.join(repoRoot, "query", "index.html"), "utf8");
const css = readFileSync(path.join(repoRoot, "assets", "styles.css"), "utf8");

// ── Existing builder modal checks ───────────────────────────────────────────

const dialogMarkup = /<dialog id="query-builder-modal" class="query-builder-modal"/.test(html);
if (!dialogMarkup) {
  throw new Error("Expected query page to keep the builder in a <dialog> element.");
}

const baseDialogBlock = css.match(/#query-builder-modal\s*\{([\s\S]*?)\}/);
if (!baseDialogBlock) {
  throw new Error("Expected styles.css to define a base #query-builder-modal block.");
}

if (/display\s*:\s*grid/i.test(baseDialogBlock[1])) {
  throw new Error("Expected closed #query-builder-modal styles to avoid forcing display:grid.");
}

const openDialogBlock = css.match(/#query-builder-modal\[open\]\s*\{([\s\S]*?)\}/);
if (!openDialogBlock) {
  throw new Error("Expected styles.css to define an [open] rule for #query-builder-modal.");
}

if (!/display\s*:\s*grid/i.test(openDialogBlock[1])) {
  throw new Error("Expected #query-builder-modal[open] to handle the modal display:grid layout.");
}

// ── Distilled query UI checks ────────────────────────────────────────────────

// 1. Single collapsed support surface containing both templates and examples
const supportDetails = /<details id="query-support"/.test(html);
if (!supportDetails) {
  throw new Error("Expected a <details id=\"query-support\"> support surface.");
}

const templateInsideSupport = html.includes('<details id="query-support"')
  && (() => {
    const idx = html.indexOf('<details id="query-support"');
    const closeIdx = html.indexOf("</details>", idx);
    const block = html.slice(idx, closeIdx);
    return block.includes('id="query-template-strip"');
  })();
if (!templateInsideSupport) {
  throw new Error("Expected #query-template-strip to live inside #query-support.");
}

const examplesInsideSupport = (() => {
  const idx = html.indexOf('<details id="query-support"');
  const closeIdx = html.indexOf("</details>", idx);
  const block = html.slice(idx, closeIdx);
  return block.includes('id="example-strip"');
})();
if (!examplesInsideSupport) {
  throw new Error("Expected #example-strip to live inside #query-support.");
}

// 2. Secondary builder trigger near the composer
const builderTrigger = /id="open-builder-trigger"/.test(html);
if (!builderTrigger) {
  throw new Error("Expected a #open-builder-trigger button near the composer.");
}

// 3. Query pulse section hidden on idle (has the hidden attribute in HTML)
const pulseHidden = /<section id="query-pulse-section"[^>]*hidden[^>]*>/.test(html);
if (!pulseHidden) {
  throw new Error("Expected #query-pulse-section to carry the hidden attribute in HTML (idle state).");
}

// 4. Query help hidden on idle
const helpHidden = /<details id="query-help"[^>]*hidden[^>]*>/.test(html);
if (!helpHidden) {
  throw new Error("Expected <details id=\"query-help\"> to carry the hidden attribute in HTML (idle state).");
}

// 5. No step-numbered sections in the main form (three-step structure removed)
const hasOldStepSections = /id="query-step-compose"|id="query-step-shape"|id="query-step-run"/.test(html);
if (hasOldStepSections) {
  throw new Error("Expected old three-step form sections (query-step-compose/shape/run) to be removed.");
}

// 6. CSS defines query-support styles
if (!css.includes(".query-support {")) {
  throw new Error("Expected styles.css to define .query-support styles.");
}

if (!css.includes(".query-builder-trigger {")) {
  throw new Error("Expected styles.css to define .query-builder-trigger styles.");
}

console.log("Query UI verification passed.");
