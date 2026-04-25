# Ask the Stats Query Expansion: Comprehensive Redesign

**Date:** 2026-04-25  
**Status:** Design approved, ready for implementation planning  
**Scope:** Full query system redesign supporting comparisons, complex combinations, multi-season trends, and all-time records with a hybrid dual-track architecture (freeform + fallback builder).

---

## Executive Summary

Currently, Ask the Stats supports 4 query templates through a purely freeform interface:
- Count threshold
- Single peak
- Player/team list
- Team low mark

This redesign expands the system to support 4 new query shapes (comparison, combination, trend, record) while improving the natural language parser to handle more complex questions. The architecture uses a **hybrid dual-track approach**:

1. **Simple queries** (existing 4 shapes) stay purely freeform — parsed directly to results
2. **Complex queries** (new 4 shapes) support both freeform and an optional multi-step builder fallback

When a complex query can't be fully parsed, users see a helpful error with a rephrasing suggestion plus a "Use builder" escape hatch. This lets power users benefit from smarter parsing while novices can always fall back to a guided form.

---

## Design Principles

1. **Progressive Disclosure** — Users trying simple queries never see the builder. Users attempting complex queries get a clear error + escape hatch if freeform fails.
2. **Confidence-Based Routing** — Parser attempts to extract query intent with explicit confidence scoring; only executes if confidence is high.
3. **Dual-Path Parity** — A query built step-by-step in the builder produces identical results to the same query via freeform parsing.
4. **Privacy & Simplicity** — Parser remains stateless and immutable; no training or feedback loops. New queries are added via explicit intent detection, not ML.

---

## Architecture & Components

### System Overview

**Frontend (JavaScript/HTML)**
- Enhanced query form in `assets/query.js`
- New `attempt_complex_parse()` function that extends the existing simple parser
- Multi-step builder UI component (modal/slide-out)
- Error display with suggestion and builder call-to-action

**Backend (R/Plumber)**
- Enhanced `/api/query` endpoint with structured error responses
- Four new query builders in `api/R/helpers.R`:
  - `build_comparison_query()` — side-by-side aggregates for 2 teams/players
  - `build_combination_query()` — AND/OR filtered result sets with multiple conditions
  - `build_trend_query()` — same subject across multiple seasons with year-over-year deltas
  - `build_record_query()` — all-time stat rankings with context and top-10 surrounding records
- Enhanced `parse_query_intent()` to return structured hints for builder prefill on failure

### Data Flow

```
User types freeform query
         ↓
attempt_complex_parse() tries 4 existing shapes first
         ↓
         ├─ Match found? Return confidence score
         │
         └─ No match? Try complex patterns:
            ├─ Comparison markers ("vs", "compared to")
            ├─ Logical operators ("and", "or")
            ├─ Season arrays ("2023-2025", "across 2023, 2024, 2025")
            ├─ Record indicators ("all-time", "ranking")
            └─ Extract subjects, stat, filters
                    ↓
         Confidence ≥ 0.85? → Execute query builder → Return results
                    ↓
         Confidence 0.65–0.84? → Return parse_help_needed error + prefill hints
                    ↓
         User sees error + suggestion + "Use builder" button
                    ↓
         User clicks builder button → Modal opens with hints pre-filled
                    ↓
         User completes builder steps → Sends structured payload
                    ↓
         Backend executes (no re-parsing) → Return results
```

---

## Parser & Query Intent Detection

### Current Intent Types (Keep Existing)
- `count` — Threshold-based counting (e.g., "How many times has Grace scored 50+?")
- `highest` — Single peak query (e.g., "What's Liz's highest goal assists?")
- `lowest` — Min value query (e.g., "Which teams had the lowest turnovers?")
- `list` — List-based filtering (e.g., "Which players had 5+ gains in 2025?")

### New Intent Types
- `comparison` — "Vixens vs Swifts goal assists in 2025" → side-by-side comparison
- `combination` — "Players with 40+ goals AND 5+ gains in 2024" → multi-filter AND/OR logic
- `trend` — "Grace Nweke goal assists across 2023, 2024, 2025" → multi-season trend
- `record` — "Highest single-game intercepts, all time" → all-time record with ranking

