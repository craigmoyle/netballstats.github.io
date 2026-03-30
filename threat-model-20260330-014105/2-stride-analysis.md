# STRIDE-A Analysis — netballstats

## Summary Table

| Component | S | T | R | I | D | E | A | Total | T1 | T2 | T3 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| SWAFrontend | 1 | 1 | 1 | N/A | N/A | N/A | 1 | 4 | 3 | 1 | 0 |
| PlumberAPI | 2 | 1 | 1 | 1 | 1 | 1 | 1 | 8 | 5 | 2 | 1 |
| DBRefreshJob | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 7 | 0 | 0 | 7 |
| PostgreSQL | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 7 | 2 | 5 | 0 |
| KeyVault | 1 | 1 | 1 | 1 | N/A | 1 | 1 | 6 | 0 | 4 | 2 |
| AppInsights | 1 | 1 | 1 | 1 | 1 | N/A | N/A | 5 | 5 | 0 | 0 |
| AzureContainerRegistry | 1 | 1 | 1 | 1 | N/A | 1 | N/A | 5 | 0 | 5 | 0 |
| ChampionData | 1 | 1 | 1 | 1 | 1 | N/A | 1 | 6 | 0 | 0 | 6 |
| AzureAD | 1 | 1 | 1 | 1 | N/A | 1 | 1 | 6 | 0 | 4 | 2 |
| **Totals** | | | | | | | | **54** | **15** | **21** | **18** |

N/A = category genuinely not applicable to component (not counted in totals).

---

## C04 — SWAFrontend {#swafrontend}

**Boundary**: PublicInternet | **Tier**: T1 | **Listens on**: 443 (Azure CDN)

### S — Spoofing {#swafrontend-s}

| ID | Description | Tier | Status |
|---|---|---|---|
| T01.S.1 | An attacker registers a typosquatting domain mimicking the SWA hostname to phish users who mistype the URL. The SWA custom domain has no DNSSEC or CAA record enforcement configured in the Bicep template. | T1 | Open |

### T — Tampering {#swafrontend-t}

| ID | Description | Tier | Status |
|---|---|---|---|
| T01.T.1 | App Insights browser SDK is loaded from multiple `https://js.monitor.azure.com` and `js.cdn.applicationinsights.io` CDN hostnames listed in the `script-src` CSP without Subresource Integrity (SRI) hashes. A compromised CDN endpoint could serve malicious JavaScript to all users. | T1 | Open |

### R — Repudiation {#swafrontend-r}

| ID | Description | Tier | Status |
|---|---|---|---|
| T01.R.1 | CDN access logs are not explicitly exported from Azure SWA to a Log Analytics workspace or SIEM. Access patterns (e.g. scraping, reconnaissance) cannot be audited after the fact. | T2 | Open |

### I — Information Disclosure {#swafrontend-i}

N/A — SWAFrontend delivers pre-built static files only; it holds no server-side session state or user data. XSS risk from CDN compromise is captured under T01.T.1.

### D — Denial of Service {#swafrontend-d}

N/A — Azure SWA includes platform-managed DDoS protection and CDN rate controls. No application-layer denial-of-service surface exists on the static host itself.

### E — Elevation of Privilege {#swafrontend-e}

N/A — SWAFrontend has no authentication model; no server-side privilege escalation path exists.

### A — Abuse {#swafrontend-a}

| ID | Description | Tier | Status |
|---|---|---|---|
| T01.A.1 | Automated bots can load the SWA landing pages at scale, triggering each page's `/api/*` calls and increasing backend API request volume without human interaction. The SWA itself provides no bot detection. | T1 | Open |

---

## C05 — PlumberAPI {#plumberapi}

**Boundary**: AzureContainerApps | **Tier**: T1 | **Listens on**: 8000 (ACA external ingress → 443)

### S — Spoofing {#plumberapi-s}

| ID | Description | Tier | Status |
|---|---|---|---|
| T02.S.1 | PlumberAPI exposes all endpoints without client authentication. Any HTTP client can impersonate a legitimate browser. CORS headers restrict cross-origin browser access but do not prevent direct scripted requests to the ACA ingress URL. | T1 | Open |
| T02.S.2 | The rate limiter keys on the leftmost `X-Forwarded-For` address. A multi-hop proxy chain under attacker control can prepend a spoofed IP, causing rate-limit accounting to be attributed to an innocent address instead of the true origin. | T2 | Open |

