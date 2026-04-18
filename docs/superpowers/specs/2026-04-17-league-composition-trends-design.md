# League Composition Trends Design

## Summary

Introduce a new public analysis feature focused on how league composition changes over time, with two linked surfaces built on one shared maintained player reference layer:

1. a **dedicated public analysis page** for season-by-season trends in youth break-ins, league age/experience, and import share
2. **enriched player profiles** that add birthday, nationality/import context, and debut framing to the existing dossier

The approved direction is a **hybrid** product shape:

- a strong editorial opening with plain-language findings
- an interactive analysis desk underneath
- lightweight, dossier-style profile enrichment rather than a second analytics dashboard inside player pages

This feature depends on a maintained, site-owned player reference dataset for birthday, nationality, and import classification. Debut and experience should be derived from the archive itself.

## Problem

The archive can already tell rich stories about performance over time, but it cannot yet answer league-composition questions such as:

1. are fewer younger players breaking into the league now than before?
2. is the league older or more experienced than in earlier eras?
3. has the share of imports increased over time?

The current product has two gaps:

- there is **no dedicated public surface** for league-composition analysis
- player profiles do **not yet carry core identity context** such as birthday, nationality/import status, or debut framing

Without a maintained reference layer and a dedicated surface, these questions either stay unanswered or get forced into the wrong parts of the product.

## Goals

1. Ship a **new public analysis page** for league-composition trends over time.
2. Add **birthday, nationality/import context, and debut framing** to player profiles.
3. Keep the feature editorial, evidence-led, and easy to scan.
4. Use **maintained reference data** for birthday and nationality/import status rather than fragile runtime scraping.
5. Keep definitions, coverage notes, and classifications explicit so the feature remains trustworthy.

## Non-goals

- no generic BI-style analyst console
- no team-by-team deep-dive as the primary v1 surface
- no position-group-first experience in the first release
- no heavy comparison builder for this feature area
- no inference of import status from name, club, or other weak proxies

## Product framing

### Primary model

The first release should feel like a **league-composition editorial desk**:

- the new page is the main destination
- player profiles gain supporting identity context
- the maintained reference layer is shared across both surfaces

### Editorial stance

The feature should feel like:

- a sports almanac for league composition
- a data-journalism feature with explicit methods
- a trustworthy archive analysis surface

It should not feel like:

- a speculative scouting tool
- a generic dashboard
- a demographic widget farm

## Information architecture

### New public page

Create a new standalone public page dedicated to league-composition trends.

Recommended structure:

1. **Editorial lead**
   - 2-3 plain-language findings based on the active season window
   - a short framing paragraph that explains what changed and why it matters
2. **Three core trend modules**
   - youth break-ins over time
   - league age / experience profile over time
   - import share over time
3. **Analysis desk**
   - season-range controls
   - trend-lens toggles
   - supporting composition and distribution views
4. **Method and definitions**
   - exact definitions for debut, age, experience, and import classification
   - coverage notes and caveats

### Player profiles

Add a compact identity/context block to player dossiers showing:

- birthday
- nationality
- import status
- debut season
- experience framing based on seasons since debut

This should stay lightweight and editorial. The profile should not become a second full analysis desk.

## Day-one scope

### Included

- whole-league season-by-season trends
- a shared maintained player reference layer feeding the analysis page and player profiles
- editorial opening plus interactive analysis desk on the new page
- dossier-style profile enrichment

### Explicitly out of scope

- team-by-team deep dives as the main page model
- position-group-first exploration
- player-by-player breakout explorer as a primary surface
- free-form comparison tooling

## Data model and backend shape

### Maintained reference layer

Add a site-owned player reference source keyed by `player_id`, stored in the repo at a stable path such as `config/player_reference.csv`.

Required v1 fields:

- `date_of_birth`
- `nationality`
- `import_status`

Recommended provenance fields:

- `source_label`
- `source_url`
- `verified_at`
- optional `notes`

Optional support fields may be added if needed, but debut season should be derived from archive data rather than manually entered where possible.

### Derived analytical layer

Materialize season-level analytical rows during `build_database.R` rather than calculating them ad hoc at request time.

Recommended derived outputs:

1. **player identity context**
   - the normalized profile-facing reference fields
2. **player season demographics**
   - age in season
   - experience in season
   - debut-season flag
   - import flag
3. **league season summaries**
   - aggregated season-level trend rows for the public analysis page

