# AGENTS.md

This file captures the repo-specific context, decisions, and operating guidance that future agents should keep in mind when working in `netballstats`.

## Product and UX intent

- This product is for netball fans, writers, analysts, and curious supporters exploring Super Netball history.
- The experience should feel editorial, confident, and distinctive: more like a sports almanac or data-journalism feature than a SaaS dashboard.
- Keep the warm amber and teal palette unless there is a strong reason to change it.
- Support both dark and light themes.
- Preserve the typography system: `Fraunces` for body/editorial voice and `Teko` for display emphasis.
- Accessibility is part of the product quality bar: WCAG AA contrast, strong keyboard support, and respectful reduced-motion behaviour are non-negotiable.

## System shape

- Frontend: static HTML and vanilla JS, built into `dist/` and deployed to Azure Static Web Apps.
- API: read-only R Plumber service in `api/plumber.R`, deployed to Azure Container Apps.
- Database: Azure Database for PostgreSQL Flexible Server.
- Data refresh: scheduled Azure Container Apps jobs rebuild the database from Champion Data via `superNetballR`.
- Infra and deploy: `azure.yaml` plus Bicep under `infra/`.

## Operating model decisions

- Azure plus PostgreSQL is the primary supported deployment path.
- Render/Cloudflare notes in the README are legacy alternatives, not the default operating model.
- The API is intentionally read-only. Do not introduce public write endpoints without an explicit product decision.
- Keep validation and result caps strict. The current posture favours trustworthy, bounded queries over permissive behaviour.
- Continue using parameterized SQL and explicit request validation across the API surface.
- Avoid broad try/catch wrappers or silent fallbacks. Surface or log errors in the same explicit style already used in the repo.
- The per-replica in-memory rate limiter does not aggregate across Container App replicas. This is acceptable while `apiMaxReplicas` is 1 but would need a centralized store (e.g. Redis) if scaling beyond a single replica.

## Telemetry decisions

- Browser usage telemetry is enabled and should stay privacy-safe.
- Browser telemetry loads runtime config from `/meta`, posts same-origin to `/api/telemetry`, and the API forwards sanitized events to Application Insights.
- Do not enable automatic fetch/XHR capture for browser telemetry; this was intentionally disabled to avoid collecting raw Ask the Stats URLs and question text.
- Do not log raw Ask the Stats free-text prompts in telemetry.
- Browser page views land in `AppPageViews`; custom interactions land in `AppEvents`.
- Existing page view names include `archive-home`, `compare`, and `player-profile`.
- Player URLs are sanitized to `/player/:id/` in telemetry.
- `scripts/usage-telemetry.kql` is the starter report file and its query blocks are intentionally self-contained so they can be run independently.

## Frontend conventions

- Reuse the shared UI helpers in `assets/config.js` instead of adding page-specific one-off behaviour where a shared helper already exists.
- Use `window.NetballStatsUI.showStatusBanner` and `cycleStatusBanner` for rotating loading copy and ephemeral success states.
- Use `window.NetballStatsUI.syncResponsiveTable` for dynamic stackable tables so mobile card layouts stay labelled correctly.
- `theme.js` owns the reveal-animation observer logic. Do not reintroduce a second `IntersectionObserver` setup elsewhere.
- Keep major pages visually distinct, but within the same editorial system. The product should feel cohesive without every page feeling templated.

### Stat labels
- Use `window.NetballStatsUI.formatStatLabel(key)` everywhere a stat key needs a human-readable label. Do not hardcode display strings for stat names.
- `STAT_LABEL_OVERRIDES` in `assets/config.js` is the canonical map of camelCase stat key → label (e.g. `goalAssists` → "Goal Assists", `feeds` → "Feeds into Circle", `points` → "Points"). Add new overrides there, not in page scripts.
- Use `window.NetballStatsUI.statPrefersLowerValue(key)` to determine whether a stat should highlight the *lowest* value as best (turnovers, penalties, etc.).
- `LOW_IS_BETTER_STATS` in `assets/config.js` is the canonical set of stat keys that prefer lower values.

### Table wrapping on desktop
- Leader tables (`#player-leaders-table`, `#team-leaders-table`) use `white-space: nowrap` scoped to `@media (min-width: 681px)`. The `.table-wrapper` already provides `overflow-x: auto`, so the table scrolls horizontally rather than wrapping cells. Do not remove the `nowrap` rule.

### Round recap frontend
- `ordinalSuffix(n)` in `assets/round.js` handles 1st/2nd/3rd/11th–13th edge cases correctly.
- `standoutNote()` prepends `historical_rank` context ("34th highest all-time") before badges and date info when the entry carries a rank value.
- The rank direction ("highest" vs "lowest") is read from `entry.ranking`.

### Copy and language conventions
- Use netball terminology, not basketball terms. "First centre pass" not "tip-off". "Quarter" is correct for netball; "rebound" appears in Champion Data stats and is valid.
- Keep UI copy tight. Avoid explanatory drag — the data should speak for itself.

