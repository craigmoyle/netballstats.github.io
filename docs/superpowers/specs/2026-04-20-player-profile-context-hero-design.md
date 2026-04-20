# Player Profile Hero Context Design

## Summary

Move the player identity details out of the separate lower-page context panel and into the hero aside, replacing the current **Career span** card with a compact **Profile** card.

The approved direction is:

1. rename the hero-aside card from **Career span** to **Profile**
2. show only **Birthday**, **Nationality**, and **Debut season**
3. remove the separate **Identity context / Profile context** panel entirely
4. remove the source or verification sentence as well

## Problem

The player page currently splits the profile context across two different surfaces:

- a hero-aside card labelled **Career span**
- a separate lower-page **Identity context / Profile context** panel

That makes the identity details feel secondary and duplicates attention across two nearby sections. The current panel also carries more fields than desired for this surface, including import status, experience, and a verification sentence.

## Goals

1. Make the player hero the primary home for lightweight profile context.
2. Reduce the identity surface to only the three approved fields:
   - Birthday
   - Nationality
   - Debut season
3. Remove the lower identity/context panel from the reading order.
4. Keep the change presentation-focused, using the existing player-profile payload where possible.

## Non-goals

- no new player-profile API endpoint
- no new profile metadata fields
- no identity verification copy on the page
- no changes to career totals, pillars, ledger, or compare flows

## Approved scope

### Hero card

The existing hero-aside card becomes the new profile summary surface.

It should:

- use the label **Profile**
- present the three approved fields in a compact, readable layout
- stop presenting the current career-span framing in that slot

### Lower-page identity panel

Remove the separate section currently labelled:

- eyebrow: **Identity context**
- heading: **Profile context**

This panel should not remain as a reduced duplicate.

## Design

### Data usage

Reuse the existing `profile.identity` payload fields already returned by the player-profile response:

- `date_of_birth`
- `nationality`
- `debut_season`

Do not render:

- `import_status`
- `experience_seasons`
- `reference_status`
- `source_label`

### Layout

Replace the current hero-aside content with a compact definition-list or equivalent key/value treatment that fits the existing hero card footprint.

Recommended content order:

1. Birthday
2. Nationality
3. Debut season

If any field is missing, use the current page pattern for unavailable identity values rather than inventing a new fallback style.

### Copy

Use **Profile** as the hero card label.

Do not add a verification footer, provenance sentence, or “identity context” subheading in the hero.

The rest of the player page should continue to rely on the existing editorial framing:

- career snapshot
- career pillars
- career totals
- season ledger

### Accessibility and behavior

- preserve the existing hero-aside semantics and readable heading order
- avoid introducing duplicated identity content in multiple places on the same page
- keep the profile details available as plain text, not tooltip-only or icon-only content

## Implementation shape

This should stay a focused frontend change with no required API contract change unless the current hero renderer cannot already access the needed fields.

Expected touch points:

- `player/index.html`
  - remove the lower identity panel markup
  - update the hero-aside label/structure
- `assets/player.js`
  - stop rendering the removed identity panel
  - render the approved three-field profile block in the hero instead
- page styles only if the existing hero card needs small spacing adjustments

## Testing

Update only the checks needed for this presentation move:

1. frontend syntax validation for `assets/player.js`
2. static build validation
3. any existing player-profile UI verification script that checks for removed panel hooks or the new hero content, if applicable

No new backend or data-build tests are required unless implementation proves otherwise.

## Risks and mitigations

### Hero card becomes too cramped

Risk: the existing hero-aside card may not comfortably fit three labelled fields.

Mitigation: use a compact stacked key/value layout and keep the content limited to the approved three fields only.

### Loss of useful context

Risk: removing import status and experience may make the page feel less informative.

Mitigation: follow the approved scope strictly; this change intentionally simplifies the identity surface and keeps deeper career framing elsewhere on the page.

### Duplicate references left behind

Risk: the removed panel’s copy or DOM hooks could remain partially wired.

Mitigation: remove the panel markup and corresponding render/status logic together so the page has one clear profile-context surface.