### T — Tampering {#plumberapi-t}

| ID | Description | Tier | Status |
|---|---|---|---|
| T02.T.1 | The rate-limiter state is an in-process R environment (`new.env(parent=emptyenv())`). With `maxReplicas: 2` in the ACA configuration each replica maintains independent state, allowing an attacker to exceed the intended per-IP limit by distributing requests across replicas. | T1 | Open |

### R — Repudiation {#plumberapi-r}

| ID | Description | Tier | Status |
|---|---|---|---|
| T02.R.1 | The `/api/telemetry` POST endpoint is explicitly listed in `request_telemetry_ignored`. If a malicious or malformed telemetry batch triggers downstream App Insights failures there is no request-level log entry to support attribution or replay analysis. | T1 | Open |

### I — Information Disclosure {#plumberapi-i}

| ID | Description | Tier | Status |
|---|---|---|---|
| T02.I.1 | The `/meta` endpoint returns the App Insights connection string (`telemetry.connection_string`) as a plain JSON field to any unauthenticated caller. The connection string is sufficient to submit arbitrary telemetry events to the App Insights workspace. | T1 | Open |

### D — Denial of Service {#plumberapi-d}

| ID | Description | Tier | Status |
|---|---|---|---|
| T02.D.1 | Per-replica in-process rate limiting allows an attacker to send up to `N × rate_limit` requests before any single replica triggers a 429 response. With two replicas and the default 60 req/60 s limit the effective limit is 120 req/60 s. High request volume targeting multiple ACA internal IPs consumes CPU and exhausts the in-process cache memory before the 10-minute prune interval fires. | T1 | Open |

### E — Elevation of Privilege {#plumberapi-e}

| ID | Description | Tier | Status |
|---|---|---|---|
| T02.E.1 | If the container image deployed to ACA has been tampered with (supply-chain compromise via ACR), the attacker's code runs within the container with access to all secrets referenced by the ACA secret store (Key Vault-sourced DB password) and with the managed identity bound to the environment. | T3 | Open |

### A — Abuse {#plumberapi-a}

| ID | Description | Tier | Status |
|---|---|---|---|
| T02.A.1 | The `/query` natural-language endpoint accepts arbitrary text and echoes parsed fields in its response. An adversary can systematically craft questions to enumerate all valid team names, player IDs, stat types, and season ranges without authentication, extracting a full schema map of the stats dataset. | T1 | Open |

---

## C06 — DBRefreshJob {#dbrefreshjob}

**Boundary**: AzureContainerApps | **Tier**: T3 | **No listener — outbound-only scheduled job**

### S — Spoofing {#dbrefreshjob-s}

| ID | Description | Tier | Status |
|---|---|---|---|
| T03.S.1 | The `superNetballR` package connects to the Champion Data API over HTTPS. There is no certificate-pinning configuration. A DNS spoofing or BGP hijack attack that redirects the Champion Data hostname to an attacker-controlled TLS endpoint (with a valid CA-signed cert for the target domain) could cause DBRefreshJob to authenticate against a malicious service. | T3 | Open |

### T — Tampering {#dbrefreshjob-t}

| ID | Description | Tier | Status |
|---|---|---|---|
| T03.T.1 | The DBRefreshJob performs a destructive schema-rebuild cycle (DROP / CREATE / INSERT) each run. If the upstream Champion Data payload is tampered (e.g., attacker-controlled champion data endpoint after T03.S.1), injected stats values persist into PostgreSQL without integrity checks. | T3 | Open |

### R — Repudiation {#dbrefreshjob-r}

| ID | Description | Tier | Status |
|---|---|---|---|
| T03.R.1 | ACA execution logs capture job start/end and stdout but there is no schema-level diff or row-change audit mechanism. If a refresh job produces unexpected database changes (e.g., tampered upstream data) there is no artefact to determine which rows changed and when. | T3 | Open |

### I — Information Disclosure {#dbrefreshjob-i}

| ID | Description | Tier | Status |
|---|---|---|---|
| T03.I.1 | The DBRefreshJob ACA job environment includes the PostgreSQL admin password (`NETBALL_STATS_DB_PASSWORD` sourced from Key Vault via secret ref) and any Champion Data credentials. A process dump, container escape, or Azure portal secret inspection by an over-privileged operator would expose admin database credentials. | T3 | Open |

