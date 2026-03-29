## Design Context

### Users
This product is for netball fans, writers, analysts, and curious supporters exploring Super Netball history.

The core job is to help them find trustworthy historical stats, season comparisons, and player or team context quickly and confidently. The experience should feel like a serious reference surface for evidence and exploration, not a casual novelty tool.

### Brand Personality
The brand should feel **editorial, confident, and distinctive**.

The interface should evoke confidence, clarity, and a sense of depth rather than hype. It should feel informed and composed, with the tone of a sharp sports almanac or data-journalism feature rather than a sales dashboard.

### Aesthetic Direction
Lean into an editorial sports almanac feel with modern data-visualisation polish.

Keep the current warm amber and teal direction unless there is a strong reason to change it. Support both dark and light themes. Preserve the custom typography system (`Fraunces` for body voice, `Teko` for display emphasis) and use it to create hierarchy with intent rather than ornament.

Domain cues can borrow from Champion Data and the official Super Netball ecosystem in terms of seriousness, specificity, and subject matter, but the product should explicitly avoid looking like a generic SaaS dashboard or a shiny gambling-style sports site.

### Design Principles
1. **Evidence first.** Interfaces should foreground trustworthy stats, clear labels, and traceable supporting detail over decorative flourish.
2. **Editorial, not dashboard.** Use layout, typography, and pacing that feel curated and story-aware instead of generic widget grids.
3. **Dense without confusion.** Complex data is welcome, but it must be progressively disclosed and easy to scan on both desktop and mobile.
4. **Accessibility is part of the aesthetic.** Maintain WCAG AA contrast, strong keyboard support, and respectful reduced-motion behaviour as non-negotiable design qualities.
5. **Distinctive consistency.** Reuse the shared visual system, but give major pages their own emphasis and hierarchy so the site feels cohesive without becoming templated.

### Stat and copy conventions
- Stat labels come from `STAT_LABEL_OVERRIDES` in `assets/config.js` via `formatStatLabel()`. Never hardcode display strings for stat names in page scripts.
- Use "Points" not "Goals" when referring to match scoring — team/player points are computed from goal1 + 2×goal2 (super shots are worth 2).
- Use netball terminology throughout. "First centre pass" not "tip-off". "Quarter" is correct. "Rebound" is a valid Champion Data stat.
- Keep copy tight. Avoid explanatory drag — the archive data should speak for itself.