This keeps the read-only API explicit, bounded, and fast.

## Sourcing and provenance

### Derived automatically

- **Debut season** from the first season in archive match data
- **Experience in season** from debut season
- **Age in season** from `date_of_birth` plus the season anchor date

### Maintained explicitly

- **Date of birth**
- **Nationality**
- **Import status**

These should live in a checked-in, site-owned reference file. The build reads the file, validates it, and writes the normalized values into PostgreSQL.

### Recommended sourcing policy

1. Prefer an **official player or competition source** when available.
2. Allow a **secondary public reference** when no official source exists.
3. Treat **import status** as a site-owned classification field, not something implied automatically from nationality.
4. Do **not** scrape third-party pages at runtime or during normal request handling.

This keeps the system deterministic, auditable, and maintainable.

## Analytical definitions

### Core terms

- **Debut season:** the first season in archive match data for that player
- **Experience in season:** `season - debut_season + 1`, so a player is in **season 1** during their debut year
- **Age in season:** player age at the start of that season’s competition window, anchored to the first match date in the season
- **Import share:** share of players who appeared in at least one match that season and are flagged as imports in the maintained reference layer

### Youth breakout framing

Model “younger players breaking in” with two linked measures:

1. **average debut age by season**
2. **debut-age band composition by season**

Approved debut-age bands for v1:

- **19 and under**
- **20 to 22**
- **23 to 25**
- **26 and over**

This is clearer and more defensible than one arbitrary “young player” cutoff.

## Page behavior

### Editorial lead

The page lead should summarize the strongest shifts in the selected season frame, such as:

- whether debut age is rising
- whether league experience is increasing
- whether import share has moved materially

### Trend modules

The main modules should answer:

1. how debut age and debut-age composition changed
2. how league age and experience changed
3. how import share changed

### Analysis desk

Keep v1 focused and bounded:

- season-range controls
- trend-lens toggles
- supporting season summary and composition views

No free-form control sprawl unless later releases prove the need.

### Player profile behavior

Profiles should render the new identity/context block in the existing dossier flow, using the same maintained classification logic as the analysis page.

## API shape

### Player profile extension

Extend `player-profile` so the payload includes a lightweight player identity/reference block for frontend rendering.

### New analytical endpoints

Add one or two purpose-built endpoints for the new page, likely:

1. a whole-league season trend summary endpoint
2. an optional supporting composition/distribution endpoint for the active season range

Keep them explicit, read-only, and bounded. Avoid introducing a generic analytics query surface.

## Frontend shape

### New page module

Create a page-specific frontend module for the new analysis page rather than overloading an existing page script.

### Player profile integration

Extend the existing player page flow to render the new identity/context block, preserving the current dossier reading order.

### Method copy

Keep method and definition copy frontend-owned so it stays editorial, stable, and intentionally phrased.

## Coverage, error handling, and trust signals

### Coverage handling

- surface coverage notes whenever age/import metrics exclude players without maintained reference data
- include coverage metadata in analytical responses
- if coverage for an age- or import-derived metric drops below **85%** of players with at least one appearance in the selected season frame, show a caution state rather than presenting the figure as fully authoritative

### Profile handling

- if birthday or nationality/import data is missing, render a neutral “not yet verified” state
- if debut season is derivable, still show it even when other reference fields are unavailable

### Build-time safeguards

- validate the reference-file schema during `build_database.R`
- fail loudly on malformed values
- summarize missing-reference players so editorial cleanup work is visible

### API safeguards

- keep responses bounded and explicit
- never silently backfill age/import metrics with guesses

## Testing and validation

Validate the feature across four layers:

1. **reference-data validation**
   - schema and field checks for maintained records
2. **build assertions**
   - derived debut, age, experience, and season summary logic
3. **API regression coverage**
   - analytical endpoint responses and the extended player-profile payload
4. **frontend checks**
   - full, partial, and missing-reference states on the new page and on player profiles

## Implementation notes

### Recommended boundaries

1. keep maintained player reference data isolated from gameplay/stat tables
2. materialize season-level analytical rows during the database build
3. expose only purpose-built read-only endpoints for the new page
4. keep player profile enrichment lightweight and dossier-style

### Release logic

Treat the shared reference-data layer as the foundation. The analysis page and enriched profiles are two product surfaces backed by the same normalized source of truth.