### Parser Strategy: `attempt_complex_parse()`

**Step 1: Fast Path (Existing Patterns)**
- Try to match against the 4 existing templates first
- If match found, return immediately with high confidence

**Step 2: Complex Pattern Matching**
If no simple match, scan for:

| Marker | Intent | Example |
|--------|--------|---------|
| "vs", "versus", "compared to", "vs." | Comparison | "Vixens vs Swifts goal assists" |
| "and", "or" with multiple conditions | Combination | "40+ goals AND 5+ gains" |
| "across", season range like "2023-2025", comma-separated years | Trend | "across 2023, 2024, 2025" |
| "all-time", "ever", "ranking", "record", "highest/lowest all time" | Record | "all-time highest intercepts" |

**Step 3: Extraction**
For each detected pattern, extract:
- **Subjects**: Player or team names (1+ for comparison/combination, 1 only for trend/record)
- **Stat**: The performance metric being queried
- **Filters**: Opponent, location (home/away), min/max games (optional)
- **Seasons**: Array of seasons or all-time flag (optional; defaults to current)
- **Operator**: "AND" or "OR" for combinations (optional; defaults to "AND")

**Step 4: Confidence Scoring**
Calculate confidence as a weighted sum:
- Subject(s) parsed: +0.40
- Stat identified: +0.35
- At least one filter or season: +0.15
- No ambiguities detected: +0.10

