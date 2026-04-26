import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";

const repoRoot = process.cwd();
const html = readFileSync(path.join(repoRoot, "query", "index.html"), "utf8");

const expectedExamples = [
  {
    question: "Grace Nweke goal assists across 2023, 2024, 2025",
    intentType: "trend"
  },
  {
    question: "Vixens vs Swifts goal assists in 2025",
    intentType: "comparison"
  },
  {
    question: "Highest single-game intercepts all time",
    intentType: "record"
  }
];

const expectedApiQuestions = [
  ...expectedExamples,
  {
    question: "Which teams had the lowest general play turnovers in 2025?",
    intentType: "lowest"
  }
];

const exampleMatches = [...html.matchAll(/data-example="([^"]+)"/g)].map((match) => match[1]);

for (const example of expectedExamples) {
  assert(
    exampleMatches.includes(example.question),
    `Expected query page to include ready-made example: "${example.question}".`
  );
}

const baseUrlArg = process.argv.find((value) => value.startsWith("--base-url="));
const baseUrl = baseUrlArg ? baseUrlArg.slice("--base-url=".length).replace(/\/$/, "") : null;

if (!baseUrl) {
  throw new Error("Pass --base-url=<api-root> to verify example questions against a running API.");
}

for (const example of expectedApiQuestions) {
  const url = new URL(`${baseUrl}/query`);
  url.searchParams.set("question", example.question);

  const response = await fetch(url);
  assert.equal(response.ok, true, `Expected ${example.question} to return HTTP 200.`);

  const payload = await response.json();
  assert.equal(
    payload.status,
    "supported",
    `Expected "${example.question}" to return status \"supported\".`
  );
  assert.equal(
    payload.intent_type,
    example.intentType,
    `Expected "${example.question}" to resolve as ${example.intentType}.`
  );
}

console.log("Query example verification passed.");