### D — Denial of Service {#dbrefreshjob-d}

| ID | Description | Tier | Status |
|---|---|---|---|
| T03.D.1 | If Champion Data rate-limits or blocks `superNetballR` requests the weekly refresh job fails. With no automatic retry policy beyond a single ACA job re-run and no alerting on stale DB data, the archive remains out-of-date without operator notification. | T3 | Open |

### E — Elevation of Privilege {#dbrefreshjob-e}

| ID | Description | Tier | Status |
|---|---|---|---|
| T03.E.1 | DBRefreshJob uses the PostgreSQL admin credentials (`NETBALL_STATS_DB_USER = postgresAdminUsername`). A vulnerability in the R runtime, the `superNetballR` package, or a maliciously crafted Champion Data response that achieves code execution within the container grants the attacker full DDL/DML access to the production database. | T3 | Open |

### A — Abuse {#dbrefreshjob-a}

| ID | Description | Tier | Status |
|---|---|---|---|
| T03.A.1 | An insider with access to the ACA job configuration or the container image pipeline could modify the job command to execute additional SQL statements using the admin credentials at the next scheduled refresh, without changing any observable application behaviour. | T3 | Open |

---

## C07 — PostgreSQL {#postgresql}

**Boundary**: AzureData | **Tier**: T2 | **Listens on**: 5432 (public endpoint enabled)

### S — Spoofing {#postgresql-s}

| ID | Description | Tier | Status |
|---|---|---|---|
| T04.S.1 | PostgreSQL connections use `sslmode=require`, which mandates TLS encryption but does not verify the server hostname against the certificate CN/SAN (`sslmode=verify-full` would). An attacker positioned between the Container App and the database with a valid TLS certificate for an unrelated domain could present it without triggering a connection error. | T2 | Open |

### T — Tampering {#postgresql-t}

| ID | Description | Tier | Status |
|---|---|---|---|
| T04.T.1 | PostgreSQL `postgresPublicNetworkAccess` is set to `'Enabled'` and the `allowAzureServicesPostgresFirewallRule` is active. This permits any Azure resource from any tenant to attempt a TCP connection to port 5432, significantly broadening the network attack surface for brute-force or credential-stuffing attacks against the database. | T1 | Open |

### R — Repudiation {#postgresql-r}

| ID | Description | Tier | Status |
|---|---|---|---|
| T04.R.1 | The PostgreSQL Flexible Server Bicep module does not configure `pgaudit` or diagnostic settings that export audit logs to Log Analytics. DML statements and login events cannot be traced to specific client connections during a security investigation. | T2 | Open |

### I — Information Disclosure {#postgresql-i}

| ID | Description | Tier | Status |
|---|---|---|---|
| T04.I.1 | The combination of a publicly accessible PostgreSQL endpoint and the broad "Allow Azure Services" firewall rule means any Azure-hosted attacker (including from different tenants) can probe port 5432. Successful credential guessing or credential theft provides access to the full historical stats dataset. | T1 | Open |

### D — Denial of Service {#postgresql-d}

| ID | Description | Tier | Status |
|---|---|---|---|
| T04.D.1 | No explicit connection-limit setting for the `netballstats_api` PostgreSQL role is configured. If PlumberAPI scales to multiple replicas and each maintains a persistent connection pool, connection exhaustion could deny database access to legitimate requests; no circuit breaker is implemented. | T2 | Open |

### E — Elevation of Privilege {#postgresql-e}

| ID | Description | Tier | Status |
|---|---|---|---|
| T04.E.1 | The Bicep template provisions the API user but does not contain explicit GRANT/REVOKE statements limiting the `netballstats_api` role to SELECT-only access. If the provisioning script applies overly broad defaults, the read-only guarantee may not be enforced at the PostgreSQL permission layer. | T2 | Needs Verification |

### A — Abuse {#postgresql-a}

| ID | Description | Tier | Status |
|---|---|---|---|
| T04.A.1 | An authenticated PostgreSQL user (e.g., stolen credentials) can run arbitrary SELECT statements at full database throughput without any query-level rate limiting. The entire historical dataset could be bulk-extracted in a single session without triggering application-layer controls. | T2 | Open |

---

## C08 — KeyVault {#keyvault}