Confidence ranges:
- **≥ 0.85** — Execute query immediately (high confidence)
- **0.65–0.84** — Return error with suggestion + builder hints (medium confidence)
- **< 0.65** — Return error with builder only (low confidence; don't guess)

---

## The Four New Query Shapes

### 1. Comparison Queries

**User Says:** "Vixens vs Swifts goal assists in 2025"

**Parser Extracts:**
- Intent: `comparison`
- Subjects: [Vixens, Swifts]
- Stat: `goalAssists`
- Season: 2025

**Backend Execution (`build_comparison_query()`):**
1. Fetch aggregate stat for subject 1 in season
2. Fetch aggregate stat for subject 2 in season
3. Compute round-by-round breakdown for both
4. Calculate difference and determine leader

**Response:**
```json
{
  "status": "supported",
  "intent_type": "comparison",
  "subjects": ["Vixens", "Swifts"],
  "stat": "goalAssists",
  "stat_label": "Goal Assists",
  "season": 2025,
  "results": [
    {
      "subject": "Vixens",
      "total": 487,
      "average_per_game": 23.2,
      "rounds": [
        { "round": 1, "opponent": "Swifts", "value": 21 },
        { "round": 2, "opponent": "Firebirds", "value": 25 }
      ]
    },
    {
      "subject": "Swifts",
      "total": 412,
      "average_per_game": 19.6,
      "rounds": [...]
    }
  ],
  "comparison": {
    "leader": "Vixens",
    "difference": 75,
    "percentage_ahead": 18.2
  }
}
```

---

### 2. Complex Combination Queries

**User Says:** "Which players had 40+ goals AND 5+ gains in 2024?"

**Parser Extracts:**
- Intent: `combination`
- Filters: [goals ≥ 40, gains ≥ 5]
- Operator: AND
- Season: 2024

**Backend Execution (`build_combination_query()`):**
1. Query player_match_stats for matches where (goal1 + 2×goal2) ≥ 40 AND gains ≥ 5
2. Group by player and season
3. Rank by combined score (goals + gains)
4. Return all matching records

**Response:**
```json
{
  "status": "supported",
  "intent_type": "combination",
  "filters": [
    { "stat": "goals", "operator": ">=", "threshold": 40 },
    { "stat": "gains", "operator": ">=", "threshold": 5 }
  ],
  "logical_operator": "AND",
  "season": 2024,
  "total_matches": 5,
  "results": [
    {
      "player": "Grace Nweke",
      "team": "Vixens",
      "goals": 45,
      "gains": 8,
      "date": "2024-05-15",
      "opponent": "Fever"
    },
    {
      "player": "Liz Watson",
      "team": "Fever",
      "goals": 42,
      "gains": 6,
      "date": "2024-06-08",
      "opponent": "Vixens"
    }
  ]
}
```

---

### 3. Multi-Season Trend Queries

**User Says:** "Grace Nweke goal assists across 2023, 2024, 2025"

**Parser Extracts:**
- Intent: `trend`
- Subject: Grace Nweke
- Stat: `goalAssists`
- Seasons: [2023, 2024, 2025]

**Backend Execution (`build_trend_query()`):**
1. For each season, sum goal assists across all matches
2. Calculate games played per season
3. Compute year-over-year change percentage
4. Return chronological series

**Response:**
```json
{
  "status": "supported",
  "intent_type": "trend",
  "subject": "Grace Nweke",
  "subject_type": "player",
  "stat": "goalAssists",
  "stat_label": "Goal Assists",
  "seasons": [2023, 2024, 2025],
  "results": [
    {
      "season": 2023,
      "total": 156,
      "games": 20,
      "average": 7.8
    },
    {
      "season": 2024,
      "total": 189,
      "games": 22,
      "average": 8.6,
      "yoy_change": 21.2,
      "yoy_change_label": "+33 assists"
    },
    {
      "season": 2025,
      "total": 201,
      "games": 23,
      "average": 8.7,
      "yoy_change": 6.3,
      "yoy_change_label": "+12 assists"
    }
  ]
}
```

---

### 4. All-Time Record Queries

**User Says:** "Highest single-game intercepts all time with ranking"

**Parser Extracts:**
- Intent: `record`
- Stat: `intercepts`
- Scope: all-time

**Backend Execution (`build_record_query()`):**
1. Query max(stat) across all seasons and matches
2. Find all-time rank for that performance
3. Fetch top 10 matches of that stat for context
4. Return record + surrounding context

**Response:**
```json
{
  "status": "supported",
  "intent_type": "record",
  "stat": "intercepts",
  "stat_label": "Intercepts",
  "scope": "all_time",
  "record": {
    "player": "Sharni Layton",
    "team": "Vixens",
    "value": 12,
    "date": "2016-05-01",
    "opponent": "Swifts",
    "round": 8,
    "season": 2016,
    "all_time_rank": 1
  },
  "context": [
    {
      "rank": 1,
      "player": "Sharni Layton",
      "value": 12,
      "date": "2016-05-01",
      "season": 2016
    },
    {
      "rank": 2,
      "player": "Liz Watson",
      "value": 11,
      "date": "2018-07-14",
      "season": 2018
    }
  ]
}
```

---

## Multi-Step Builder UI

**When It Appears:**
- Only when freeform parse returns confidence < 0.85
- Shown alongside error banner
- Opened via "Use the builder" button
- Pre-populated with any hints the parser did extract

### Step 1: Pick Query Shape
- **Input:** Radio button group
- **Options:** 
  - Comparison
  - Combination
  - Trend
  - Record
  - (Plus existing 4: Count, Highest, Lowest, List)
- **Help Text:** One-sentence description of each
- **Validation:** Required; one must be selected
- **Prefill:** Parser's suspected shape if detected

### Step 2: Pick Subject(s)
- **Input:** Searchable dropdown (player/team names) + "Add subject" button for multi-subject queries
- **Validation:** At least 1 required; max 2 for comparisons/combinations
- **Prefill:** Any subjects the parser extracted

### Step 3: Pick Stat
- **Input:** Searchable dropdown grouped by category (Scoring, Ball Handling, Defense, etc.)
- **Hover:** Show stat label + brief definition
- **Validation:** Required; one stat only
- **Prefill:** Any stat the parser matched

### Step 4: Add Filters (Optional)
- **Input:** Checkboxes for Opponent / Location (Home/Away) / Min/Max Games
- **For Combinations:** Toggle for AND/OR operator + "Add filter" button
- **Validation:** Optional; applies only to relevant shapes
- **Prefill:** Any filters parsed

### Step 5: Pick Timeframe
- **Input:** Radio group: Single Season / Multi-Season / All-Time
- **If Multi-Season:** Checklist of years to select (e.g., 2023, 2024, 2025)
- **If Single:** Dropdown of all available seasons
- **Validation:** Required; at least one season
- **Prefill:** Current season or parsed seasons

**Submit Button:**
- Label: "Run Query"
- Enabled only when: subject(s) + stat + timeframe all filled
- On click: Convert builder state to structured intent → send to `/api/query` with `builder_source: true` flag

---

## Error Handling & Fallback Behavior

### Parse Failure Response

When freeform query doesn't parse with confidence ≥ 0.85:

```json
{
  "status": "parse_help_needed",
  "question": "user's original question",
  "error_message": "I couldn't match all the parts of that question.",
  "suggestion": "Try: 'Which players had 40+ goals in 2024?' or 'Vixens vs Swifts goal assists 2025'",
  "parsed_hints": {
    "subjects": ["Grace Nweke"],
    "stat": "goals",
    "seasons": null,
    "comparison": false,
    "confidence": 0.72
  },
  "builder_prefill": {
    "shape": "list",
    "subjects": ["Grace Nweke"],
    "stat": "goal1"
  }
}
```

### Frontend Error Display

1. Show error message in a red banner
2. Display suggestion as a clickable link (clicking re-populates form and reruns query)
3. Show "Use the builder" button next to suggestion
4. When builder button clicked: modal opens with `builder_prefill` pre-selected

### Builder Submission Flow

1. User fills all required builder steps
2. Clicks "Run Query"
3. Frontend converts builder state to structured payload:
   ```json
   {
     "question": "[auto-generated from builder selections]",
     "builder_source": true,
     "intent": {
       "intent_type": "[shape]",
       "subjects": [...],
       "stat": "[stat_key]",
       "filters": [...],
       "seasons": [...]
     }
   }
   ```
4. Sends to `/api/query`
5. Backend recognizes `builder_source: true` and skips parsing (executes directly)
6. Returns results as normal

### Graceful Degradation

- **Database timeout:** Both freeform and builder show: "The query took too long. Try narrowing to a specific season or player."
- **Stat not indexed:** Backend returns error with 3-5 alternative stat suggestions
- **Requested season has no data:** Show "No data for [season]." with suggestions for available seasons
- **Subject not found:** Return error with spelling suggestions (e.g., "Did you mean Vixens? (1986 founded)")

---

## Implementation Notes

### Database Considerations
- Ensure `idx_pms_stat_value` is present for efficient stat ranking queries
- May need additional indices for multi-subject comparisons (e.g., `idx_team_season_stat`)
- All-time record queries should use `compute_archive_rank()` helper (wrapped in tryCatch)

### API Changes
- Extend `/api/query` to handle `builder_source` flag
- Return structured `parse_help_needed` error responses (new HTTP 422 or 200 with error status)
- Maintain backward compatibility: existing simple queries continue to work as-is

### Frontend Changes
- Extend `assets/query.js` with `attempt_complex_parse()` function
- Add new modal/slide-out builder component
- Update error display to show suggestions and builder trigger
- Enhance template strip to show 8–10 examples (expanded from 4)

### Testing
- Unit tests for `attempt_complex_parse()` with 20+ test cases (simple, complex, ambiguous, edge cases)
- Integration tests: verify each new query shape returns correctly structured responses
- Regression tests: ensure existing 4 query types still work without changes
- API tests: verify builder vs freeform produce identical results for same query

---

## Success Criteria

1. ✅ Parser successfully extracts 80%+ of clearly-stated complex queries (comparison, combination, trend, record)
2. ✅ Users attempting complex queries see helpful error + builder option when parser confidence is low
3. ✅ Builder-composed queries produce identical results to freeform equivalents
4. ✅ All-time record queries execute in < 2s (with index optimization)
5. ✅ Existing simple queries remain unchanged and work as before
6. ✅ Privacy constraints maintained: no raw question text logged; builder state sanitized
7. ✅ New query shapes produce results in < 3s under normal load

---

## Scope: In vs Out

### In Scope
- Comparisons (2 subjects)
- AND/OR combinations with multiple filters
- Multi-season trends
- All-time records with ranking
- Builder UI for query composition
- Enhanced parser with confidence scoring

### Out of Scope
- Machine learning / training / feedback loops
- Support for 3+ subject comparisons (focus on 2-way for MVP)
- Custom aggregation functions (use existing stat set)
- Natural language date parsing beyond "2023-2025" format
- Saved queries or query templates
- Real-time notifications on record breaks
