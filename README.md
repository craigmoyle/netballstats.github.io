# Netball Stats Website

This repository now contains a secure-by-default Super Netball stats site backed by a read-only API and a database populated with the `superNetballR` package. It supports local SQLite for simple development and managed PostgreSQL for hosted deployments such as Azure.

## What changed

The old site was a single HTML page showing a few 2020 static images. The rewrite introduces:

- a modern query UI for seasons from 2017 onward, including multi-season comparisons and tunable row limits
- table/chart toggles for the team and player leaderboards, including season trend lines for fast visual comparisons
- a read-only R Plumber API with input validation, rate limiting, security headers, and parameterized SQL
- a database build script that uses `superNetballR::downloadMatch()` plus the package tidiers to populate either SQLite or PostgreSQL
- canonical player-name handling so leaderboard queries continue to work when players appear under multiple surnames over time
- additional high-value query views for single-game team and player highs
- Azure deployment files for Static Web Apps + Container Apps + PostgreSQL Flexible Server
- an explicit season competition manifest for Super Netball regular season and finals from 2017 to 2025

## Repository layout

- `index.html` + `assets/`: static frontend
- `api/plumber.R`: read-only API
- `api/R/helpers.R`: validation, database, and CORS helpers
- `scripts/build_database.R`: data ingestion and SQLite/PostgreSQL build
- `config/competitions.csv`: season-to-competition ID mapping
- `storage/`: database output location (gitignored)
- `azure.yaml` + `infra/`: Azure Developer CLI deployment files

The current frontend highlights:

- team leaderboard bar charts
- player leaderboard bar charts
- season-by-season trend lines for the leading teams and players
- table/chart toggles so the detailed tables remain available

## Local setup

Install the required R packages and the updated fork of `superNetballR`:

```r
install.packages(c("DBI", "RPostgres", "RSQLite", "plumber", "dplyr", "purrr"))
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

The database is written to `storage/netball_stats.sqlite` by default.

To target PostgreSQL instead, set either `NETBALL_STATS_DATABASE_URL` / `DATABASE_URL`, or the split settings below before running the build:

```sh
NETBALL_STATS_DB_BACKEND=postgres
NETBALL_STATS_DB_HOST=...
NETBALL_STATS_DB_PORT=5432
NETBALL_STATS_DB_NAME=netballstats
NETBALL_STATS_DB_USER=...
NETBALL_STATS_DB_PASSWORD=...
NETBALL_STATS_DB_SSLMODE=require
```

If you also set `NETBALL_STATS_API_DB_USERNAME` and `NETBALL_STATS_API_DB_PASSWORD` during a PostgreSQL build, the script will create or rotate a read-only API role and grant `SELECT` on the application tables.

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
- **Secrets hygiene**: `.env` files and SQLite files are ignored by Git, and the Azure deployment stores database passwords in Key Vault.

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

## Azure deployment

This repository now includes an Azure deployment path using:

- **Azure Static Web Apps Standard** for the frontend
- **Azure Container Apps** for the R Plumber API
- **Azure Database for PostgreSQL Flexible Server** for managed data storage
- **Azure Key Vault** for database passwords
- **Azure Container Registry** for the API image
- **Log Analytics** for Container Apps logs

### Azure files added

- `azure.yaml`: Azure Developer CLI project definition
- `infra/main.bicep`: subscription-scope entry point that creates the resource group
- `infra/modules/app-stack.bicep`: resource-group deployment for the app stack
- `infra/main.parameters.json`: environment-variable-driven defaults for `azd`
- `Dockerfile.azure`: API container image for Azure Container Apps
- `staticwebapp.config.json`: Azure Static Web Apps headers and API route configuration
- `scripts/build_static.mjs` + `package.json`: static asset build output for Azure Static Web Apps

The Azure template keeps most resources in `AZURE_LOCATION` (for example `australiaeast`) but deploys **Static Web Apps** separately in a supported region. By default that is `eastasia`, because Azure Static Web Apps is not available in every region.

### Provision with azd

Set the required Azure Developer CLI environment values first:

```sh
cd /Users/craig/Git/netballstats
azd env set AZURE_LOCATION australiaeast
azd env set NETBALL_STATS_POSTGRES_ADMIN_PASSWORD '<strong-admin-password>'
azd env set NETBALL_STATS_POSTGRES_API_PASSWORD '<strong-readonly-password>'
```

If you plan to use a custom frontend hostname, set it too:

```sh
azd env set NETBALL_STATS_CUSTOM_FRONTEND_HOSTNAME https://stats.example.com
```

Then validate and deploy:

```sh
azd provision --preview
azd up
```

If you are deploying from an Apple Silicon Mac, keep `azure.yaml` configured with `platform: linux/amd64` for the `api` service. Azure Container Apps remote builds only support that platform today.

`azd deploy` also expects the Container Registry login server under `AZURE_CONTAINER_REGISTRY_ENDPOINT`. The template now outputs that name during provisioning, and `azure.yaml` uses it explicitly for the API image push target.

### Seed PostgreSQL after provision

`azd up` provisions the infrastructure and deploys the frontend/API, but the database still needs to be populated from Champion Data. Run the ingestion script from a trusted machine or CI runner with network access:

```sh
NETBALL_STATS_DB_BACKEND=postgres \
NETBALL_STATS_DB_HOST='<postgres fqdn>' \
NETBALL_STATS_DB_PORT=5432 \
NETBALL_STATS_DB_NAME='netballstats' \
NETBALL_STATS_DB_USER='netballstatsadmin' \
NETBALL_STATS_DB_PASSWORD='<admin password>' \
NETBALL_STATS_DB_SSLMODE=require \
NETBALL_STATS_API_DB_USERNAME='netballstats_api' \
NETBALL_STATS_API_DB_PASSWORD='<readonly password>' \
Rscript scripts/build_database.R
```

That build step loads the application tables into PostgreSQL and grants `SELECT` permissions to the read-only API user that the Azure Container App uses at runtime.

When the build script targets PostgreSQL, it now disables PostgreSQL statement timeouts by default for that ingestion session so bulk `COPY` operations can complete. The API still keeps its short readiness/query timeout settings through the Container App environment.

### Azure deployment notes

- The generated Bicep uses a **user-assigned managed identity** for the Container App.
- The managed identity receives **AcrPull** on the Azure Container Registry and **Key Vault Secrets User** on the Key Vault.
- The Static Web App is configured on the **Standard** plan so it can link `/api/*` to the Container App backend.
- `assets/config.js` now defaults to `/api` for non-local, non-Cloudflare hosts, which matches the Azure linked-backend pattern.
- Azure Container Apps probes now use `/live` for process liveness and `/ready` for PostgreSQL readiness, while `/health` remains the richer operator-facing status endpoint.
