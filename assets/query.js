const config = window.NETBALL_STATS_CONFIG || {};
const API_BASE_URL = (config.apiBaseUrl || "/api").replace(/\/$/, "");
const DEFAULT_TIMEOUT_MS = 30000;
const {
  cycleStatusBanner = () => {},
  formatStatLabel = (stat) => stat,
  syncResponsiveTable = () => {}
} = window.NetballStatsUI || {};
const {
  applyMetaConfig = () => {},
  bucketCount = () => "unknown",
  trackEvent = () => {}
} = window.NetballStatsTelemetry || {};
const QUERY_LOADING_MESSAGES = [
  "Parsing the question…",
  "Checking the supporting match totals…",
  "Drafting an answer from the archive…"
];
const QUERY_STATUS_LABELS = {
  count: "Count",
  highest: "Highest",
  lowest: "Lowest",
  list: "List"
};
const DEFAULT_QUERY_STATE = {
  title: "Supported questions",
  description: "Keep the wording literal so the parser can read it cleanly.",
  items: [
    "Player or team + stat + threshold + optional opponent/season",
    "Player or team + highest/lowest + stat + optional opponent/season",
    "List queries for players or teams meeting a stat filter"
  ]
};
const FALLBACK_EXAMPLES = [
  "How many times has Grace Nweke scored 50 goals or more against the Vixens?",
  "What is Liz Watson's highest goal assist total against the Firebirds?",
  "Which players had 5+ gains in 2025?",
  "Which teams had the lowest general play turnovers in 2025?"
];
const TABLE_SCHEMAS = {
  player: {
    caption: "Matching player performances",
    columns: ["Player", "Team", "Opponent", "Season", "Round", "Stat total", "Local start"]
  },
  team: {
    caption: "Matching team performances",
    columns: ["Team", "Opponent", "Season", "Round", "Stat total", "Local start"]
  }
};

const elements = {
  apiBase: document.getElementById("api-base"),
  heroSeasonRange: document.getElementById("hero-season-range"),
  querySeasonSummary: document.getElementById("query-season-summary"),
  queryStatus: document.getElementById("query-status"),
  queryForm: document.getElementById("query-form"),
  questionInput: document.getElementById("question-input"),
  questionCharacterCount: document.getElementById("question-character-count"),
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
  queryTable: document.getElementById("query-table"),
  queryTableCaption: document.getElementById("query-table-caption"),
  queryTableHead: document.getElementById("query-table-head"),
  queryRowsBody: document.getElementById("query-rows-body")
};

elements.submitButton = elements.queryForm.querySelector('[type="submit"]');

const exampleButtons = Array.from(elements.exampleStrip.querySelectorAll("[data-example]"));
const submitButtonDefaultLabel = elements.submitButton?.textContent || "Run question";

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

function showStatus(message, tone = "neutral", options = {}) {
  if (!message) {
    window.NetballStatsUI?.showStatusBanner?.(elements.queryStatus, "");
    return;
  }
  window.NetballStatsUI?.showStatusBanner?.(elements.queryStatus, message, tone, options);
}

function showLoadingStatus(messages, kicker) {
  cycleStatusBanner(elements.queryStatus, messages, {
    tone: "loading",
    kicker
  });
}

function normalizeQuerySubjectType(subjectType = "player") {
  return subjectType === "team" || subjectType === "teams" ? "team" : "player";
}

