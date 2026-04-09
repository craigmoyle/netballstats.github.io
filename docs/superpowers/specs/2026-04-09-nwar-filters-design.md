# nWAR Filters Design

## Summary

Add two new filters to the nWAR leaderboard so users can slice the archive by **competition era** and **position group** without leaving the existing page flow.

The chosen approach is to extend the current filter bar with two additional selects:

- **Era**: All eras / ANZC / SSN
- **Position**: All positions / Shooter / Midcourt / Defender

This keeps the page simple, discoverable, and consistent with the existing nWAR controls.

## Problem

The current nWAR page can be filtered by season and minimum games, but it cannot answer two common archive questions cleanly:

1. How do the rankings change between the **ANZC era** and the **SSN era**?
2. Who leads within a specific **role family** such as shooters, midcourters, or defenders?

Without dedicated filters, users have to infer those splits manually or leave the page for other archive views.

## Goals

1. Let users switch between **ANZC**, **SSN**, and all-era views from the nWAR page.
2. Let users filter the leaderboard to **Shooter**, **Midcourt**, or **Defender**.
3. Keep the page editorial and lightweight rather than turning it into a dense control panel.
4. Preserve the current nWAR ranking rules:
   - all-seasons view ranks by `nwar_per_season`
   - single-season view ranks by `nwar`
5. Keep the API validation and empty-state behavior explicit and predictable.

## Non-goals

- No new nWAR page or alternate comparison view
- No expansion from three position groups into raw position codes
- No rewrite of the current dominant-position methodology
- No change to the existing season and minimum-games filters beyond integrating the new controls

## Filter definitions

### Era

- **All eras**: no era restriction
- **ANZC**: seasons `2008` through `2016`
- **SSN**: seasons `2017` onward

Era is a convenience bucket over season ranges, not a separate competition label sourced from another field.

### Position

The position filter reuses the existing dominant-position grouping already used by the nWAR page:

- **Shooter**: `GS`, `GA`
- **Midcourt**: `WA`, `C`, `WD`
- **Defender**: `GD`, `GK`

The selected group is determined from each player's dominant position **within the filtered result scope**, not from a career-wide label cached elsewhere.

## UX design

The existing filter bar gains two additional selects:

1. Season
2. Min games
3. Era
4. Position

Requirements:

- The new controls should match the existing form styling and interaction pattern.
- They should remain always visible rather than hidden behind a secondary panel.
- They should fit the current editorial shell on desktop and stack cleanly on smaller screens.
- Active leaderboard framing should stay obvious through nearby copy and table context.

## Copy and framing

When filters are active, the page should reflect that context in the existing hero/meta copy so users can tell what they are looking at without re-reading the control row.

Examples of the intended behavior:

- All eras + all positions: current default framing
- ANZC + all positions: copy should make clear the leaderboard is limited to the ANZC era
- SSN + Defender: copy should make clear the ranking is for SSN defenders
- Specific season + Shooter: copy should emphasize the season first, with the position filter as a secondary qualifier

This should stay concise and editorial rather than reading like raw parameter dumps.

## API design

Extend `/api/nwar` with two optional query parameters:

- `era=anzc|ssn`
- `position_group=shooter|midcourt|defender`

Behavior:

1. Apply the era filter as a season-range restriction before leaderboard aggregation when no specific season is selected.
2. Resolve dominant positions against the already filtered scope.
3. Apply the position-group filter after dominant position resolution.
4. Preserve the current ranking behavior:
   - no specific season selected -> order by `nwar_per_season`
   - specific season selected -> order by `nwar`

The current response shape can remain unchanged unless a lightweight convenience field is helpful during implementation. No new endpoint is needed.

## Interaction between season and era

Both `season` and `era` may be present in a request.

Design rule:

- **Season is the narrower filter and overrides era when both are supplied.**

That means:

- `season=2024&era=ssn` is valid and behaves like the 2024 season view
- `season=2012&era=anzc` is valid and behaves like the 2012 season view
- `season=2012&era=ssn` is also valid and still behaves like the 2012 season view because the explicit season takes precedence

This keeps the UI forgiving and avoids surprising empty states caused by conflicting control combinations.

## Empty states and validation

- Invalid `era` values should return the existing explicit `400` validation style.
- Invalid `position_group` values should return the existing explicit `400` validation style.
- Valid filters that produce no matches should return `200` with an empty `data` array.
- Frontend empty-state messaging should remain clear and non-alarming.

## Implementation surfaces

Expected code surfaces:

- `nwar/index.html` for the two new controls and any small explanatory copy updates
- `assets/nwar.js` for query-param handling, active-state framing, and table reload behavior
- `api/plumber.R` for request parsing and validation
- `api/R/helpers.R` for era scoping and position-group filtering
- `scripts/test_api_regression.R` for API-level regression coverage

## Testing requirements

Add regression coverage for:

1. all-seasons request with `era=anzc`
2. all-seasons request with `era=ssn`
3. each position-group filter
4. combined filters such as `season=2024&position_group=defender`
5. `season` overriding `era` when both are supplied
6. empty-result cases returning `200` with empty data
7. invalid `era` returning `400`
8. invalid `position_group` returning `400`

Frontend checks should confirm that:

- the new controls are reflected in the request URL/state
- the page copy updates to reflect active filters
- the table still renders correctly for empty, success, and error states

## Recommendation carried into implementation

Use the simple dropdown approach and keep all filter logic inside the existing nWAR page and endpoint. This gives users the archive slicing they want without adding UI complexity or creating a second mental model for how nWAR works.