## Backend and data conventions

- `api/R/helpers.R` contains much of the validation, query-building, and transformation logic; prefer extending existing helpers over duplicating logic.
- The natural-language query flow now supports a parsed `seasons` array for multi-season filters. Preserve that shape when extending query parsing.
- The API should continue logging structured request and error telemetry without dumping raw internal database errors into normal logs.
- Keep the API conservative about privacy and high-cardinality fields.

### Points vs goals
- The database has no `points` stat in `player_match_stats`. `goal1` = 1-point shots made; `goal2` = super shots (worth 2 points each).
- Player points per game = `goal1 + 2 × goal2` — computed via a self-join on `player_match_stats`.
- Team points per game come from `matches.home_score` / `matches.away_score` (the true match scores), not from player stats.
- Use "points" (not "goals") when referring to match scoring in UI copy and round summaries.
- `fetch_player_points_high()` and `fetch_team_points_high()` are dedicated helpers for this; do not try to use the generic `fetch_player_game_high_rows()` with `stat = 'points'` — "points" is a synthetic stat and that fetcher expects a real `player_match_stats` stat key.

### Historical ranking
- `compute_archive_rank()` computes all-time `COUNT(*) + 1` ranking (standard competition ranking) across all seasons.
- Four cases: player points (goal1+2×goal2 subquery), team points (matches UNION ALL), player regular stats (index scan on `idx_pms_stat_value`), team regular stats (aggregation subquery on `team_period_stats`).
- Always wrap `compute_archive_rank()` calls in `tryCatch` — a failed rank query must not crash the enclosing endpoint.
- `points_record_badges()` is separate from `game_record_badges()` for the same reason: `game_record_badges()` calls the generic fetchers internally, which cannot handle the synthetic "points" stat.

### SQLite compatibility
- Use `append_integer_in_filter()` for `IN (?, ?, ...)` clauses — not `ANY(ARRAY[...])`. The API must work with both PostgreSQL and SQLite (used in local dev and tests).

### Round recap
- `build_round_summary_payload()` generates 12 spotlights: 6 player stats (points, goalAssists, feeds, gain, deflections, intercepts) and 6 team stats (points, gain, deflections, intercepts, penalties, generalPlayTurnovers). The last two team stats rank lowest-is-best.
- Each spotlight entry carries `historical_rank` (integer or NULL). The frontend renders this as e.g. "34th highest all-time" or "2nd lowest all-time".
- Each round-summary call now executes ~50 DB queries. Acceptable for Azure PostgreSQL but worth monitoring if latency becomes an issue.

## Azure and deployment notes

- Build the static site with `npm run build`.
- The repo does not currently provide an `npm test` script.
- The practical validation commands used in this repo are:
  - `node --check assets/*.js`
  - `Rscript -e "parse(file='api/R/helpers.R'); parse(file='api/plumber.R')"`
  - `npm run build`
  - `Rscript scripts/test_api_regression.R` against a running environment when API behaviour changes
- For frontend-only changes, prefer `azd deploy web`.
- `azure.yaml` has a `postdeploy` hook that syncs the database refresh jobs to the current API image and triggers an immediate rebuild job. Keep that relationship intact.
- Pushes to `main` only deploy the Static Web App through GitHub Actions. The database refresh jobs are not automatically updated by that workflow; they are synchronized during `azd` deploys.
- Container images must keep the `renv` cache outside `/root` because the app runs as a non-root user and the library symlinks must remain traversable at runtime.
- On Apple Silicon, keep the Azure API build targeting `linux/amd64` as configured in `azure.yaml`.

### `azd provision` resets job images
- `azd provision` resets Container App Job images to `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest` (the Bicep placeholder).
- Always run `azd deploy api` after any `azd provision` to restore the real R image via the postdeploy hook.
- Without this step, DB rebuild jobs will fail immediately with `exec: "Rscript": executable file not found in $PATH`.

### PostgreSQL extensions and parameters
- Azure PostgreSQL Flexible Server requires extensions to be allow-listed via the `azure.extensions` server parameter before `CREATE EXTENSION` works in SQL.
- Currently allow-listed: `pg_trgm,pgaudit`. Add new extensions there before referencing them in `build_database.R`.
- `pgaudit.log` valid values: `none`, `read`, `write`, `function`, `role`, `ddl`, `misc`, `all`. The value `mod` is NOT valid.

### DB refresh job and API user sync
- `build_database.R` calls `configure_postgres_api_user()` to create/sync the read-only `netballstats_api` DB user.
- This function requires `NETBALL_STATS_API_DB_USERNAME` and `NETBALL_STATS_API_DB_PASSWORD` env vars to be set on the job. If both are absent the function silently skips — the API user will not be created or have its password updated.
- Both env vars are now present in `dbRefreshEnv` in `infra/modules/app-stack.bicep`. Do not remove them.
- `dbJobIdentity` must have Key Vault Secrets User access to both `postgres-admin-password` and `postgres-api-password` secrets.

