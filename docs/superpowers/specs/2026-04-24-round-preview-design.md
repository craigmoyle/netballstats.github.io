# Round Preview Design

## Problem

The archive already has a strong **round recap** surface for completed matches, but it has no equivalent editorial surface for the **next upcoming round**. Users can see fixtures elsewhere, but they cannot quickly understand why an upcoming matchup matters through the lens of archive history, recent form, or standout player context.

This feature adds a dedicated `/round-preview` page that previews the **next upcoming round only** with a fixture-first editorial structure and API-curated facts.

## Goals

- Create a dedicated `/round-preview` page for the next upcoming round.
- Present each fixture as an editorial preview card rather than a generic schedule row.
- Surface trustworthy context: head-to-head, last meeting, recent form, streaks, and a small set of player-watch notes.
- Keep the frontend simple by returning a ready-to-render preview payload from the API.
- Preserve the archive's editorial tone, accessibility bar, and bounded-query posture.

## Non-goals

- Multi-round future schedules on the initial page load.
- Longform article tooling or manually authored preview copy.
- Heavy charting in v1.
- Expanding the existing `/round` recap page to handle both completed and upcoming rounds.

## UX Summary

`/round-preview` is a new dedicated page. It defaults to the **next upcoming round only**.

The page structure is:

1. **Hero** with round label, season, short editorial line, and compact round snapshot.
2. **Summary band** with a small number of round-wide facts.
3. **Fixture stack** with one preview card per match.

The chosen layout is the **editorial match stack**:

- the page leads with round context
- the core narrative lives in the fixture cards
- the experience stays scan-friendly on mobile and desktop

Where reliable team-logo assets already exist, fixture cards should display **team logos alongside team names**. If a logo is unavailable, the layout falls back to text-only team labels without leaving empty placeholders or broken image treatment.

## Match Preview Card Design

Each fixture card should contain the same bounded structure:

- fixture header: home team, away team, logos if available, venue, and local start time
- head-to-head summary
- last meeting summary
- recent-form summary for both teams
- current streak note
- curated player-watch notes
- one or two short editorial fact callouts

This keeps the page consistent and avoids each fixture turning into a long article.

### Player-watch notes

Player-watch notes are capped and curated. The first version should aim for:

- one **recent-form** note where possible
- one **last-meeting** note where possible

This can produce up to two notes per team, but the payload should not force a fixed count if the data is weak. If only one strong note exists, return one. If none meet the threshold, omit the block rather than generating filler.

## API Design

The feature should use a dedicated API-first payload, separate from the existing round-recap response. A route such as `/round-preview-summary` is appropriate.

The frontend should make **one request** for the page and render from that payload.

### Payload shape

The response should have a bounded, editorially shaped structure similar to:

```json
{
  "season": 2026,
  "round_number": 9,
  "round_label": "Round 9",
  "round_intro": "Three fixtures, including a rivalry with 22 meetings in the archive.",
  "summary_cards": [
    { "label": "Matches", "value": "3" },
    { "label": "Closest rivalry", "value": "Firebirds lead 11-10" }
  ],
  "matches": [
    {
      "fixture": {
        "match_id": 123,
        "home_team": "Vixens",
        "away_team": "Swifts",
        "home_logo_url": "/assets/...",
        "away_logo_url": "/assets/...",
        "venue": "John Cain Arena",
        "local_start_time": "2026-05-02T19:00:00+10:00"
      },
      "head_to_head": {
        "meetings": 18,
        "home_wins": 10,
        "away_wins": 8,
        "summary": "Vixens lead the archive series 10-8."
      },
      "last_meeting": {
        "winner": "Swifts",
        "scoreline": "66-61",
        "season": 2025,
        "round_number": 12,
        "summary": "Swifts won the last meeting by 5 points in Round 12, 2025."
      },
      "recent_form": {
        "home": { "wins": 4, "losses": 1, "results": ["W", "W", "L", "W", "W"] },
        "away": { "wins": 2, "losses": 3, "results": ["L", "W", "L", "L", "W"] },
        "summary": "Vixens have won 4 of their last 5; Swifts 2 of 5."
      },
      "streaks": {
        "home": { "type": "win", "length": 3, "summary": "Vixens enter on a 3-match winning streak." },
        "away": { "type": "loss", "length": 2, "summary": "Swifts have dropped their last 2." }
      },
      "player_watch": [
        { "team": "Vixens", "context": "recent_form", "summary": "Kiera Austin has scored 28+ in three straight matches." },
        { "team": "Swifts", "context": "last_meeting", "summary": "Helen Housby scored 31 in the last meeting." }
      ],
      "fact_cards": [
        "This is the tightest rivalry in the round by archive record.",
        "The last four meetings have all been decided by single digits."
      ]
    }
  ]
}
```