**Boundary**: AzureData | **Tier**: T2 | **Azure-managed HTTPS**

### S — Spoofing {#keyvault-s}

| ID | Description | Tier | Status |
|---|---|---|---|
| T05.S.1 | Managed identity tokens are acquired from the Azure Instance Metadata Service (IMDS) at `169.254.169.254`. An SSRF vulnerability in PlumberAPI (e.g., a crafted request that causes server-side HTTP to an attacker-specified URL resolving to IMDS) could allow the attacker to retrieve the managed identity access token and impersonate the identity when calling Key Vault. | T2 | Open |

### T — Tampering {#keyvault-t}

| ID | Description | Tier | Status |
|---|---|---|---|
| T05.T.1 | Key Vault secret values can be updated by any principal holding the `Key Vault Secrets Officer` or `Key Vault Administrator` role. Accidental RBAC over-assignment or a compromised Azure admin account could silently rotate the DB password to a value unknown to the application, causing a service outage. | T3 | Open |

### R — Repudiation {#keyvault-r}

| ID | Description | Tier | Status |
|---|---|---|---|
| T05.R.1 | Key Vault diagnostic settings are not explicitly configured in the Bicep template to export access and management logs to the Log Analytics workspace. Secret read events (by PlumberAPI and DBRefreshJob) and any secret updates are not surfaced in the application's monitoring dashboard. | T2 | Open |

### I — Information Disclosure {#keyvault-i}

| ID | Description | Tier | Status |
|---|---|---|---|
| T05.I.1 | If the managed identity access token is exfiltrated (via T05.S.1 SSRF, container escape, or log leakage), all Key Vault secrets accessible to the `userAssignedIdentity` — including the PostgreSQL admin password — can be read by the attacker within the token's validity window (~1 hour). | T2 | Open |

### D — Denial of Service {#keyvault-d}

N/A — Azure Key Vault is a platform-managed service with a published SLA; throttle limits (2,000 operations/10 s) are unlikely to be reached by this workload and are outside the application's control.

### E — Elevation of Privilege {#keyvault-e}

| ID | Description | Tier | Status |
|---|---|---|---|
| T05.E.1 | PlumberAPI and DBRefreshJob share the same `userAssignedIdentity`. This identity has `Key Vault Secrets User` access to both the read-only API password and the admin password secrets. A container compromise of PlumberAPI (lower-privilege component) therefore grants the attacker access to the admin DB password, escalating beyond the API's intended read-only posture. | T2 | Open |

### A — Abuse {#keyvault-a}

| ID | Description | Tier | Status |
|---|---|---|---|
| T05.A.1 | An insider with `Key Vault Secrets Officer` access can silently rotate secrets outside normal change-control procedures, intentionally causing service disruptions or substituting credentials with attacker-controlled values. | T3 | Open |

---

## C10 — AppInsights {#appinsights}

**Boundary**: Outside | **Tier**: T1 | **Connection string exposed in /meta response**

### S — Spoofing {#appinsights-s}

| ID | Description | Tier | Status |
|---|---|---|---|
| T06.S.1 | The App Insights connection string returned by `/meta` is sufficient to submit telemetry using the standard Application Insights ingestion API. Any third party who reads the connection string from the browser page load can send forged events that appear as legitimate user traffic in the analytics workspace. | T1 | Open |

### T — Tampering {#appinsights-t}

| ID | Description | Tier | Status |
|---|---|---|---|
| T06.T.1 | Forged telemetry events submitted via the exposed connection string can inflate page-view counts, suppress real user activity in dashboards, or trigger custom alert rules (if any are configured). Operational decisions based on the analytics workspace may be driven by attacker-injected data. | T1 | Open |

### R — Repudiation {#appinsights-r}

| ID | Description | Tier | Status |
|---|---|---|---|
| T06.R.1 | Because any party can submit telemetry using the exposed connection string there is no reliable mechanism to distinguish authentic browser events from injected events. There is no per-event signature or source-IP restriction enforced by the App Insights ingestion endpoint. | T1 | Open |

### I — Information Disclosure {#appinsights-i}

| ID | Description | Tier | Status |
|---|---|---|---|
| T06.I.1 | The telemetry-proxy handler in PlumberAPI forwards the client IP address as `ai.location.ip` (sourced from `HTTP_X_FORWARDED_FOR` or `REMOTE_ADDR`) to App Insights without anonymisation (e.g., last-octet zeroing). Full client IPs are therefore stored in the App Insights workspace, constituting personal data retention without explicit user notice. | T1 | Open |

