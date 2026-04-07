# Analytical Stats Design

## Summary

Add a new analytical layer to the archive and player dossier experience so users can move beyond raw totals and averages into explainable impact and efficiency metrics for both players and teams.

The first release should emphasize **interpretable derived stats**, not a black-box rating system. Users should be able to understand what a metric means, what inputs it uses, and why it belongs on the site.

## Problem

The archive is strong as a historical reference, but the stat model is still heavily box-score driven:

- it answers **what happened**
- it is weaker at explaining **how efficiently it happened**
- it does not yet provide a shared analytical language for player and team styles
- player dossiers are more editorial now, but they still lack a dedicated analytical layer

This leaves a gap between trusted historical data and the kinds of deeper interpretive stats that fans, writers, and analysts often want.

## Goals

1. Add analytical stats for both players and teams.
2. Keep the first release explainable and auditable.
3. Reuse existing archive and dossier surfaces rather than launching a separate analytics product.
4. Support both direct derived metrics and light model-based metrics.
5. Preserve trust by making caveats and formula behavior explicit.

## Non-goals

- Do not replace raw archive stats with analytical stats.
- Do not launch a separate analytics-only page in the first release.
- Do not introduce opaque “overall rating” metrics with unclear weights.
- Do not force metrics across eras where the underlying data is too inconsistent.

## Chosen Direction

The chosen direction is an **impact and efficiency layer** embedded into the existing archive and player dossier surfaces.

This layer should:

- sit alongside the current player/team stat selectors
- work for both player and team views
- prefer direct formulas first
- allow more opinionated composites only when they remain well documented

## Rejected Alternatives

### 1. Role/archetype-first model

This would classify players and teams into labels such as finisher, feeder, disruptor, or transition driver.

Why not first:

- more subjective
- harder to benchmark cleanly across seasons
- better as a second-phase storytelling layer after the core analytical metrics exist

### 2. Value/leverage-first model

This would prioritize clutch impact, matchup swing, or win-value contribution metrics.

Why not first:

- highest complexity
- highest explanation burden
- easiest to challenge if the model assumptions are not obvious

These ideas remain viable follow-on phases after the core impact-and-efficiency layer is established.

## Metric Families

The first release should organize analytical stats into four families.

### 1. Efficiency

Purpose: describe how effectively a player or team turned involvement into results.

Candidate metrics:

- **Scoring efficiency**: points per scoring attempt
- **Shot value efficiency**: weighted scoring output that handles super-shot eras correctly
- **Team finishing efficiency**: team points per scoring attempt or scoring sequence proxy

Notes:

- formulas must account for pre-super-shot and super-shot eras cleanly
- metrics should degrade gracefully when a formula is not meaningful for an older season

### 2. Involvement

Purpose: describe how central a player or team was to attacking flow.

Candidate metrics:

- **Attack involvement rate**: share of feeds, goal assists, centre-pass receives, or shot attempts
- **Possession usage proxy**: a weighted estimate of how often a player sat at the center of an attacking chain
- **Team concentration score**: how concentrated or spread a team’s attacking production was

Notes:

- these metrics are especially valuable on player dossiers because they give shape to role and style

### 3. Ball Security and Pressure

Purpose: describe how well a player or team protected possession or disrupted opponents.

Candidate metrics:

- **Turnover cost rate**: turnovers relative to attacking involvement or touches proxy
- **Disruption rate**: gains, intercepts, deflections, rebounds, or related defensive actions per match or per opportunity proxy
- **Pressure balance**: defensive events created minus possession giveaways

Notes:

- some metrics may need player and team variants rather than pretending one formula fits both

### 4. Two-way Impact

Purpose: create a more interpretive headline stat that combines attacking and defensive contribution.

Candidate metrics:

- **Net impact score**
- **Two-way contribution index**

Notes:

- this family is intentionally more opinionated
- it should not be the first analytical stat shipped
- the formula and weights must be documented explicitly

## Product Surfaces

### Archive

Analytical stats should be added into the existing player and team stat-picking flow rather than a separate landing page.

Design rules:

- expose them as an **Analytics** stat group or equivalent grouping pattern
- keep leaderboard behavior consistent with current stats
- allow them to work with the existing archive totals / average views where appropriate
- include concise explainer copy so users can understand the metric without leaving the page

### Player dossier

Player pages should gain an **analytical profile** layer that complements the dossier pillars and notes.

This should include:

- a small set of strongest analytical indicators for the player
- one or two short interpretive notes derived from those metrics
- clear terminology that explains the player’s style, not just their totals

### Team surfaces

Teams should use the same analytical layer so archive users can compare style as well as output.

This should support questions such as:

- which teams were most efficient
- which teams protected the ball best
- which teams created the most defensive disruption

### Deferred surfaces

Do not include these in the first implementation plan:

- Ask the Stats support for analytical metrics
- Round recap integration
- separate analytics landing page

Those can follow once the formulas and archive behavior are proven.

## Architecture

The analytical layer should be implemented as a **derived-metrics system** on top of the current database and API, not as a new raw-data ingestion path.

### Source of truth

- existing Champion Data-derived tables remain the source of truth
- analytical metrics are computed from existing validated inputs
- if a metric needs a new aggregation helper, it should live in one shared calculation path, not be duplicated per endpoint

### Metric categories

Analytical metrics should be split into two internal categories:

1. **Direct derived metrics**
   - pure formulas using existing stats
   - easiest to validate and explain

2. **Model-based metrics**
   - weighted or composite formulas
   - still acceptable, but must ship with documentation and constraints

### Interfaces

The system should make it easy to answer:

- what inputs a metric uses
- whether it is valid for all seasons or only some eras
- whether it applies to players, teams, or both
- whether it behaves as a total-style metric, average-style metric, or both

## Trust, Caveats, and Error Handling

Analytical stats are only useful if users trust them.

Rules:

- every metric must have a one-sentence explanation
- model-based metrics must document their weights and assumptions
- if a metric is not valid for a season or era, show it as unavailable instead of filling with a misleading value
- avoid implying exact possession models if the site is using a proxy
- never hide uncertainty when historical data quality differs by season

## Candidate First-Release Metrics

The first implementation plan should define a concrete subset of roughly **6 to 10** analytical metrics, such as:

### Player candidates

- scoring efficiency
- attack involvement rate
- turnover cost rate
- defensive disruption rate
- pressure balance

### Team candidates

- team finishing efficiency
- team ball security rate
- team disruption rate
- attack concentration score
- possession control balance

This set is enough to create a meaningful first release without exploding scope.

## Rollout Plan

### Phase 1

- define the first-release analytical metrics
- document formulas and caveats
- ensure historical validity rules are explicit

### Phase 2

- wire analytical stats into archive stat selectors and leaderboard views
- ensure player and team surfaces both support them

### Phase 3

- add dossier-specific analytical notes on player pages
- highlight strongest analytical traits rather than dumping all metrics equally

### Phase 4

- consider the first composite/two-way impact metric
- only ship once the simpler metrics have established trust

## Validation and Testing

Validation should cover:

- formula correctness for direct derived metrics
- era-specific behavior for scoring models
- unavailable-state behavior when inputs are insufficient
- archive rendering for both player and team surfaces
- dossier rendering for player analytical notes

The first implementation plan should prefer repository-native checks and targeted regression validation over introducing new frameworks unless a clear gap exists.

## Success Criteria

This design is successful if:

- archive users can browse analytical stats as naturally as current stats
- player dossiers explain style and impact, not just totals
- the first analytical metrics are explainable in plain language
- formulas remain maintainable and reusable across surfaces
- the site gains a more distinctive analytical voice without sacrificing trust