### SSL with Azure PostgreSQL
- The API and refresh jobs use `NETBALL_STATS_DB_SSLMODE=verify-full` and `NETBALL_STATS_DB_SSLROOTCERT=system`.
- `sslrootcert=system` (libpq 14+) uses the OS trust store. Ubuntu Noble's `ca-certificates` package includes the DigiCert root CA that signs Azure PostgreSQL Flexible Server certificates. No cert download is needed.
- Do not attempt to download the DigiCert cert from `dl.cacerts.digicert.com` — that URL has an SSL hostname mismatch.

## Registry cleanup workflow decisions

- `.github/workflows/cleanup-registry.yml` uses GitHub OIDC with a federated Azure app registration.
- The workflow requires:
  - GitHub secret `AZURE_CLIENT_ID`
  - GitHub secret `AZURE_TENANT_ID`
  - GitHub variable `AZURE_SUBSCRIPTION_ID`
  - GitHub variable `AZURE_REGISTRY_NAME`
- The federated service principal needs both `AcrPull` and `AcrDelete` on the registry. `AcrDelete` alone is not enough because the workflow must enumerate repositories and tags before pruning.
- The workflow intentionally skips cleanly when its Azure configuration is incomplete.

## Repo map

- `assets/`: frontend scripts and shared UI helpers
- `query/`, `compare/`, `players/`, `player/`: major frontend pages
- `api/plumber.R`: API entry point and telemetry forwarding endpoint
- `api/R/helpers.R`: query parsing, validation, and response helpers
- `scripts/test_api_regression.R`: endpoint smoke/regression coverage
- `scripts/usage-telemetry.kql`: starter usage and product analytics queries
- `azure.yaml` and `infra/`: Azure deployment definitions
- `Dockerfile.azure`: Azure runtime image for the API

## Preferred change style

- Make surgical changes that preserve the existing product tone and operating model.
- Prefer extending existing helpers and utilities over adding parallel systems.
- Keep telemetry privacy-safe and low-cardinality.
- Keep docs aligned with Azure-first deployment and the current production architecture.

## Known pitfalls

- `scripts/usage-telemetry.kql` blocks should stay self-contained. Query tabs in the portal are often run individually, so shared `let` bindings across sections break easily.
- Browser telemetry should keep using the `/meta` bootstrap plus `/api/telemetry` proxy path. Direct browser-to-App-Insights changes risk losing sanitization and privacy guarantees.
- Do not re-enable fetch/XHR auto-tracking in telemetry. It can capture raw Ask the Stats URLs and undo the current privacy posture.
- `theme.js` already owns reveal-observer behaviour. Reintroducing observer setup in `config.js` or page scripts creates duplication and drift.
- `assets/query.js` has historically been sensitive to missing DOM hooks. Guard page-specific selectors instead of assuming every element exists.
- `azure.yaml` postdeploy keeps the database refresh jobs aligned with the API image. Frontend-only GitHub Actions deploys do not update those jobs.
- **`azd provision` resets job images to the hello-world placeholder.** Always run `azd deploy api` after any `azd provision` or jobs will fail with `Rscript not found`.
- If the API image/runtime changes, keep the `renv` cache outside `/root` or the non-root Container App user will hit broken library symlinks at runtime.
- The registry cleanup workflow can authenticate successfully and still fail functionally if the service principal lacks `AcrPull`; it needs both `AcrPull` and `AcrDelete`.
- Do not use `fetch_player_game_high_rows()` or `fetch_team_game_high_rows()` with `stat = 'points'`. "Points" is synthetic (goal1 + 2×goal2 / match scores); use `fetch_player_points_high()` and `fetch_team_points_high()` instead.
- Do not use `ANY(ARRAY[...])` syntax for IN clauses. Use `append_integer_in_filter()` to stay SQLite-compatible.
- The homepage hero `h1` uses a home-specific font-size override (`.hero-copy--home h1`) with a tighter `clamp()` than the global heading scale. Do not remove it — the global scale is too large for the 1240px shell at mid-range viewport widths.
- Archive filter toggles use `field--toggle` class (not `compare-mode-toggle`) to avoid inheriting pill-button wrapping from the compare page styles.
- Do not remove `NETBALL_STATS_API_DB_USERNAME` / `NETBALL_STATS_API_DB_PASSWORD` from `dbRefreshEnv` in Bicep. Without them the API DB user is never created/synced and the API will fail authentication after a fresh rebuild.
- `render.yaml` and the root `Dockerfile` are legacy Render deployment files and should not be used; Azure deployment uses `Dockerfile.azure`.
- The `_headers` file duplicates `staticwebapp.config.json` and may contain stale CSP origins (e.g. Render API).
- `buildUrl()` and `fetchJson()` should be used from the shared `window.NetballStatsUI` module, not redefined per page script.
- The Saturday DB refresh job (`dbRefreshJobSat`) should have explicit `resources` (cpu/memory) matching the Sunday job.