### D — Denial of Service {#appinsights-d}

| ID | Description | Tier | Status |
|---|---|---|---|
| T06.D.1 | An adversary can flood the App Insights ingestion endpoint using the exposed connection string, exhausting the workspace's daily data volume cap. Once the cap is reached, legitimate telemetry events — including availability alerts and error traces — are dropped, blinding operators to production incidents. | T1 | Open |

### E — Elevation of Privilege {#appinsights-e}

N/A — AppInsights is a write-only telemetry sink from the application's perspective; no privilege escalation path exists via the ingestion endpoint.

---

## C09 — AzureContainerRegistry {#azurecontainerregistry}

**Boundary**: Outside | **Tier**: T2 | **ACR Basic SKU; admin disabled; public endpoint**

### S — Spoofing {#azurecontainerregistry-s}

| ID | Description | Tier | Status |
|---|---|---|---|
| T07.S.1 | Container images are referenced by mutable tag (e.g. `latest` or version tag) rather than immutable digest in the ACA container spec. An attacker with write access to the registry can update the tag to point to a different image without changing the image reference in the ACA configuration, effectively deploying malicious code on the next ACA revision. | T2 | Open |

### T — Tampering {#azurecontainerregistry-t}

| ID | Description | Tier | Status |
|---|---|---|---|
| T07.T.1 | Neither the GitHub Actions CI/CD workflow nor the `azure.yaml` post-deploy hooks sign container images (no Cosign or Notation step). ACR Basic SKU does not support content trust. A compromised push credential or pipeline token could substitute a malicious image for a legitimate one with no cryptographic detection mechanism. | T2 | Open |

### R — Repudiation {#azurecontainerregistry-r}

| ID | Description | Tier | Status |
|---|---|---|---|
| T07.R.1 | ACR diagnostic settings are not configured in the Bicep template to export registry access events to the Log Analytics workspace. Image push, pull, and delete operations by GitHub Actions or the Operator are not auditable from the application's monitoring tooling. | T2 | Open |

### I — Information Disclosure {#azurecontainerregistry-i}

| ID | Description | Tier | Status |
|---|---|---|---|
| T07.I.1 | `Dockerfile.azure` uses `COPY . /app` to copy the full repository working tree into the image. Without a verified `.dockerignore` file, build artefacts, local `.env` files, IDE config, or test fixtures may be inadvertently included in a published image layer, disclosing sensitive development-time data to anyone with pull access or image inspection tools. | T2 | Open |

### D — Denial of Service {#azurecontainerregistry-d}

N/A — ACR availability is an Azure platform concern; no application-level control over registry availability exists.

### E — Elevation of Privilege {#azurecontainerregistry-e}

| ID | Description | Tier | Status |
|---|---|---|---|
| T07.E.1 | The GitHub Actions cleanup workflow (`cleanup-registry.yml`) requires `AcrPull` and `AcrDelete` roles on the registry. Over-provisioning the federated credential (e.g., granting `Contributor` at subscription scope) would allow the GitHub Actions identity to modify broader Azure resources during a compromised workflow run. | T2 | Open |

---

## C11 — ChampionData {#championdata}

**Boundary**: Outside | **Tier**: T3 | **External API; outbound-only from DBRefreshJob**

### S — Spoofing {#championdata-s}

| ID | Description | Tier | Status |
|---|---|---|---|
| T08.S.1 | The `superNetballR` package resolves the Champion Data hostname via system DNS with no certificate pinning. A DNS poisoning or BGP hijack attack that redirects the hostname to a TLS endpoint controlled by the attacker (presenting a CA-signed cert for a different domain) could cause DBRefreshJob to pull data from a malicious source undetected. | T3 | Open |

### T — Tampering {#championdata-t}

| ID | Description | Tier | Status |
|---|---|---|---|
| T08.T.1 | Champion Data controls the content of the stats payload. If the upstream API is compromised or an adversary performs a MITM against the connection (enabled by T08.S.1), injected data values (including out-of-range stats or SQL-relevant character sequences) flow directly into the destructive schema-rebuild cycle and are persisted to PostgreSQL. | T3 | Open |

### R — Repudiation {#championdata-r}

