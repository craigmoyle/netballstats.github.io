const config = window.NETBALL_STATS_CONFIG || {};
const API_BASE_URL = (config.apiBaseUrl || "/api").replace(/\/$/, "");
const {
  buildUrl,
  clearEmptyTableState = () => {},
  fetchJson,
  formatDate,
  formatNumber,
  formatStatLabel = (stat) => stat,
  playerProfileUrl = (playerId) => `/player/${encodeURIComponent(playerId)}/`,
  renderEmptyTableRow = () => {},
  showElementLoadingStatus = () => {},
  showElementStatus = () => {},
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
  title: "Supported question shapes",
  description: "Keep the wording literal and stick to match totals the parser can trace end to end.",
  items: [
    "Player or team + stat + threshold + optional opponent or season",
    "Player or team + highest or lowest + stat + optional opponent or season",
    "List players or teams meeting a stat filter in a season"
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

const QUERY_TEMPLATES = {
  'head-to-head': {
    label: 'Head-to-Head',
    description: 'Compare Vixens vs Swifts goals in 2025',
    query: 'How many goals did Vixens score vs Swifts in 2025?'
  },
  'player-combo': {
    label: 'Player Combo',
    description: 'Combine stats from multiple players',
    query: 'What is Tara Hinchliffe and Taryn Aiken combined feeds in 2024?'
  },
  'alltime-record': {
    label: 'Record Holder',
    description: 'Find the all-time record for a stat',
    query: 'Which player has the highest total points all-time?'
  },
  'multi-team': {
    label: 'Multi-Team Gains',
    description: 'Compare defensive gains across teams',
    query: 'How many defensive gains did Vixens, Swifts, and Magpies record in 2025?'
  },
  'quarter-penalties': {
    label: 'Quarter Breakdown',
    description: 'See penalty trends by quarter',
    query: 'What is Vixens penalties by quarter in 2025?'
  },
  'rising-stars': {
    label: 'Rising Stars',
    description: 'Track emerging players defensive stats',
    query: 'Which young players had the most intercepts in 2024?'
  }
};

const elements = {
  apiBase: document.getElementById("api-base"),
  heroSeasonRange: document.getElementById("hero-season-range"),
  querySeasonSummary: document.getElementById("query-season-summary"),
  queryStatus: document.getElementById("query-status"),
  queryForm: document.getElementById("query-form"),
  queryStepShape: document.getElementById("query-step-shape"),
  queryStepCompose: document.getElementById("query-step-compose"),
  queryStepRun: document.getElementById("query-step-run"),
  queryTemplateStrip: document.getElementById("query-template-strip"),
  queryRunwayHint: document.getElementById("query-runway-hint"),
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
  queryHelp: document.getElementById("query-help"),
  queryHelpSummary: document.getElementById("query-help-summary"),
  queryState: document.getElementById("query-state"),
  tableMeta: document.getElementById("table-meta"),
  queryTable: document.getElementById("query-table"),
  queryTableCaption: document.getElementById("query-table-caption"),
  queryTableHead: document.getElementById("query-table-head"),
  queryRowsBody: document.getElementById("query-rows-body"),
  errorBanner: document.getElementById("error-banner"),
  errorBannerMessage: document.getElementById("error-banner-message"),
  errorBannerActions: document.getElementById("error-banner-actions")
};

elements.submitButton = elements.queryForm.querySelector('[type="submit"]');

const exampleButtons = Array.from(elements.exampleStrip.querySelectorAll("[data-example]"));
const templateButtons = Array.from((elements.queryTemplateStrip?.querySelectorAll("[data-template]")) || []);
const submitButtonDefaultLabel = elements.submitButton?.textContent || "Run question";

// Builder modal elements
const builderElements = {
  modal: document.getElementById("query-builder-modal"),
  form: document.getElementById("builder-form"),
  closeBtn: document.querySelector(".builder-modal__close"),
  nextBtn: document.getElementById("builder-next"),
  prevBtn: document.getElementById("builder-prev"),
  submitBtn: document.getElementById("builder-submit"),
  addSubjectBtn: document.getElementById("builder-add-subject"),
  
  // Step elements
  stepShape: document.getElementById("builder-step-shape"),
  stepSubjects: document.getElementById("builder-step-subjects"),
  stepStat: document.getElementById("builder-step-stat"),
  stepFilters: document.getElementById("builder-step-filters"),
  stepTimeframe: document.getElementById("builder-step-timeframe"),
  
  // Subject selection
  subjectSearch: document.getElementById("builder-subject-search"),
  subjectList: document.getElementById("builder-subject-list"),
  
  // Stat selection
  statSearch: document.getElementById("builder-stat-search"),
  statList: document.getElementById("builder-stat-list"),
  
  // Filters
  filterOpponent: document.getElementById("builder-filter-opponent"),
  filterLocation: document.getElementById("builder-filter-location"),
  filterGames: document.getElementById("builder-filter-games"),
  
  // Timeframe
  timeframeSingle: document.getElementById("builder-timeframe-single"),
  timeframeRange: document.getElementById("builder-timeframe-range"),
  seasonSingle: document.getElementById("builder-season-single"),
  seasonFrom: document.getElementById("builder-season-from"),
  seasonTo: document.getElementById("builder-season-to")
};

// Builder state
let builderState = {
  currentStep: 1,
  shape: null,
  subjects: [],
  stat: null,
  filters: {},
  timeframe: null,
  seasonSingle: null,
  seasonRange: null,
  availableSeasons: [],
  availableSubjects: []
};

if (elements.apiBase) {
  elements.apiBase.textContent = API_BASE_URL;
}

function showErrorBanner(message) {
  if (!elements.errorBanner) return;
  elements.errorBanner.hidden = false;
  if (elements.errorBannerMessage) {
    elements.errorBannerMessage.textContent = message;
  }
}

function hideErrorBanner() {
  if (!elements.errorBanner) return;
  elements.errorBanner.hidden = true;
  if (elements.errorBannerMessage) {
    elements.errorBannerMessage.textContent = "";
  }
  if (elements.errorBannerActions) {
    elements.errorBannerActions.replaceChildren();
  }
}

function showBuilderButton(prefill) {
  if (!elements.errorBannerActions) return;
  elements.errorBannerActions.replaceChildren();

  const button = document.createElement("button");
  button.type = "button";
  button.className = "button button--primary";
  button.textContent = "Use the builder";
  button.addEventListener("click", () => {
    openBuilderModal(prefill);
  });

  elements.errorBannerActions.appendChild(button);
}

function openBuilderModal(prefill) {
  const event = new CustomEvent("open-builder-modal", {
    detail: { prefill }
  });
  window.dispatchEvent(event);
}

function rephraseSuggestion(suggestion) {
  applyQuestionText(suggestion, { focus: true });
  void runQuestion(suggestion, "suggestion");
}

function attemptComplexParse(question) {
  if (!question || typeof question !== "string") {
    return null;
  }

  const trimmed = question.trim().toLowerCase();
  const confidence = { score: 0 };

  let intentType = null;
  let subjects = [];
  let stat = null;
  let filters = [];
  let seasons = null;
  let operator = "AND";

  const comparisonMarkers = /\bvs\b|\bversus\b|\bcompared to\b|\bvs\./i;
  const trendMarkers = /\bacross\b|\btrend\b/i;
  const recordMarkers = /\ball[- ]?time\b|\bever\b|\branking\b|\brecord\b/i;
  const seasonPattern = /\b(20\d{2})\b/g;
  const seasonRangePattern = /\b(20\d{2})\s*[-–]\s*(20\d{2})\b/;
  const logicalOpPattern = /\b(and|or)\b/i;

  if (comparisonMarkers.test(trimmed)) {
    intentType = "comparison";
    confidence.score += 0.25;
  } else if (recordMarkers.test(trimmed)) {
    intentType = "record";
    confidence.score += 0.25;
  } else if (trendMarkers.test(trimmed) || /\bacross\s+(20\d{2})/.test(trimmed)) {
    intentType = "trend";
    confidence.score += 0.25;
  } else if (logicalOpPattern.test(trimmed) && (trimmed.includes("and ") || trimmed.includes("or "))) {
    intentType = "combination";
    confidence.score += 0.25;
  }

  if (intentType && /\b\d+\+/.test(trimmed)) {
    confidence.score += 0.1;
  }

  const seasonMatches = trimmed.match(seasonPattern);
  if (seasonMatches && seasonMatches.length > 0) {
    seasons = [...new Set(seasonMatches.map(Number))].sort();
    confidence.score += 0.15;
  }

  const seasonRangeMatch = trimmed.match(seasonRangePattern);
  if (seasonRangeMatch) {
    const startYear = parseInt(seasonRangeMatch[1], 10);
    const endYear = parseInt(seasonRangeMatch[2], 10);
    seasons = [];
    for (let year = startYear; year <= endYear; year++) {
      seasons.push(year);
    }
    confidence.score += 0.15;
  }

  if (intentType === "record" || !intentType) {
    return null;
  }

  confidence.score = Math.min(confidence.score, 1.0);

  return {
    intentType,
    subjects,
    stat,
    filters,
    seasons,
    operator,
    confidence: confidence.score
  };
}

function showStatus(message, tone = "neutral", options = {}) {
  showElementStatus(elements.queryStatus, message, tone, options);
}

function showLoadingStatus(messages, kicker) {
  showElementLoadingStatus(elements.queryStatus, messages, kicker);
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

function clearTable(message) {
  renderEmptyTableRow(elements.queryRowsBody, message);
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
  if (elements.queryHelpSummary) {
    elements.queryHelpSummary.textContent = "Question patterns";
  }
}

function setStepState(element, stepState) {
  if (element) {
    element.setAttribute("data-step-state", stepState);
  }
}

function containsTemplatePlaceholders(value = "") {
  return /\[[^\]]+\]/.test(value);
}

function updateQuestionWorkflowState(value = "") {
  const trimmed = value.trim();
  const hasText = Boolean(trimmed);
  const hasPlaceholders = containsTemplatePlaceholders(value);

  setStepState(elements.queryStepShape, hasText ? "ready" : "active");
  setStepState(elements.queryStepCompose, hasText && !hasPlaceholders ? "ready" : "active");
  setStepState(elements.queryStepRun, hasText && !hasPlaceholders ? "active" : "pending");

  if (!elements.queryRunwayHint) {
    return;
  }

  if (!hasText) {
    elements.queryRunwayHint.textContent = "Choose a template or write one literal question before you run it.";
    return;
  }

  if (hasPlaceholders) {
    elements.queryRunwayHint.textContent = "Replace the bracketed placeholders with real names, stats, thresholds, or seasons before you run it.";
    return;
  }

  elements.queryRunwayHint.textContent = "Ready to run. The answer card and evidence table will update together.";
}

function updateQuestionComposerState(value = "") {
  const trimmed = value.trim();
  const hasPlaceholders = containsTemplatePlaceholders(value);

  if (elements.questionCharacterCount) {
    elements.questionCharacterCount.textContent = `${value.length} / 220 characters`;
  }

  elements.clearQuestion.disabled = trimmed.length === 0;

  exampleButtons.forEach((button) => {
    const isActive = button.getAttribute("data-example") === value;
    button.setAttribute("aria-pressed", isActive ? "true" : "false");
  });

  templateButtons.forEach((button) => {
    const isActive = button.getAttribute("data-template") === value;
    button.setAttribute("aria-pressed", isActive ? "true" : "false");
  });

  if (elements.submitButton && !questionRunning) {
    elements.submitButton.disabled = trimmed.length === 0 || hasPlaceholders;
  }

  updateQuestionWorkflowState(value);
}

function applyQuestionText(question, { focus = true } = {}) {
  elements.questionInput.value = question;
  updateQuestionComposerState(question);
  if (focus) {
    elements.questionInput.focus();
    elements.questionInput.setSelectionRange(question.length, question.length);
  }
}

function setIdleState() {
  hideErrorBanner();
  setTableSchema("player");
  setSummaryCards("--", "--", "--", "Choose a shape");
  elements.answerHeadline.textContent = "Choose a template or ask a literal question.";
  elements.answerMeta.textContent = "The answer card and evidence table will update together once the wording is specific enough for the parser.";
  elements.interpretationGrid.replaceChildren();
  renderDefaultQueryState();
  if (elements.queryHelp) {
    elements.queryHelp.hidden = false;
    elements.queryHelp.open = false;
  }
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
  const firstFullSeason = seasons.length > 1 ? seasons[1] : seasons[0];
  if (elements.heroSeasonRange) elements.heroSeasonRange.textContent = `${seasons[0]} finals + ${firstFullSeason}\u2013${seasons[seasons.length - 1]}`;
  elements.querySeasonSummary.textContent = `${seasons[0]} finals only · full seasons ${firstFullSeason}-${seasons[seasons.length - 1]} · ${meta.player_stats.length} player stats · ${meta.team_stats.length} team stats.`;
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
  clearEmptyTableState(elements.queryRowsBody);
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
        formatDate(entry.local_start_time, { includeTime: true })
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
        formatDate(entry.local_start_time, { includeTime: true })
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
  elements.answerMeta.textContent = "Stay literal: subject + stat + request type. The guide below shows supported shapes and complete examples.";
  elements.interpretationGrid.replaceChildren();
  if (elements.queryHelpSummary) {
    elements.queryHelpSummary.textContent = result.status === "ambiguous"
      ? "Need a tighter prompt?"
      : "Rewrite it in a supported shape";
  }
  renderQueryState({
    title: result.status === "ambiguous" ? "Tighten the wording" : "Rewrite the question in one supported shape",
    description: reason,
    extraParagraphs: Array.isArray(result.candidates) && result.candidates.length
      ? [`Possible matches: ${result.candidates.join(", ")}`]
      : [],
    items: Array.isArray(result.examples) && result.examples.length ? result.examples : FALLBACK_EXAMPLES
  });
  if (elements.queryHelp) {
    elements.queryHelp.hidden = false;
    elements.queryHelp.open = true;
  }

  elements.tableMeta.textContent = "";
  clearTable("Use a supported question shape to see matching rows.");
}

function renderResult(result) {
  hideErrorBanner();

  if (!result) {
    renderUnsupported({});
    return;
  }

  if (result.status === "parse_help_needed") {
    const message = result.error_message || "I couldn't match all the parts of that question. Try rephrasing or use the builder to construct it step-by-step.";
    showErrorBanner(message);

    if (result.suggestion) {
      const actions = elements.errorBannerActions;
      if (actions) {
        actions.replaceChildren();

        const suggestionLink = document.createElement("button");
        suggestionLink.type = "button";
        suggestionLink.className = "button button--ghost";
        suggestionLink.textContent = `Try: "${result.suggestion}"`;
        suggestionLink.addEventListener("click", () => {
          rephraseSuggestion(result.suggestion);
        });

        actions.appendChild(suggestionLink);

        if (result.builder_prefill) {
          showBuilderButton(result.builder_prefill);
        }
      }
    }

    setTableSchema("player");
    setSummaryCards("--", "--", "--", "Help needed");
    elements.answerHeadline.textContent = "Try a different approach or use the builder.";
    elements.answerMeta.textContent = "";
    elements.interpretationGrid.replaceChildren();
    clearTable("No results yet. Use the builder or rephrase your question.");
    return;
  }

  if (result.status !== "supported") {
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
  elements.answerMeta.textContent = "Transparent answer with the matching evidence table below.";
  if (elements.queryHelp) {
    elements.queryHelp.open = false;
  }
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

async function tryParseQuestion(question) {
  try {
    const response = await fetch(buildUrl("/query/parse"), {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json"
      },
      body: JSON.stringify({ question })
    });

    if (!response.ok) {
      return { success: false, error: "Parser request failed" };
    }

    const data = await response.json();
    return data;
  } catch (error) {
    return { success: false, error: error.message || "Parse request error" };
  }
}

async function runQuestion(question, source = "manual") {
  if (questionRunning) return;

  const trimmed = question.trim();
  if (!trimmed) {
    showStatus("Enter a question first.", "error");
    setIdleState();
    return;
  }

  if (containsTemplatePlaceholders(trimmed)) {
    showStatus("Replace the bracketed placeholders before running the question.", "error", { kicker: "Template incomplete" });
    updateQuestionComposerState(trimmed);
    return;
  }

  hideErrorBanner();

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
    // Try to parse the question to provide UX feedback
    const parseResult = await tryParseQuestion(trimmed);
    let parseInfo = {};
    if (parseResult.success && parseResult.parsed) {
      parseInfo = parseResult.parsed;
    }

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
        : (result.status === "parse_help_needed" ? "I need clarification." : "That wording is not supported yet."),
      result.status === "supported" ? "success" : "error",
      result.status === "supported"
        ? { kicker: "Ready", autoHideMs: 2200 }
        : { kicker: result.status === "parse_help_needed" ? "Need help" : "Parser limit" }
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
      submitBtn.removeAttribute("aria-busy");
      submitBtn.textContent = submitButtonDefaultLabel;
    }
    updateQuestionComposerState(elements.questionInput.value);
  }
}

// ============================================================================
// Builder Modal Functions
// ============================================================================

function resetBuilderState() {
  builderState = {
    currentStep: 1,
    shape: null,
    subjects: [],
    stat: null,
    filters: {},
    timeframe: null,
    seasonSingle: null,
    seasonRange: null,
    availableSeasons: [],
    availableSubjects: []
  };
}

function showBuilderStep(stepNum) {
  const steps = [
    builderElements.stepShape,
    builderElements.stepSubjects,
    builderElements.stepStat,
    builderElements.stepFilters,
    builderElements.stepTimeframe
  ];

  steps.forEach((step, idx) => {
    if (step) {
      step.hidden = idx !== stepNum - 1;
    }
  });

  builderState.currentStep = stepNum;
  updateBuilderFooter();
}

function updateBuilderFooter() {
  const isFirstStep = builderState.currentStep === 1;
  const isLastStep = builderState.currentStep === 5;

  if (builderElements.prevBtn) {
    builderElements.prevBtn.hidden = isFirstStep;
  }
  if (builderElements.nextBtn) {
    builderElements.nextBtn.hidden = isLastStep;
  }
  if (builderElements.submitBtn) {
    builderElements.submitBtn.hidden = !isLastStep;
  }
}

function validateBuilderStep(stepNum) {
  switch (stepNum) {
    case 1: // Shape
      return !!builderState.shape;
    case 2: // Subjects
      return builderState.subjects && builderState.subjects.length > 0;
    case 3: // Stat
      return !!builderState.stat;
    case 4: // Filters (optional)
      return true;
    case 5: // Timeframe
      if (!builderState.timeframe) return false;
      if (builderState.timeframe === "single") {
        return !!builderState.seasonSingle;
      } else if (builderState.timeframe === "range") {
        return !!(builderState.seasonRange && builderState.seasonRange.from && builderState.seasonRange.to);
      }
      return true;
    default:
      return false;
  }
}

function getValidationErrorMessage(step) {
  switch (step) {
    case 1: return "Please select a query shape to continue.";
    case 2: return "Please select at least one subject to continue.";
    case 3: return "Please select a stat to continue.";
    case 4: return ""; // Filters are optional
    case 5: return "Please select a timeframe to continue.";
    default: return "Please complete this step.";
  }
}

function showBuilderValidationError(message) {
  const errorRegion = document.getElementById("builder-validation-errors");
  if (errorRegion) {
    errorRegion.textContent = message;
    errorRegion.style.display = "block";
    // Clear after 5 seconds
    setTimeout(() => {
      errorRegion.textContent = "";
      errorRegion.style.display = "none";
    }, 5000);
  }
}

function nextBuilderStep() {
  if (!validateBuilderStep(builderState.currentStep)) {
    // Show error message
    showBuilderValidationError(getValidationErrorMessage(builderState.currentStep));
    return;
  }
  if (builderState.currentStep < 5) {
    showBuilderStep(builderState.currentStep + 1);
  }
}

function prevBuilderStep() {
  if (builderState.currentStep > 1) {
    showBuilderStep(builderState.currentStep - 1);
  }
}

function getStatsList() {
  const stats = window.NetballStatsUI?.STAT_LABEL_OVERRIDES || {};
  return Object.keys(stats);
}

function renderBuilderShapeOptions() {
  const shapes = ["comparison", "combination", "trend", "record", "count", "highest", "lowest", "list"];
  const radios = builderElements.stepShape.querySelectorAll('input[name="shape"]');
  
  radios.forEach((radio) => {
    radio.addEventListener("change", () => {
      builderState.shape = radio.value;
      
      // For comparison, allow multi-select; others single
      const isComparison = builderState.shape === "comparison";
      if (builderElements.addSubjectBtn) {
        builderElements.addSubjectBtn.hidden = !isComparison;
      }
      
      nextBuilderStep();
    });
  });
}

function renderBuilderSubjectOptions() {
  if (!builderElements.subjectList) return;

  const subjects = builderState.availableSubjects || [];
  const filtered = (builderElements.subjectSearch?.value || "").toLowerCase();
  const matched = filtered
    ? subjects.filter(s => s.toLowerCase().includes(filtered))
    : subjects;

  builderElements.subjectList.replaceChildren();

  matched.forEach((subject) => {
    const isMulti = builderState.shape === "comparison";
    const label = document.createElement("label");
    label.className = "builder-subject-option";
    
    const input = document.createElement("input");
    input.type = isMulti ? "checkbox" : "radio";
    input.name = isMulti ? "subjects" : "subject-single";
    input.value = subject;
    
    input.addEventListener("change", () => {
      if (isMulti) {
        if (input.checked) {
          if (!builderState.subjects.includes(subject)) {
            builderState.subjects.push(subject);
          }
        } else {
          builderState.subjects = builderState.subjects.filter(s => s !== subject);
        }
      } else {
        builderState.subjects = [subject];
      }
    });

    const span = document.createElement("span");
    span.textContent = subject;

    label.appendChild(input);
    label.appendChild(span);
    builderElements.subjectList.appendChild(label);
  });
}

function renderBuilderStatOptions() {
  if (!builderElements.statList) return;

  const stats = getStatsList();
  const filtered = (builderElements.statSearch?.value || "").toLowerCase();
  const matched = filtered
    ? stats.filter(s => s.toLowerCase().includes(filtered) || formatStatLabel(s).toLowerCase().includes(filtered))
    : stats;

  builderElements.statList.replaceChildren();

  matched.forEach((stat) => {
    const label = document.createElement("label");
    label.className = "builder-stat-option";
    
    const input = document.createElement("input");
    input.type = "radio";
    input.name = "stat";
    input.value = stat;
    
    input.addEventListener("change", () => {
      builderState.stat = stat;
    });

    const span = document.createElement("span");
    span.textContent = formatStatLabel(stat);

    label.appendChild(input);
    label.appendChild(span);
    builderElements.statList.appendChild(label);
  });
}

function setupBuilderFilterListeners() {
  const filterCheckboxes = builderElements.form.querySelectorAll('[name^="filter-"]');
  
  filterCheckboxes.forEach((checkbox) => {
    checkbox.addEventListener("change", () => {
      const filterType = checkbox.value;
      
      if (checkbox.checked) {
        const filterInput = document.getElementById(`builder-filter-${filterType}`);
        if (filterInput) filterInput.hidden = false;
      } else {
        const filterInput = document.getElementById(`builder-filter-${filterType}`);
        if (filterInput) {
          filterInput.hidden = true;
          // Clear value
          const input = filterInput.querySelector("input, select");
          if (input) input.value = "";
        }
        delete builderState.filters[filterType];
      }
    });
  });
}

function setupBuilderTimeframeListeners() {
  const timeframeRadios = builderElements.form.querySelectorAll('[name="timeframe"]');
  
  timeframeRadios.forEach((radio) => {
    radio.addEventListener("change", () => {
      builderState.timeframe = radio.value;

      if (builderElements.timeframeSingle) {
        builderElements.timeframeSingle.hidden = radio.value !== "single";
      }
      if (builderElements.timeframeRange) {
        builderElements.timeframeRange.hidden = radio.value !== "range";
      }
    });
  });

  // Season single select
  if (builderElements.seasonSingle) {
    builderElements.seasonSingle.addEventListener("change", () => {
      builderState.seasonSingle = builderElements.seasonSingle.value ? parseInt(builderElements.seasonSingle.value, 10) : null;
    });
  }

  // Season range selects
  if (builderElements.seasonFrom) {
    builderElements.seasonFrom.addEventListener("change", () => {
      if (!builderState.seasonRange) builderState.seasonRange = {};
      builderState.seasonRange.from = builderElements.seasonFrom.value ? parseInt(builderElements.seasonFrom.value, 10) : null;
    });
  }
  if (builderElements.seasonTo) {
    builderElements.seasonTo.addEventListener("change", () => {
      if (!builderState.seasonRange) builderState.seasonRange = {};
      builderState.seasonRange.to = builderElements.seasonTo.value ? parseInt(builderElements.seasonTo.value, 10) : null;
    });
  }
}

function populateBuilderSeasonSelects() {
  const seasons = builderState.availableSeasons.sort((a, b) => b - a); // Descending

  [builderElements.seasonSingle, builderElements.seasonFrom, builderElements.seasonTo].forEach((select) => {
    if (!select) return;
    const currentValue = select.value;
    select.replaceChildren();

    if (select === builderElements.seasonSingle) {
      const option = document.createElement("option");
      option.value = "";
      option.textContent = "Select season…";
      select.appendChild(option);
    } else {
      const option = document.createElement("option");
      option.value = "";
      option.textContent = select.id.includes("from") ? "From season…" : "To season…";
      select.appendChild(option);
    }

    seasons.forEach((season) => {
      const option = document.createElement("option");
      option.value = season;
      option.textContent = season;
      select.appendChild(option);
    });

    if (currentValue) select.value = currentValue;
  });
}

async function submitBuilderQuery() {
  const isValid = validateBuilderStep(5);
  if (!isValid) return;

  const formData = {
    shape: builderState.shape,
    subjects: builderState.subjects,
    stat: builderState.stat,
    filters: builderState.filters,
    timeframe: builderState.timeframe
  };

  if (builderState.timeframe === "single") {
    formData.seasons = builderState.seasonSingle ? [builderState.seasonSingle] : [];
  } else if (builderState.timeframe === "range") {
    const from = builderState.seasonRange?.from || 0;
    const to = builderState.seasonRange?.to || 0;
    formData.seasons = [];
    for (let i = from; i <= to; i++) {
      formData.seasons.push(i);
    }
  } else {
    formData.seasons = builderState.availableSeasons;
  }

  try {
    showLoadingStatus(QUERY_LOADING_MESSAGES, "Building query");

    // Convert builder query to natural language or construct API payload
    // For now, post builder_source flag
    const result = await fetchJson("/query", {
      builder_source: true,
      builder_query: formData,
      limit: 12
    });

    renderResult(result);
    closeBuilderModal();
  } catch (error) {
    renderUnsupported({
      status: "error",
      reason: error.message || "Builder query failed"
    });
    showStatus(error.message || "Builder query failed.", "error");
  }
}

function closeBuilderModal() {
  if (builderElements.modal) {
    builderElements.modal.close();
  }
}

function openBuilderModalUI(prefill = {}) {
  if (!builderElements.modal) return;

  resetBuilderState();

  // Prefill if provided
  if (prefill.shape) {
    builderState.shape = prefill.shape;
    const shapeRadio = builderElements.stepShape.querySelector(`input[value="${prefill.shape}"]`);
    if (shapeRadio) shapeRadio.checked = true;
  }

  if (prefill.subjects && Array.isArray(prefill.subjects)) {
    builderState.subjects = [...prefill.subjects];
  }

  if (prefill.stat) {
    builderState.stat = prefill.stat;
  }

  if (prefill.seasons && Array.isArray(prefill.seasons)) {
    if (prefill.seasons.length === 1) {
      builderState.timeframe = "single";
      builderState.seasonSingle = prefill.seasons[0];
    } else {
      builderState.timeframe = "range";
      builderState.seasonRange = {
        from: Math.min(...prefill.seasons),
        to: Math.max(...prefill.seasons)
      };
    }
  }

  showBuilderStep(1);
  builderElements.modal.showModal();
}

function setupBuilderEventListeners() {
  if (!builderElements.modal) return;

  // Close button
  if (builderElements.closeBtn) {
    builderElements.closeBtn.addEventListener("click", closeBuilderModal);
  }

  // Navigation buttons
  if (builderElements.nextBtn) {
    builderElements.nextBtn.addEventListener("click", nextBuilderStep);
  }
  if (builderElements.prevBtn) {
    builderElements.prevBtn.addEventListener("click", prevBuilderStep);
  }

  // Form submission
  if (builderElements.form) {
    builderElements.form.addEventListener("submit", (e) => {
      e.preventDefault();
      void submitBuilderQuery();
    });
  }

  // Add subject button for comparison
  if (builderElements.addSubjectBtn) {
    builderElements.addSubjectBtn.addEventListener("click", () => {
      // Focus subject search to add another
      if (builderElements.subjectSearch) {
        builderElements.subjectSearch.focus();
      }
    });
  }

  // Subject search
  if (builderElements.subjectSearch) {
    builderElements.subjectSearch.addEventListener("input", renderBuilderSubjectOptions);
  }

  // Stat search
  if (builderElements.statSearch) {
    builderElements.statSearch.addEventListener("input", renderBuilderStatOptions);
  }

  // Shape options
  renderBuilderShapeOptions();

  // Filters
  setupBuilderFilterListeners();

  // Timeframe
  setupBuilderTimeframeListeners();

  // Listen for custom event from error banner
  window.addEventListener("open-builder-modal", (event) => {
    const prefill = event.detail?.prefill || {};
    openBuilderModalUI(prefill);
  });

  // Close modal on Escape
  builderElements.modal.addEventListener("keydown", (e) => {
    if (e.key === "Escape") {
      closeBuilderModal();
    }
  });
}

async function loadBuilderMetadata() {
  try {
    const meta = await fetchJson("/meta");
    if (meta.seasons && Array.isArray(meta.seasons)) {
      builderState.availableSeasons = meta.seasons;
      populateBuilderSeasonSelects();
    }
    if (meta.players && Array.isArray(meta.players)) {
      builderState.availableSubjects = meta.players;
    } else if (meta.subjects && Array.isArray(meta.subjects)) {
      builderState.availableSubjects = meta.subjects;
    }
  } catch (error) {
    console.error("Failed to load builder metadata:", error);
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

  // Initialize builder modal
  await loadBuilderMetadata();
  setupBuilderEventListeners();

  const params = new URLSearchParams(window.location.search);
  const initialQuestion = params.get("q");
  if (initialQuestion) {
    applyQuestionText(initialQuestion, { focus: false });
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
  showStatus("");
  updateUrl("");
  applyQuestionText("", { focus: true });
  setIdleState();
  trackEvent("ask_stats_cleared", {
    previous_question_length_bucket: bucketCount(previousQuestion.length, [0, 20, 40, 80, 120, 180])
  });
});

if (elements.queryTemplateStrip) {
  elements.queryTemplateStrip.addEventListener("click", (event) => {
    const button = event.target.closest("[data-template], [data-template-id]");
    if (!button) {
      return;
    }

    // Handle new example templates with data-template-id
    const templateId = button.getAttribute("data-template-id");
    if (templateId && QUERY_TEMPLATES[templateId]) {
      const template = QUERY_TEMPLATES[templateId];
      applyQuestionText(template.query);
      trackEvent("ask_stats_template_selected", {
        template: template.label,
        template_id: templateId
      });
      return;
    }

    // Handle old-style placeholder templates with data-template
    const template = button.getAttribute("data-template") || "";
    applyQuestionText(template);
    trackEvent("ask_stats_template_selected", {
      template: button.querySelector(".query-template-button__label")?.textContent || "template"
    });
  });
}

elements.exampleStrip.addEventListener("click", async (event) => {
  const button = event.target.closest("[data-example]");
  if (!button) {
    return;
  }

  const example = button.getAttribute("data-example") || "";
  applyQuestionText(example, { focus: false });
  await runQuestion(example, "example");
});

void init();
