const config = window.NETBALL_STATS_CONFIG || {};
const API_BASE_URL = (config.apiBaseUrl || "/api").replace(/\/$/, "");
const DEFAULT_TIMEOUT_MS = 30000;
const {
  syncResponsiveTable = () => {}
} = window.NetballStatsUI || {};
const QUERY_STATUS_LABELS = {
  count: "Count",
  highest: "Highest",
  lowest: "Lowest",
  list: "List"
};

const elements = {
  apiBase: document.getElementById("api-base"),
  heroSeasonRange: document.getElementById("hero-season-range"),
  querySeasonSummary: document.getElementById("query-season-summary"),
  queryStatus: document.getElementById("query-status"),
  queryForm: document.getElementById("query-form"),
  questionInput: document.getElementById("question-input"),
  clearQuestion: document.getElementById("clear-question"),
  exampleStrip: document.getElementById("example-strip"),
  summaryQuestionType: document.getElementById("summary-question-type"),
  summaryMatchCount: document.getElementById("summary-match-count"),
  summaryStat: document.getElementById("summary-stat"),
  summaryStatus: document.getElementById("summary-status"),
  answerHeadline: document.getElementById("answer-headline"),
  answerMeta: document.getElementById("answer-meta"),
  interpretationGrid: document.getElementById("interpretation-grid"),
  queryState: document.getElementById("query-state"),
  tableMeta: document.getElementById("table-meta"),
  queryRowsBody: document.getElementById("query-rows-body")
};


if (elements.apiBase) {
  elements.apiBase.textContent = API_BASE_URL;
}

function buildUrl(path, params = {}) {
  const url = new URL(`${API_BASE_URL}${path}`, window.location.href);
  Object.entries(params).forEach(([key, value]) => {
    if (value !== undefined && value !== null && `${value}`.trim() !== "") {
      url.searchParams.set(key, value);
    }
  });
  return url;
}

async function fetchJson(path, params = {}) {
  const controller = new AbortController();
  const timeoutId = window.setTimeout(() => controller.abort(), DEFAULT_TIMEOUT_MS);

  try {
    const response = await fetch(buildUrl(path, params), {
      headers: {
        Accept: "application/json"
      },
      signal: controller.signal
    });

    const payload = await response.json().catch(() => ({ error: "Unexpected server response." }));
    if (!response.ok) {
      throw new Error(payload.error || `Request failed with status ${response.status}.`);
    }

    return payload;
  } catch (error) {
    if (error.name === "AbortError") {
      throw new Error("The request timed out.");
    }
    throw error;
  } finally {
    window.clearTimeout(timeoutId);
  }
}

function showStatus(message, tone = "neutral") {
  elements.queryStatus.textContent = message;
  elements.queryStatus.dataset.tone = tone;
  elements.queryStatus.role = tone === "error" ? "alert" : "status";
  elements.queryStatus.hidden = !message;
}

function formatNumber(value) {
  if (value === null || value === undefined || value === "") {
    return "--";
  }

  const numeric = Number(value);
  if (!Number.isFinite(numeric)) {
    return value;
  }

  return new Intl.NumberFormat("en-AU", {
    maximumFractionDigits: Number.isInteger(numeric) ? 0 : 2
  }).format(numeric);
}