| ID | Description | Tier | Status |
|---|---|---|---|
| T08.R.1 | No hash, signature, or content-integrity check is performed on Champion Data download payloads. Post-incident analysis cannot determine whether a given database state originated from authentic Champion Data or from a tampered download. | T3 | Open |

### I — Information Disclosure {#championdata-i}

| ID | Description | Tier | Status |
|---|---|---|---|
| T08.I.1 | If Champion Data authentication credentials are required by `superNetballR` they are likely configured as environment variables in the DBRefreshJob ACA job specification. A container escape or Azure portal secret inspection by an over-privileged operator would expose these credentials to an external third-party service. | T3 | Open |

### D — Denial of Service {#championdata-d}

| ID | Description | Tier | Status |
|---|---|---|---|
| T08.D.1 | Champion Data API downtime, rate-limiting, or intentional access revocation would cause the weekly DB refresh job to fail. The application has no alerting on stale data or automatic fall-back to a cached snapshot; stats displayed could silently become out-of-date. | T3 | Open |

### E — Elevation of Privilege {#championdata-e}

N/A — ChampionData is an outbound-only read data source; DBRefreshJob does not send privileged commands to it and cannot be directed by it to escalate privileges within the Azure environment.

### A — Abuse {#championdata-a}

| ID | Description | Tier | Status |
|---|---|---|---|
| T08.A.1 | The `superNetballR` R package is a third-party open-source dependency not under the team's control. A malicious version pushed to CRAN or the package source could execute arbitrary code within the DBRefreshJob container on the next refresh run, with access to all secrets available to that container. | T3 | Open |

---

## C12 — AzureAD {#azuread}

**Boundary**: Outside | **Tier**: T2 | **Managed identity provider; OIDC federated credentials**

### S — Spoofing {#azuread-s}

| ID | Description | Tier | Status |
|---|---|---|---|
| T09.S.1 | An SSRF vulnerability in PlumberAPI could allow an attacker to issue HTTP requests to the Azure IMDS endpoint (`169.254.169.254/metadata/identity/oauth2/token`), retrieving the managed identity access token. The token could then be used to authenticate to Key Vault as the application identity and read all secrets within the token's validity window. | T2 | Open |

### T — Tampering {#azuread-t}

| ID | Description | Tier | Status |
|---|---|---|---|
| T09.T.1 | Azure RBAC role assignments for the managed identity are managed by Azure administrators. An unauthorised or accidental role-assignment change could revoke the identity's Key Vault access (service disruption) or grant broader permissions than intended (privilege escalation beyond application boundaries). | T3 | Open |

### R — Repudiation {#azuread-r}

| ID | Description | Tier | Status |
|---|---|---|---|
| T09.R.1 | Azure AD sign-in logs capturing managed identity token acquisitions are available in the Azure portal but are not forwarded to the application's Log Analytics workspace. Anomalous token acquisition patterns (e.g., unusually high frequency or from an unexpected IP) would not trigger application-level alerts. | T2 | Open |

### I — Information Disclosure {#azuread-i}

| ID | Description | Tier | Status |
|---|---|---|---|
| T09.I.1 | Managed identity access tokens have a validity window (typically 1 hour). If a token is inadvertently captured in application logs or error traces before the SDK has a chance to redact it, it could be replayed by an attacker to authenticate as the managed identity until expiry. Log sanitisation of token values should be verified. | T2 | Needs Verification |

### D — Denial of Service {#azuread-d}

N/A — Azure AD IMDS availability is an Azure platform SLA concern outside the application's control.

### E — Elevation of Privilege {#azuread-e}

| ID | Description | Tier | Status |
|---|---|---|---|
| T09.E.1 | PlumberAPI and DBRefreshJob share a single `userAssignedIdentity`. A compromise of the lower-privilege PlumberAPI container grants the attacker the same managed identity token, providing access to the admin DB password secret in Key Vault — well beyond the read-only API's intended privilege level. (See also T05.E.1.) | T2 | Open |

### A — Abuse {#azuread-a}

| ID | Description | Tier | Status |
|---|---|---|---|
| T09.A.1 | An insider with Azure AD administrative access could add additional federated credentials or role assignments to the managed identity, enabling external systems or identities to authenticate as the application identity and access Key Vault secrets without triggering standard change-control alerts. | T3 | Open |
