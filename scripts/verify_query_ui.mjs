import { readFileSync } from "node:fs";
import path from "node:path";

const repoRoot = process.cwd();
const html = readFileSync(path.join(repoRoot, "query", "index.html"), "utf8");
const css = readFileSync(path.join(repoRoot, "assets", "styles.css"), "utf8");

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

console.log("Query UI verification passed.");