The response should favor short, display-ready summary strings over making the browser assemble narrative copy from raw numbers.

## Data Rules

### Upcoming round detection

The page targets the **next upcoming round only**. The backend should identify the earliest round in the selected season whose fixtures are still upcoming, based on scheduled match times and completion state in the matches table.

If no upcoming round is available, the endpoint should return a clean empty payload or 404-style domain response that the frontend can map to a dedicated empty state.

### Head-to-head and last meeting

Head-to-head and last-meeting context should use the **full recorded archive wherever the teams have a logged meeting**.

This should not be restricted to the Super Netball era. The product is an archive first, so matchup history can span all recorded seasons available in the dataset.

### Recent form

Recent form should:

- prefer the **current season**
- fall back across earlier seasons only when fewer than 5 completed matches are available
- stop once 5 matches are collected

This rule applies to both summary strings and result-strip style data.

### Streaks

Streaks should describe the current run entering the fixture:

- win streak
- losing streak
- optionally unbeaten/winless phrasing if useful

The first version should keep streak logic simple and explicit. Avoid overfitting niche streak types that dilute readability.

### Sparse-history handling

If the historical record is thin, the payload should say so directly. Examples:

- "First recorded meeting in the archive."
- "Only two prior meetings are logged."

The API must not generate inflated claims when the sample is weak.

## Frontend Design Notes

- Reuse the editorial shell language already present in the site and the existing round page.
- Keep the page visually distinct from the completed-round recap, but clearly part of the same product family.
- Use shared UI helpers from `window.NetballStatsUI` for status and responsive table behavior where relevant.
- Prefer cards and short fact blocks over dense tables in the first version.
- Keep motion subtle and compatible with reduced-motion handling already owned by `theme.js`.

## Error Handling and Empty States

The page should behave explicitly:

- **No upcoming round:** show a clear empty state and link users to the latest completed round recap.
- **Partial preview data:** still render the match card and omit only the missing block.
- **Missing logos:** render the text version cleanly.
- **Fetch failure:** use the existing status-banner error treatment rather than leaving a blank page.

The backend should continue the repo's existing posture:

- explicit validation
- parameterized SQL
- hard result bounds
- no broad silent fallbacks

## Implementation Boundaries

The first implementation should stay focused:

- one new page shell at `/round-preview`
- one page script for fetching and rendering the preview
- one new API endpoint for the preview payload
- helper functions in `api/R/helpers.R` for upcoming-round selection, head-to-head summaries, recent-form snapshots, streaks, and player-watch selection

This is a single coherent feature and does not need decomposition into multiple specs.

## Validation

Because the feature changes both frontend and API behavior, the implementation phase should validate with the repo's existing commands:

- `npm run build`
- `node --check assets/*.js`
- `Rscript -e "parse(file='api/R/helpers.R'); parse(file='api/plumber.R')"`
- `Rscript scripts/test_api_regression.R` when the API endpoint is added

## Recommendation

Implement this as an **API-first editorial preview surface**. The API should assemble trustworthy, bounded matchup context; the frontend should focus on information hierarchy, tone, and scanability.