function formatDate(value) {
  if (!value) {
    return "--";
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return new Intl.DateTimeFormat("en-AU", {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit"
  }).format(date);
}

function clearTable(message) {
  elements.queryRowsBody.replaceChildren();
  const row = document.createElement("tr");
  const cell = document.createElement("td");
  cell.colSpan = 7;
  cell.textContent = message;
  row.appendChild(cell);
  elements.queryRowsBody.appendChild(row);
  syncResponsiveTable(elements.queryRowsBody.closest("table"));
}

function createInterpretationCard(label, value) {
  const article = document.createElement("article");
  article.className = "interpretation-card";

  const labelElement = document.createElement("span");
  labelElement.className = "interpretation-card__label";
  labelElement.textContent = label;

  const valueElement = document.createElement("span");
  valueElement.className = "interpretation-card__value";
  valueElement.textContent = value || "--";

  article.append(labelElement, valueElement);
  return article;
}

function playerProfileUrl(playerId) {
  return `/player/${encodeURIComponent(playerId)}/`;
}

function setSummaryCards(questionType = "--", matchCount = "--", stat = "--", status = "Ready") {
  elements.summaryQuestionType.textContent = questionType;
  elements.summaryMatchCount.textContent = matchCount;
  elements.summaryStat.textContent = stat;
  elements.summaryStatus.textContent = status;
}

function setIdleState() {
  setSummaryCards();
  elements.answerHeadline.textContent = "Ask a question to see the answer.";
  elements.answerMeta.textContent = "Each answer comes from the parsed intent and the matching records.";
  elements.interpretationGrid.replaceChildren();
  elements.queryState.hidden = false;
  elements.tableMeta.textContent = "";
  clearTable("Ask a question to see the matching records.");
}

function renderMeta(meta) {
  if (!meta || !Array.isArray(meta.seasons) || !meta.seasons.length) {
    elements.querySeasonSummary.textContent = "Count, highest/lowest, and list questions over the archive.";
    return;
  }

  const seasons = [...meta.seasons].sort((left, right) => left - right);
  if (elements.heroSeasonRange) elements.heroSeasonRange.textContent = seasons[0] + "\u2013" + seasons[seasons.length - 1];
  elements.querySeasonSummary.textContent = `${seasons[0]}-${seasons[seasons.length - 1]} archive coverage with ${meta.player_stats.length} tracked player stats in the catalog.`;
}

function renderInterpretation(parsed = {}) {
  elements.interpretationGrid.replaceChildren();
  const seasonValue = Array.isArray(parsed.seasons) && parsed.seasons.length
    ? parsed.seasons.join(", ")
    : (parsed.season || "All seasons");

  const cards = [
    ["Question type", QUERY_STATUS_LABELS[parsed.intent_type] || "--"],
    ["Subject", parsed.player_name || (parsed.subject_type === "players" ? "Players" : "--")],
    ["Stat", parsed.stat_label || "--"],
    ["Filter", parsed.comparison_label && parsed.threshold !== undefined && parsed.threshold !== null
      ? `${parsed.comparison_label} ${formatNumber(parsed.threshold)}`
      : "None"],
    ["Opponent", parsed.opponent_name || "Any"],
    ["Season", seasonValue]
  ];

  cards.forEach(([label, value]) => {
    elements.interpretationGrid.appendChild(createInterpretationCard(label, `${value}`));
  });
}

function renderRows(rows) {
  if (!Array.isArray(rows) || !rows.length) {
    clearTable("No matching records found.");
    return;
  }

  const fragment = document.createDocumentFragment();
  rows.forEach((entry) => {
    const row = document.createElement("tr");

    const playerCell = document.createElement("td");
    if (entry.player_id) {
      const link = document.createElement("a");
      link.className = "table-link";
      link.href = playerProfileUrl(entry.player_id);
      link.textContent = entry.player_name || "Unknown player";
      playerCell.appendChild(link);
    } else {
      playerCell.textContent = entry.player_name || "Unknown player";
    }

    const cells = [
      playerCell,
      entry.squad_name || "--",
      entry.opponent || "--",
      formatNumber(entry.season),
      formatNumber(entry.round_number),
      formatNumber(entry.total_value),
      formatDate(entry.local_start_time)
    ];

    cells.forEach((cell) => {
      if (cell instanceof HTMLElement) {
        row.appendChild(cell);
      } else {
        const td = document.createElement("td");
        td.textContent = cell;
        row.appendChild(td);
      }
    });

    fragment.appendChild(row);
  });
  elements.queryRowsBody.replaceChildren(fragment);
  syncResponsiveTable(elements.queryRowsBody.closest("table"));
}

function renderUnsupported(result) {
  const reason = result.reason || "That question is outside the supported v1 grammar.";
  setSummaryCards("--", "--", "--", result.status === "ambiguous" ? "Ambiguous" : "Unsupported");
  elements.answerHeadline.textContent = reason;
  elements.answerMeta.textContent = "Try one of the examples above.";
  elements.interpretationGrid.replaceChildren();
  elements.queryState.hidden = false;
  elements.queryState.innerHTML = "";

  const title = document.createElement("strong");
  title.textContent = result.status === "ambiguous" ? "Need a more specific question" : "Supported question shapes";
  elements.queryState.appendChild(title);

  const message = document.createElement("p");
  message.textContent = reason;
  elements.queryState.appendChild(message);

  if (Array.isArray(result.candidates) && result.candidates.length) {
    const candidateList = document.createElement("p");
    candidateList.textContent = `Possible matches: ${result.candidates.join(", ")}`;
    elements.queryState.appendChild(candidateList);
  }

  const list = document.createElement("ul");
  const examples = Array.isArray(result.examples) && result.examples.length ? result.examples : [];
  examples.forEach((example) => {
    const item = document.createElement("li");
    item.textContent = example;
    list.appendChild(item);
  });
  elements.queryState.appendChild(list);

  elements.tableMeta.textContent = "";
  clearTable("Ask a supported question to see matching records.");
}

function renderResult(result) {
  if (!result || result.status !== "supported") {
    renderUnsupported(result || {});
    return;
  }

  const summary = result.summary || {};
  const parsed = result.parsed || {};

  setSummaryCards(
    QUERY_STATUS_LABELS[summary.question_type] || "--",
    formatNumber(summary.match_count),
    summary.stat_label || "--",
    "Supported"
  );
  elements.answerHeadline.textContent = result.answer || "No answer.";
  elements.answerMeta.textContent = "Generated from the parsed intent and the query template.";
  elements.queryState.hidden = true;
  renderInterpretation(parsed);
  renderRows(result.rows);
  elements.tableMeta.textContent = Array.isArray(result.rows) && result.rows.length
    ? `Showing ${result.rows.length} supporting row${result.rows.length === 1 ? "" : "s"} from ${formatNumber(summary.match_count)} matching performances.`
    : "No matching records.";
}

function updateUrl(question) {
  const url = new URL(window.location.href);
  if (question) {
    url.searchParams.set("q", question);
  } else {
    url.searchParams.delete("q");
  }
  window.history.replaceState({}, "", url);
}

let questionRunning = false;

async function runQuestion(question) {
  if (questionRunning) return;

  const trimmed = question.trim();
  if (!trimmed) {
    showStatus("Enter a question first.", "error");
    setIdleState();
    return;
  }

  questionRunning = true;
  const submitBtn = elements.queryForm.querySelector('[type="submit"]');
  if (submitBtn) {
    submitBtn.disabled = true;
    submitBtn.setAttribute("aria-busy", "true");
  }

  showStatus("Parsing and running the question…");
  setSummaryCards("…", "…", "…", "Running");

  try {
    const result = await fetchJson("/query", { question: trimmed, limit: 12 });
    renderResult(result);
    updateUrl(trimmed);
    showStatus(
      result.status === "supported"
        ? ""
        : "The parser could not safely support that wording yet.",
      result.status === "supported" ? "success" : "error"
    );
  } catch (error) {
    renderUnsupported({
      status: "unsupported",
      reason: error.message || "Something went wrong.",
      examples: [
        "How many times has Fowler scored 50 goals or more against the Vixens?",
        "What is Fowler's highest goals total against the Swifts?",
        "Which players scored 40+ goals in 2025?"
      ]
    });
    showStatus(error.message || "Something went wrong. Try again.", "error");
  } finally {
    questionRunning = false;
    if (submitBtn) {
      submitBtn.disabled = false;
      submitBtn.removeAttribute("aria-busy");
    }
  }
}

async function init() {
  setIdleState();

  try {
    const meta = await fetchJson("/meta");
    renderMeta(meta);
  } catch (error) {
    elements.querySeasonSummary.textContent = "Stats metadata unavailable. The parser may still work.";
  }

  const params = new URLSearchParams(window.location.search);
  const initialQuestion = params.get("q");
  if (initialQuestion) {
    elements.questionInput.value = initialQuestion;
    await runQuestion(initialQuestion);
  }
}

elements.queryForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  await runQuestion(elements.questionInput.value);
});

elements.clearQuestion.addEventListener("click", () => {
  elements.questionInput.value = "";
  showStatus("");
  updateUrl("");
  setIdleState();
});

elements.exampleStrip.addEventListener("click", async (event) => {
  const button = event.target.closest("[data-example]");
  if (!button) {
    return;
  }

  const example = button.getAttribute("data-example") || "";
  elements.questionInput.value = example;
  await runQuestion(example);
});

void init();
