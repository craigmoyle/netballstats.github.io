# Netball Stats Website

This repository now contains a secure-by-default Super Netball stats site backed by a read-only API and a SQLite database populated with the `superNetballR` package.

## What changed

The old site was a single HTML page showing a few 2020 static images. The rewrite introduces:

- a modern query UI for seasons from 2017 onward
- a read-only R Plumber API with input validation, rate limiting, security headers, and parameterized SQL
- a database build script that uses `superNetballR::downloadMatch()` plus the package tidiers to populate SQLite
- an explicit season competition manifest for Super Netball regular season and finals from 2017 to 2025

## Repository layout

- `index.html` + `assets/`: static frontend
- `api/plumber.R`: read-only API
- `api/R/helpers.R`: validation, database, and CORS helpers
- `scripts/build_database.R`: data ingestion and SQLite build
- `config/competitions.csv`: season-to-competition ID mapping
- `storage/`: database output location (gitignored)

## Local setup

Install the required R packages and the updated fork of `superNetballR`:

```r
install.packages(c("DBI", "RSQLite", "plumber", "dplyr", "purrr"))
remotes::install_github("craigmoyle/superNetballR_updated")
```

### Build a sample database

Use the bundled `superNetballR` example data when you want to validate the site locally without calling Champion Data:

```sh
cd /Users/craig/Git/netballstats
NETBALL_STATS_SAMPLE=true Rscript scripts/build_database.R
```

### Build the full database from Champion Data

When you are on a machine with outbound internet access and valid Champion Data access, run:

```sh
cd /Users/craig/Git/netballstats
Rscript scripts/build_database.R
```

The database is written to `storage/netball_stats.sqlite` by default. Override the output path with `NETBALL_STATS_DB=/path/to/netball_stats.sqlite`.

### Run the API locally

```sh
cd /Users/craig/Git/netballstats
NETBALL_STATS_ALLOWED_ORIGINS=http://127.0.0.1:4173,http://localhost:4173 \
Rscript scripts/run_api.R
```

If you prefer the inline form, use single quotes so your shell does not expand `pr$run(...)`:

```sh
Rscript -e 'pr <- plumber::plumb("api/plumber.R"); pr$run(host = "127.0.0.1", port = 8000)'
```

### Serve the frontend locally

```sh
cd /Users/craig/Git/netballstats
python3 -m http.server 4173
```

If your API is hosted elsewhere, edit `assets/config.js` and set `apiBaseUrl` to the deployed API origin.

## Security model

The site is designed to minimise risk:

- **No public write endpoints**: the API is read-only.
- **Offline refreshes**: the database should be refreshed by a scheduled job, not through a public admin endpoint.
- **Prepared SQL**: every API query uses `DBI::sqlInterpolate()`.
- **Strict validation**: seasons, team IDs, rounds, limits, stats, and player search terms are validated before querying.
- **Result caps**: every list endpoint enforces hard maximum limits.
- **Security headers**: the API sets `X-Frame-Options`, `X-Content-Type-Options`, HSTS, a strict referrer policy, and a restrictive permissions policy.
- **CORS allow-list**: only the origins you explicitly configure are granted cross-origin access.
- **Rate limiting**: a simple request-per-minute guard is enabled by default.
- **Secrets hygiene**: `.env` files and SQLite files are ignored by Git.

## Deployment target configured in this repo

This repository is now set up for the hobby-friendly deployment target you chose:

- **Cloudflare Pages Free** for the static frontend
- **Render Starter ($7/mo)** for the R Plumber API
- **SQLite baked into the Render image at deploy time**

That keeps the recurring cost to the Render Starter service only. The trade-off is that the database is rebuilt whenever Render performs a fresh deploy, so the simplest refresh workflow is to redeploy the service when you want newer stats.

### Cloudflare Pages setup

1. Create a new Pages project from this repository.
2. Use:
   - **Framework preset:** None
   - **Build command:** leave blank
   - **Build output directory:** `.`
3. Deploy the repository root as-is.

Cloudflare Pages will automatically apply the root `_headers` file, which adds the frontend security headers and locks browser API calls to `https://netballstats-api.onrender.com`.

### Render setup

This repository includes:

- `Dockerfile` to install R, the required packages, and `superNetballR`
- `render.yaml` to provision a **Starter** web service called **`netballstats-api`**
- a Docker build step that runs `Rscript scripts/build_database.R` so the SQLite database is created during deployment

To deploy:

1. In Render, create a Blueprint or new web service from this repository.
2. Use the included `render.yaml`.
3. Set **`NETBALL_STATS_ALLOWED_ORIGINS`** to your actual frontend origins, for example:

```text
https://your-project.pages.dev,https://netballstats.pages.dev
```

Because the frontend config defaults to `https://netballstats-api.onrender.com`, the simplest path is to keep the Render service name as `netballstats-api`.

### Refreshing the hobby deployment

The hobby setup avoids a separate managed database or persistent disk. That keeps the cost low, but it means database updates are tied to deploys.

To refresh the data:

- trigger a manual Render redeploy, or
- push a small commit to this repository to trigger a new build

Each new Render deploy rebuilds `storage/netball_stats.sqlite` inside the image using the latest Champion Data responses available to `superNetballR`.

## Hosting suggestions

For this repository as currently written, **Cloudflare Pages Free + Render Starter** is the simplest low-maintenance hobby option.

If you later want faster refreshes, persistent state across deploys, or a safer long-term datastore, the next upgrade would be:

- keep **Cloudflare Pages** for the frontend
- keep **Render** for the API
- move the database to either a Render persistent disk or a managed Postgres service

## Operational suggestions

- Run the database refresh on a schedule instead of refreshing during user requests.
- Use a read-only database user for the API and a separate write-capable user for ingestion jobs.
- Put the API behind HTTPS only and terminate TLS at your hosting platform.
- Log validation failures and high-rate clients.
- Revisit `config/competitions.csv` at the start of each season because Champion Data competition IDs change year to year.
- Consider moving to PostgreSQL once you want multi-process writes, richer indexing, or safer remote hosting.