function setTableSchema(subjectType = "player") {
  const schema = TABLE_SCHEMAS[normalizeQuerySubjectType(subjectType)] || TABLE_SCHEMAS.player;
  if (elements.queryTableCaption) {
    elements.queryTableCaption.textContent = schema.caption;
  }
  if (elements.queryTableHead) {
    const row = document.createElement("tr");
    schema.columns.forEach((label) => {
      const th = document.createElement("th");
      th.scope = "col";
      th.textContent = label;
      row.appendChild(th);
    });
    elements.queryTableHead.replaceChildren(row);
  }
  syncResponsiveTable(elements.queryTable);
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
  cell.colSpan = elements.queryTableHead?.querySelectorAll("th").length || 1;
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

function renderQueryState({ title, description, items = [], extraParagraphs = [] }) {
  elements.queryState.replaceChildren();

  const titleElement = document.createElement("strong");
  titleElement.textContent = title;
  elements.queryState.appendChild(titleElement);

  if (description) {
    const descriptionElement = document.createElement("p");
    descriptionElement.textContent = description;
    elements.queryState.appendChild(descriptionElement);
  }

  extraParagraphs.forEach((paragraph) => {
    if (!paragraph) {
      return;
    }

    const paragraphElement = document.createElement("p");
    paragraphElement.textContent = paragraph;
    elements.queryState.appendChild(paragraphElement);
  });

  if (items.length) {
    const list = document.createElement("ul");
    items.forEach((item) => {
      const listItem = document.createElement("li");
      listItem.textContent = item;
      list.appendChild(listItem);
    });
    elements.queryState.appendChild(list);
  }
}

function renderDefaultQueryState() {
  renderQueryState(DEFAULT_QUERY_STATE);
}

function updateQuestionComposerState(value = "") {
  if (elements.questionCharacterCount) {
    elements.questionCharacterCount.textContent = `${value.length} / 220 characters`;
  }

  elements.clearQuestion.disabled = value.trim().length === 0;

  exampleButtons.forEach((button) => {
    const isActive = button.getAttribute("data-example") === value;
    button.setAttribute("aria-pressed", isActive ? "true" : "false");
  });
}

function setIdleState() {
  setTableSchema("player");
  setSummaryCards();
  elements.answerHeadline.textContent = "Ask a question to see the answer.";
  elements.answerMeta.textContent = "Answers come from the parsed query and matching rows.";
  elements.interpretationGrid.replaceChildren();
  renderDefaultQueryState();
  elements.queryState.hidden = false;
  elements.tableMeta.textContent = "";
  clearTable("Ask a question to see matching rows.");
  updateQuestionComposerState(elements.questionInput.value);
}

function renderMeta(meta) {
  if (!meta || !Array.isArray(meta.seasons) || !meta.seasons.length) {
    elements.querySeasonSummary.textContent = "Count, highest/lowest, and list questions across the archive.";
    return;
  }

  const seasons = [...meta.seasons].sort((left, right) => left - right);
  if (elements.heroSeasonRange) elements.heroSeasonRange.textContent = seasons[0] + "\u2013" + seasons[seasons.length - 1];
  elements.querySeasonSummary.textContent = `${seasons[0]}-${seasons[seasons.length - 1]} archive · ${meta.player_stats.length} player stats · ${meta.team_stats.length} team stats.`;
}

function renderInterpretation(parsed = {}) {
  elements.interpretationGrid.replaceChildren();
  const seasonValue = Array.isArray(parsed.seasons) && parsed.seasons.length
    ? parsed.seasons.join(", ")
    : (parsed.season || "All seasons");
  const subjectType = normalizeQuerySubjectType(parsed.subject_type);
  const subjectValue = parsed.player_name
    || parsed.team_name
    || (parsed.subject_type === "players" ? "Players" : (parsed.subject_type === "teams" ? "Teams" : "--"));
  const statValue = parsed.stat ? formatStatLabel(parsed.stat) : (parsed.stat_label || "--");

  const cards = [
    ["Question type", QUERY_STATUS_LABELS[parsed.intent_type] || "--"],
    ["Subject", subjectValue],
    ["Subject type", subjectType === "team" ? "Team" : "Player"],
    ["Stat", statValue],
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

function renderRows(rows, subjectType = "player") {
  if (!Array.isArray(rows) || !rows.length) {
    clearTable("No matching records found.");
    return;
  }

  const normalizedSubjectType = normalizeQuerySubjectType(subjectType);
  const fragment = document.createDocumentFragment();
  rows.forEach((entry) => {
    const row = document.createElement("tr");

    let cells;
    if (normalizedSubjectType === "team") {
      cells = [
        entry.squad_name || entry.team_name || "Unknown team",
        entry.opponent || "--",
        entry.season != null ? String(entry.season) : "--",
        formatNumber(entry.round_number),
        formatNumber(entry.total_value),
        formatDate(entry.local_start_time)
      ];
    } else {
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

      cells = [
        playerCell,
        entry.squad_name || "--",
        entry.opponent || "--",
        entry.season != null ? String(entry.season) : "--",
        formatNumber(entry.round_number),
        formatNumber(entry.total_value),
        formatDate(entry.local_start_time)
      ];
    }

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
  const reason = result.reason || "That question is outside the current parser.";
  setTableSchema("player");
  setSummaryCards("--", "--", "--", result.status === "ambiguous" ? "Ambiguous" : "Unsupported");
  elements.answerHeadline.textContent = reason;
  elements.answerMeta.textContent = "Try one of the examples above.";
  elements.interpretationGrid.replaceChildren();
  elements.queryState.hidden = false;
  renderQueryState({
    title: result.status === "ambiguous" ? "Need a more specific question" : "Supported questions",
    description: reason,
    extraParagraphs: Array.isArray(result.candidates) && result.candidates.length
      ? [`Possible matches: ${result.candidates.join(", ")}`]
      : [],
    items: Array.isArray(result.examples) && result.examples.length ? result.examples : FALLBACK_EXAMPLES
  });

  elements.tableMeta.textContent = "";
  clearTable("Ask a supported question to see matching rows.");
}

function renderResult(result) {
  if (!result || result.status !== "supported") {
    renderUnsupported(result || {});
    return;
  }

  const summary = result.summary || {};
  const parsed = result.parsed || {};
  const subjectType = normalizeQuerySubjectType(parsed.subject_type);

  setSummaryCards(
    QUERY_STATUS_LABELS[summary.question_type] || "--",
    formatNumber(summary.match_count),
    parsed.stat ? formatStatLabel(parsed.stat) : (summary.stat_label || "--"),
    "Supported"
  );
  elements.answerHeadline.textContent = result.answer || "No answer.";
  elements.answerMeta.textContent = "Built from the parsed query and matching rows.";
  elements.queryState.hidden = true;
  setTableSchema(subjectType);
  renderInterpretation(parsed);
  renderRows(result.rows, subjectType);
  elements.tableMeta.textContent = Array.isArray(result.rows) && result.rows.length
    ? `Showing ${result.rows.length} row${result.rows.length === 1 ? "" : "s"} from ${formatNumber(summary.match_count)} matching performance${summary.match_count === 1 ? "" : "s"}.`
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

async function runQuestion(question, source = "manual") {
  if (questionRunning) return;

  const trimmed = question.trim();
  if (!trimmed) {
    showStatus("Enter a question first.", "error");
    setIdleState();
    return;
  }

  questionRunning = true;
  const submitBtn = elements.submitButton;
  if (submitBtn) {
    submitBtn.disabled = true;
    submitBtn.setAttribute("aria-busy", "true");
    submitBtn.textContent = "Running…";
  }

  showLoadingStatus(QUERY_LOADING_MESSAGES, "Reading archive");
  setSummaryCards("…", "…", "…", "Running");
  trackEvent("ask_stats_submitted", {
    source,
    question_length_bucket: bucketCount(trimmed.length, [0, 20, 40, 80, 120, 180])
  });

  try {
    const result = await fetchJson("/query", { question: trimmed, limit: 12 });
    renderResult(result);
    updateUrl(trimmed);
    trackEvent("ask_stats_completed", {
      source,
      outcome: result.status === "supported" ? "supported" : (result.status || "unsupported"),
      question_type: result.summary?.question_type || result.parsed?.intent_type || "unknown",
      stat: result.parsed?.stat || result.summary?.stat_label || "unknown",
      subject_type: result.parsed?.subject_type || "unknown",
      has_opponent_filter: Boolean(result.parsed?.opponent_name),
      season_count_bucket: Array.isArray(result.parsed?.seasons)
        ? bucketCount(result.parsed.seasons.length, [0, 1, 2, 3, 5])
        : "all_or_unspecified",
      match_count_bucket: bucketCount(result.summary?.match_count, [0, 1, 2, 5, 10, 25, 50, 100])
    });
    showStatus(
      result.status === "supported"
        ? "Answer ready."
        : "That wording is not supported yet.",
      result.status === "supported" ? "success" : "error",
      result.status === "supported"
        ? { kicker: "Ready", autoHideMs: 2200 }
        : { kicker: "Parser limit" }
    );
  } catch (error) {
    renderUnsupported({
      status: "unsupported",
      reason: error.message || "Something went wrong.",
      examples: [
        "How many times has Fowler scored 50 goals or more against the Vixens?",
        "What is Liz Watson's highest goal assist total against the Firebirds?",
        "Which teams had the lowest general play turnovers in 2025?"
      ]
    });
    trackEvent("ask_stats_completed", {
      source,
      outcome: "error"
    });
    showStatus(error.message || "Something went wrong. Try again.", "error", { kicker: "Question interrupted" });
  } finally {
    questionRunning = false;
    if (submitBtn) {
      submitBtn.disabled = false;
      submitBtn.removeAttribute("aria-busy");
      submitBtn.textContent = submitButtonDefaultLabel;
    }
  }
}

async function init() {
  setIdleState();

  try {
    const meta = await fetchJson("/meta");
    applyMetaConfig(meta);
    renderMeta(meta);
  } catch (error) {
    elements.querySeasonSummary.textContent = "Metadata unavailable. The parser may still work.";
  }

  const params = new URLSearchParams(window.location.search);
  const initialQuestion = params.get("q");
  if (initialQuestion) {
    elements.questionInput.value = initialQuestion;
    updateQuestionComposerState(initialQuestion);
    await runQuestion(initialQuestion, "url");
    return;
  }

  updateQuestionComposerState(elements.questionInput.value);
}

elements.queryForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  await runQuestion(elements.questionInput.value, "manual");
});

elements.questionInput.addEventListener("input", () => {
  updateQuestionComposerState(elements.questionInput.value);
});

elements.clearQuestion.addEventListener("click", () => {
  const previousQuestion = elements.questionInput.value || "";
  elements.questionInput.value = "";
  showStatus("");
  updateUrl("");
  setIdleState();
  trackEvent("ask_stats_cleared", {
    previous_question_length_bucket: bucketCount(previousQuestion.length, [0, 20, 40, 80, 120, 180])
  });
});

elements.exampleStrip.addEventListener("click", async (event) => {
  const button = event.target.closest("[data-example]");
  if (!button) {
    return;
  }

  const example = button.getAttribute("data-example") || "";
  elements.questionInput.value = example;
  updateQuestionComposerState(example);
  await runQuestion(example, "example");
});

void init();
