# Netball Stats Website

`netballstats` is an editorial Super Netball archive: a static frontend on Azure Static Web Apps, a read-only R Plumber API on Azure Container Apps, and a PostgreSQL database refreshed by scheduled Container Apps jobs using `superNetballR`.

The production operating model is now **Azure + PostgreSQL first**. Legacy Render/Cloudflare deployment notes remain below as an alternative, but the repo, docs, and runtime defaults are centred on the Azure stack.

## What’s in the app

- multi-season leaderboard and comparison views from 2017 onward
- team and player leaderboard charts plus season trend lines
- natural-language “Ask the stats” queries with parsed query explanations
- player directory and player profile pages with career and season summaries
- read-only API endpoints with validation, rate limiting, security headers, and parameterized SQL
- scheduled database refresh jobs that rebuild the archive from Champion Data via `superNetballR`

## Repository layout

- `index.html` + `assets/`: static frontend
- `query/`, `compare/`, `players/`, `player/`: page shells for the major frontend flows
- `api/plumber.R`: read-only API entry point
- `api/R/helpers.R`: validation, query-building, and response helpers
- `R/database.R`: PostgreSQL connection helpers and runtime DB config
- `scripts/build_database.R`: PostgreSQL ingestion / rebuild script
- `scripts/run_api.R`: local API runner
- `scripts/test_api_regression.R`: endpoint smoke/regression checks
- `config/competitions.csv`: season-to-competition manifest
- `azure.yaml` + `infra/`: Azure Developer CLI and Bicep deployment files
- `renv.lock` + `renv/`: reproducible R dependency management

## Local development

### Restore R dependencies

Install `renv` once, then restore the pinned package set for this repo:

```sh
cd /Users/craig/Git/netballstats
Rscript -e "install.packages('renv', repos = 'https://cloud.r-project.org')"
Rscript -e "renv::restore(prompt = FALSE)"
```

### Start a local PostgreSQL instance

The app now runs against PostgreSQL only. For quick local work, a disposable Docker container is the simplest option:

```sh
docker run --rm --name netballstats-postgres \
  -e POSTGRES_DB=netballstats \
  -e POSTGRES_USER=netballstatsadmin \
  -e POSTGRES_PASSWORD=netballstatsadmin \
  -p 5432:5432 \
  postgres:16
```

In a second shell, export the connection settings used by the build and API scripts:

```sh
export NETBALL_STATS_DB_HOST=127.0.0.1
export NETBALL_STATS_DB_PORT=5432
export NETBALL_STATS_DB_NAME=netballstats
export NETBALL_STATS_DB_USER=netballstatsadmin
export NETBALL_STATS_DB_PASSWORD=netballstatsadmin
export NETBALL_STATS_DB_SSLMODE=disable
export NETBALL_STATS_API_DB_USERNAME=netballstats_api
export NETBALL_STATS_API_DB_PASSWORD=netballstats_api_password
```

### Build a sample database

Use the bundled `superNetballR` example data when you want to validate the app without calling Champion Data:

```sh
cd /Users/craig/Git/netballstats
NETBALL_STATS_SAMPLE=true Rscript scripts/build_database.R
```

### Build the full database from Champion Data

When you have outbound access and valid Champion Data credentials, run:

```sh
cd /Users/craig/Git/netballstats
Rscript scripts/build_database.R
```

The build script writes directly to PostgreSQL and, when `NETBALL_STATS_API_DB_USERNAME` / `NETBALL_STATS_API_DB_PASSWORD` are set, rotates the read-only API role used at runtime.

### Run the API locally

```sh
cd /Users/craig/Git/netballstats
NETBALL_STATS_ALLOWED_ORIGINS=http://127.0.0.1:4173,http://localhost:4173 \
Rscript scripts/run_api.R
```

If you prefer the inline form, keep the single quotes so your shell does not expand `pr$run(...)`:

```sh
Rscript -e 'pr <- plumber::plumb("api/plumber.R"); pr$run(host = "127.0.0.1", port = 8000)'
```

### Serve the frontend locally

```sh
cd /Users/craig/Git/netballstats
python3 -m http.server 4173
```

For non-local hosts the frontend defaults to `/api`, which matches the Azure Static Web Apps linked-backend path.

### Run the API regression suite

With the API running locally:

```sh
cd /Users/craig/Git/netballstats
Rscript scripts/test_api_regression.R
```

To target another environment, pass a base URL or set `NETBALL_STATS_API_BASE_URL`:

```sh
Rscript scripts/test_api_regression.R --base-url=https://your-api.example.com
```

## Security model

The application is intentionally conservative:

- **No public write endpoints**: the API is read-only.
- **Prepared SQL**: every endpoint queries through parameterized SQL.
- **Strict validation**: seasons, limits, player IDs, team IDs, stats, and query text are validated before use.
- **Result caps**: list endpoints enforce hard maximum limits.
- **Explicit CORS allow-list**: only configured origins can call the API cross-origin.
- **Security headers**: HSTS, frame busting, content-type hardening, referrer policy, and permissions policy are all set in the API.
- **Rate limiting**: the API applies a simple request-per-minute guard.
- **Secrets in Key Vault**: Azure deployment keeps DB credentials out of repo files.
- **Structured request telemetry**: the API logs request path, status, latency, and slow/failing requests without dumping raw database errors into normal logs.

## Azure deployment (primary path)

This repository is prepared for:

- **Azure Static Web Apps Standard** for the frontend
- **Azure Container Apps** for the R Plumber API
- **Azure Database for PostgreSQL Flexible Server** for the application database
- **Azure Container Apps Jobs** for scheduled database refreshes
- **Azure Key Vault** for secret storage
- **Azure Container Registry** for API image builds
- **Log Analytics** for Container Apps logs and request telemetry

### Azure files in this repo

- `azure.yaml`: Azure Developer CLI project definition
- `infra/main.bicep`: subscription-scope entry point
- `infra/modules/app-stack.bicep`: resource-group stack
- `infra/main.parameters.json`: env-driven defaults for `azd`
- `Dockerfile.azure`: API image build for Azure Container Apps
- `staticwebapp.config.json`: Static Web Apps routing + headers
- `.github/workflows/deploy-azure-static-web-app.yml`: static frontend deployment workflow

### Required azd environment values

```sh
cd /Users/craig/Git/netballstats
azd env set AZURE_LOCATION australiaeast
azd env set NETBALL_STATS_POSTGRES_ADMIN_PASSWORD '<strong-admin-password>'
azd env set NETBALL_STATS_POSTGRES_API_PASSWORD '<strong-readonly-password>'
```

If you use a custom frontend hostname, add it too:

```sh
azd env set NETBALL_STATS_CUSTOM_FRONTEND_HOSTNAME https://stats.example.com
```

### Optional staged private PostgreSQL networking

The Bicep now includes an **opt-in** private-networking path for PostgreSQL and the Container Apps environment. It is intentionally disabled by default so current public deployments do not attempt a destructive in-place migration.

Enable it only when you are ready for a staged infrastructure cutover:

```sh
azd env set NETBALL_STATS_PRIVATE_POSTGRES_NETWORKING_MODE enabled
```

Optional CIDR / DNS overrides:

```sh
azd env set NETBALL_STATS_VNET_ADDRESS_PREFIX 10.30.0.0/16
azd env set NETBALL_STATS_CONTAINERAPPS_INFRA_SUBNET_PREFIX 10.30.0.0/21
azd env set NETBALL_STATS_POSTGRES_DELEGATED_SUBNET_PREFIX 10.30.8.0/28
azd env set NETBALL_STATS_POSTGRES_PRIVATE_DNS_ZONE_NAME netballstats.private.postgres.database.azure.com
```

Important notes:

- enabling private networking may require Azure to recreate the Container Apps environment
- treat it as a planned migration, not a casual toggle on a live environment
- when private networking is enabled, the broad `0.0.0.0` PostgreSQL firewall rule is skipped automatically

### Provision and deploy

```sh
cd /Users/craig/Git/netballstats
azd provision --preview
azd up
```

If you are deploying from Apple Silicon, keep `azure.yaml` configured with `platform: linux/amd64` for the API service.

### Seed or refresh PostgreSQL

`azd up` provisions infrastructure and deploys the API/frontend, but the database still needs a build from Champion Data. From a trusted machine or CI runner:

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

The deployed stack also provisions two scheduled Container Apps jobs:

- Saturday at **21:00 AEST**
- Sunday at **18:00 AEST**

Those jobs rebuild the database in Azure using the deployed API image.

### Validate the deployed API

After deployment, run the regression checks against the public API:

```sh
NETBALL_STATS_API_BASE_URL=https://<api-fqdn> Rscript scripts/test_api_regression.R
```

### Azure deployment notes

- The API uses a **user-assigned managed identity** for ACR pulls and Key Vault secret reads.
- Container Apps probes use `/live` for liveness and `/ready` for DB readiness.
- The API emits structured request-complete / request-slow / request-failed log lines with endpoint latency.
- Docker builds now restore R packages from `renv.lock`, so local, CI, and Azure builds all use the same dependency set.

## Frontend build

Build the static site with:

```sh
npm run build
```

That writes the deployable frontend into `dist/`.

## Legacy alternative: Cloudflare Pages + Render

The repo still contains `render.yaml` and the generic `Dockerfile` for a lower-cost hobby path. That route is now considered a legacy alternative rather than the default operating model.

If you use it:

- prefer PostgreSQL rather than baking SQLite into the image
- keep the API read-only and refresh data from an offline/scheduled job
- run `Rscript scripts/test_api_regression.R --base-url=<render-api-url>` after each deploy

## Operational suggestions

- Revisit `config/competitions.csv` at the start of each season because Champion Data competition IDs change year to year.
- Keep the API and refresh jobs on separate credentials: read-only for the API, write-capable for ingestion.
- Use the request telemetry logs to identify true hot endpoints before introducing caching or Redis.
- Treat private-networking enablement as a migration project with a maintenance window.
