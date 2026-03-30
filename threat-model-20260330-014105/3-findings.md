# Security Findings — netballstats

## Findings Summary

| ID | Title | Tier | CVSS Score | SDL Severity | Effort | Status |
|---|---|---|---|---|---|---|
| [FIND-01](#find-01) | App Insights Connection String Exposed in /meta Response | T1 | 6.9 | Moderate | Low | Open |
| [FIND-02](#find-02) | PostgreSQL Public Endpoint with Overly Permissive Azure Services Firewall Rule | T1 | 7.3 | Important | Medium | Open |
| [FIND-03](#find-03) | Per-Replica In-Memory Rate Limiter Undermines DoS Protection at Scale | T1 | 7.1 | Important | Medium | Open |
| [FIND-04](#find-04) | App Insights CDN Dependencies Loaded Without Subresource Integrity | T1 | 5.3 | Moderate | Medium | Open |
| [FIND-05](#find-05) | Client IP Addresses Forwarded to App Insights Without Anonymisation | T1 | 5.3 | Moderate | Low | Open |
| [FIND-06](#find-06) | No Container Image Signing Enabling Undetected Supply Chain Substitution | T2 | 6.7 | Moderate | High | Open |
| [FIND-07](#find-07) | Shared Managed Identity Grants PlumberAPI Access to Admin DB Credentials | T2 | 6.0 | Moderate | Medium | Open |
| [FIND-08](#find-08) | PostgreSQL sslmode Configured as "require" Rather Than "verify-full" | T2 | 4.0 | Low | Low | Open |
| [FIND-09](#find-09) | PostgreSQL Audit Logging (pgaudit) Not Configured | T2 | 4.8 | Moderate | Medium | Open |
| [FIND-10](#find-10) | ACR Diagnostic Logs and Key Vault Audit Logs Not Exported to Log Analytics | T2 | 4.8 | Moderate | Low | Open |
| [FIND-11](#find-11) | DBRefreshJob Uses Admin PostgreSQL Credentials for Full Schema Rebuild | T3 | 5.4 | Moderate | Medium | Open |
| [FIND-12](#find-12) | Dockerfile Copies Full Repository Without Verified .dockerignore | T3 | 3.0 | Low | Low | Open |

---

## FIND-01 {#find-01}

**Title**: App Insights Connection String Exposed in /meta Response

**Tier**: T1 | **SDL Severity**: Moderate | **Remediation Effort**: Low

**CVSS Vector**: `CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:L/SC:N/SI:N/SA:N`
**CVSS Score**: 6.9

**CWE**: [CWE-200 — Exposure of Sensitive Information to an Unauthorised Actor](https://cwe.mitre.org/data/definitions/200.html)
**OWASP**: A02:2025 — Security Misconfiguration

**Affected Component**: PlumberAPI (`api/plumber.R` ~L820), AppInsights

**Description**

The `/meta` endpoint returns the Application Insights browser connection string as a plain JSON
field (`telemetry.connection_string`) to every unauthenticated caller.  The connection string is
the only credential required by the App Insights ingestion API.  Any person who loads the page —
or calls `/meta` directly — can obtain it and use it to submit arbitrary telemetry events to the
workspace.

**Evidence**

```
# api/plumber.R ~L820
connection_string = if (browser_telemetry_enabled())
  meta_json_scalar(browser_telemetry_connection_string()) else NULL
```

**Impact**

- Forged page-view and custom-event records pollute operational dashboards.
- Telemetry flooding can exhaust the workspace daily data cap, suppressing real monitoring events.
- Operators lose confidence in product usage metrics and availability alerts.

**Recommendation**

Evaluate whether exposing the full connection string is necessary.  Options include:
1. Use an App Insights ingestion proxy that accepts events from the browser without exposing the raw connection string (custom proxy endpoint already exists; extend it to mint short-lived SAS-like tokens if the SDK supports it).
2. Consider restricting App Insights to `DisableLocalAuth: true` and minting time-limited shared access signatures for browser ingestion, removing the permanent connection string entirely.
3. At minimum, add rate limiting on the App Insights workspace daily cap with alerts to detect flooding.

**Related Threats**: [T02.I.1](#plumberapi-i), [T06.S.1](#appinsights-s), [T06.T.1](#appinsights-t), [T06.R.1](#appinsights-r), [T06.D.1](#appinsights-d)

---

## FIND-02 {#find-02}

**Title**: PostgreSQL Public Endpoint with Overly Permissive Azure Services Firewall Rule

**Tier**: T1 | **SDL Severity**: Important | **Remediation Effort**: Medium

**CVSS Vector**: `CVSS:4.0/AV:N/AC:H/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N`
**CVSS Score**: 7.3

**CWE**: [CWE-732 — Incorrect Permission Assignment for Critical Resource](https://cwe.mitre.org/data/definitions/732.html)
**OWASP**: A01:2025 — Broken Access Control

**Affected Component**: PostgreSQL (`infra/modules/app-stack.bicep`)

**Description**

The Bicep template provisions the PostgreSQL Flexible Server with `postgresPublicNetworkAccess:
'Enabled'` and enables the `allowAzureServicesPostgresFirewallRule`.  This firewall rule
permits any resource hosted in **any** Azure subscription (not just the application's own
subscription) to establish a TCP connection to port 5432.  The private networking mode is
available in the template but disabled by default (`privatePostgresNetworkingMode: 'disabled'`).

**Evidence**

```bicep
// infra/modules/app-stack.bicep
param postgresPublicNetworkAccess string = 'Enabled'
param allowAzureServicesPostgresFirewallRule bool = true
param privatePostgresNetworkingMode string = 'disabled'
```

**Impact**

- Reduces defence-in-depth: attacker only needs valid credentials (brute-force, credential stuffing, or stolen password) to connect directly from any Azure-hosted resource.
- Exposes the database to network-level reconnaissance from outside the application's trust boundary.
- Contradicts the intended "AzureData" private boundary described in the architecture.

**Recommendation**

1. Enable private networking: set `privatePostgresNetworkingMode` to a VNet-integrated mode.
2. Set `postgresPublicNetworkAccess: 'Disabled'` once private networking is configured.
3. Replace the broad Azure Services firewall rule with an explicit IP rule or VNet service endpoint covering only the ACA subnet.

**Related Threats**: [T04.T.1](#postgresql-t), [T04.I.1](#postgresql-i)

---

## FIND-03 {#find-03}

**Title**: Per-Replica In-Memory Rate Limiter Undermines DoS Protection at Scale

**Tier**: T1 | **SDL Severity**: Important | **Remediation Effort**: Medium

**CVSS Vector**: `CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:N/VI:N/VA:H/SC:N/SI:N/SA:N`
**CVSS Score**: 7.1

**CWE**: [CWE-770 — Allocation of Resources Without Limits or Throttling](https://cwe.mitre.org/data/definitions/770.html)
**OWASP**: A10:2025 — Security Logging and Monitoring Failures

**Affected Component**: PlumberAPI (`api/plumber.R` ~L58, `infra/modules/app-stack.bicep`)

**Description**

The rate-limiter stores per-IP request counts in an in-process R environment
(`new.env(parent=emptyenv())`).  Each Container App replica has independent, non-shared memory.
The ACA template sets `maxReplicas: 2`.  As a result an attacker's effective rate budget is
`configured_limit × replica_count`.  With the default 60 req/60 s limit and two replicas the
true cap is 120 req/60 s.  Additionally, a high-cardinality scan using many source IPs causes
unbounded growth of the rate-limiter environment between 10-minute prune cycles, consuming
container memory.

**Evidence**

```r
# api/plumber.R ~L58
rate_limit_env <- new.env(parent = emptyenv())
```

```bicep
// infra/modules/app-stack.bicep
maxReplicas: 2
```

**Impact**

- Doubles the volume of requests any single IP can send before being throttled.
- Memory exhaustion from many-IP scans can degrade API response times for legitimate users.
- Rate-limit bypass enables brute-force enumeration and sustained scraping.

**Recommendation**

1. Move rate-limit state to a shared external store (Azure Cache for Redis or a PostgreSQL counter table with TTL).
2. As an interim measure, set `minReplicas: 1` and `maxReplicas: 1` if redundancy is not required, ensuring a single rate-limit namespace.
3. Add a cap on the size of the in-process rate-limiter cache to prevent memory exhaustion.

**Related Threats**: [T02.T.1](#plumberapi-t), [T02.D.1](#plumberapi-d)

---

## FIND-04 {#find-04}

**Title**: App Insights CDN Dependencies Loaded Without Subresource Integrity

**Tier**: T1 | **SDL Severity**: Moderate | **Remediation Effort**: Medium

**CVSS Vector**: `CVSS:4.0/AV:N/AC:H/AT:N/PR:N/UI:A/VC:N/VI:H/VA:N/SC:H/SI:N/SA:N`
**CVSS Score**: 5.3

**CWE**: [CWE-829 — Inclusion of Functionality from Untrusted Control Sphere](https://cwe.mitre.org/data/definitions/829.html)
**OWASP**: A03:2025 — Injection

**Affected Component**: SWAFrontend (`staticwebapp.config.json`)

**Description**

The Content Security Policy `script-src` directive allows scripts from four App Insights CDN
hostnames (`js.monitor.azure.com`, `js.cdn.applicationinsights.io`,
`js0.cdn.applicationinsights.io`, `js2.cdn.applicationinsights.io`) without Subresource
Integrity (SRI) hashes.  A compromise of any of those CDN endpoints would allow malicious
JavaScript to be served to every user who loads the site, without violating the CSP.

**Evidence**

```json
// staticwebapp.config.json
"script-src 'self' https://js.monitor.azure.com https://js.cdn.applicationinsights.io
  https://js0.cdn.applicationinsights.io https://js2.cdn.applicationinsights.io"
```

**Impact**

- Compromised CDN script executes in the context of the SWA page — access to DOM, localStorage, and any form data entered by users.
- XSS payload delivered to all active users simultaneously without any per-user interaction required beyond page load.

**Recommendation**

1. Add SRI `integrity` attributes (`sha384-...`) to all App Insights `<script>` tags loaded from CDN hostnames.
2. Pin the CSP `script-src` to `'strict-dynamic'` with nonces for dynamically inserted scripts, removing broad CDN host entries.
3. Alternatively, self-host the App Insights browser SDK from the `dist/` build, eliminating the external CDN dependency.

**Related Threats**: [T01.T.1](#swafrontend-t)

---

## FIND-05 {#find-05}

**Title**: Client IP Addresses Forwarded to App Insights Without Anonymisation

**Tier**: T1 | **SDL Severity**: Moderate | **Remediation Effort**: Low

**CVSS Vector**: `CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:N/VA:N/SC:N/SI:N/SA:N`
**CVSS Score**: 5.3

**CWE**: [CWE-359 — Exposure of Private Personal Information to an Unauthorised Actor](https://cwe.mitre.org/data/definitions/359.html)
**OWASP**: A02:2025 — Security Misconfiguration

**Affected Component**: PlumberAPI (`api/plumber.R` — `build_telemetry_envelope()`)

**Description**

The telemetry-proxy function constructs the App Insights envelope with the field
`"ai.location.ip" = client_ip`, where `client_ip` is sourced directly from
`HTTP_X_FORWARDED_FOR` or `REMOTE_ADDR`.  The full IPv4/IPv6 address is stored in the App
Insights workspace without any anonymisation (e.g., zeroing the last octet).  This constitutes
storage of personal data that may be subject to GDPR or the Australian Privacy Act without
explicit user notice or consent.

**Impact**

- Full user IP addresses stored in a third-party analytics platform without user awareness.
- Potential compliance exposure (GDPR Article 5, Australian Privacy Act APP 3) if users are in covered jurisdictions.

**Recommendation**

1. Anonymise the IP before forwarding: zero the last octet of IPv4 addresses and the last 80 bits of IPv6 addresses.
2. Alternatively, omit the `ai.location.ip` field entirely; App Insights will still record approximate geo-location from the server-side request.
3. Update the privacy disclosure to reflect IP data collection if full IPs are retained by design.

**Related Threats**: [T06.I.1](#appinsights-i)

---

## FIND-06 {#find-06}

**Title**: No Container Image Signing Enabling Undetected Supply Chain Substitution

**Tier**: T2 | **SDL Severity**: Moderate | **Remediation Effort**: High

**CVSS Vector**: `CVSS:4.0/AV:N/AC:H/AT:N/PR:L/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N`
**CVSS Score**: 6.7

**CWE**: [CWE-494 — Download of Code Without Integrity Check](https://cwe.mitre.org/data/definitions/494.html)
**OWASP**: A03:2025 — Injection

**Affected Component**: AzureContainerRegistry, GitHubActions (`.github/workflows/`, `azure.yaml`)

**Description**

The CI/CD pipeline does not sign container images after build (no Cosign, Notation, or Docker
Content Trust step).  The ACR Basic SKU does not support content trust.  Container images are
referenced by mutable tags in the ACA configuration.  An attacker who compromises the GitHub
Actions OIDC token or the ACR push credential can substitute a malicious image; ACA will pull
and deploy the replacement on the next revision without any cryptographic alert.

**Impact**

- Silent deployment of attacker-controlled code to the production API and DB refresh jobs.
- Attacker gains access to Key Vault secrets and PostgreSQL admin credentials at next container start.

**Recommendation**

1. Upgrade ACR to Standard or Premium SKU to enable OCI artifact signing.
2. Integrate Cosign or Notation into the GitHub Actions build workflow to sign images after push.
3. Configure ACA to reference images by immutable digest rather than tag.
4. Add a Trivy or Grype container vulnerability scan step to the CI pipeline to detect known CVEs before promotion.

**Related Threats**: [T07.T.1](#azurecontainerregistry-t), [T07.S.1](#azurecontainerregistry-s)

---

## FIND-07 {#find-07}

**Title**: Shared Managed Identity Grants PlumberAPI Access to Admin DB Credentials

**Tier**: T2 | **SDL Severity**: Moderate | **Remediation Effort**: Medium

**CVSS Vector**: `CVSS:4.0/AV:N/AC:H/AT:P/PR:L/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N`
**CVSS Score**: 6.0

**CWE**: [CWE-250 — Execution with Unnecessary Privileges](https://cwe.mitre.org/data/definitions/250.html)
**OWASP**: A01:2025 — Broken Access Control

**Affected Component**: PlumberAPI, DBRefreshJob, KeyVault (`infra/modules/app-stack.bicep`)

**Description**

PlumberAPI and DBRefreshJob are assigned the same `userAssignedIdentity`.  This identity holds
`Key Vault Secrets User` access to both the read-only API DB password secret and the admin DB
password secret.  A container compromise of PlumberAPI (which has no write access to
PostgreSQL) therefore provides the attacker with the admin DB password and with the same managed
identity token used by the job that performs destructive schema rebuilds.

**Impact**

- Violates the principle of least privilege: PlumberAPI's compromise should be limited to read-only data access.
- Attacker escalates from read-only API access to full DDL control over the database.

**Recommendation**

1. Create a dedicated managed identity for DBRefreshJob, separate from the PlumberAPI identity.
2. Grant the PlumberAPI identity `Key Vault Secrets User` access **only** to the read-only DB password secret.
3. Grant the DBRefreshJob identity `Key Vault Secrets User` access **only** to the admin DB password secret.

**Related Threats**: [T05.E.1](#keyvault-e), [T09.E.1](#azuread-e)

---

## FIND-08 {#find-08}

**Title**: PostgreSQL sslmode Configured as "require" Rather Than "verify-full"

**Tier**: T2 | **SDL Severity**: Low | **Remediation Effort**: Low

**CVSS Vector**: `CVSS:4.0/AV:A/AC:H/AT:P/PR:N/UI:N/VC:H/VI:H/VA:N/SC:N/SI:N/SA:N`
**CVSS Score**: 4.0

**CWE**: [CWE-295 — Improper Certificate Validation](https://cwe.mitre.org/data/definitions/295.html)
**OWASP**: A02:2025 — Security Misconfiguration

**Affected Component**: PlumberAPI, DBRefreshJob (`R/database.R` ~L65, `infra/modules/app-stack.bicep` ~L514, ~L622)

**Description**

All database connections specify `sslmode=require`, which enforces TLS encryption of the
connection but does not verify the server's hostname against the certificate CN or SAN
(`sslmode=verify-full` would).  An attacker with a valid TLS certificate for any domain
positioned between a container and the database could terminate the TLS session without
triggering a connection error.

**Evidence**

```r
# R/database.R ~L65
sslmode = Sys.getenv("NETBALL_STATS_DB_SSLMODE", "require")
```

**Recommendation**

1. Change `sslmode` to `verify-full` in all connection configurations.
2. Set `sslrootcert` to the Azure DigiCert root CA bundle to enable full server certificate validation.
3. Add `NETBALL_STATS_DB_SSLMODE=verify-full` as a required environment variable in the ACA container spec.

**Related Threats**: [T04.S.1](#postgresql-s)

---

## FIND-09 {#find-09}

**Title**: PostgreSQL Audit Logging (pgaudit) Not Configured

**Tier**: T2 | **SDL Severity**: Moderate | **Remediation Effort**: Medium

**CVSS Vector**: `CVSS:4.0/AV:N/AC:L/AT:N/PR:L/UI:N/VC:N/VI:L/VA:N/SC:N/SI:N/SA:N`
**CVSS Score**: 4.8

**CWE**: [CWE-778 — Insufficient Logging](https://cwe.mitre.org/data/definitions/778.html)
**OWASP**: A09:2025 — Security Logging and Monitoring Failures

**Affected Component**: PostgreSQL (`infra/modules/app-stack.bicep`)

**Description**

The Bicep template does not configure `pgaudit` server parameters or PostgreSQL diagnostic
settings to export audit logs to the Log Analytics workspace.  DML operations, DDL changes
performed by DBRefreshJob, and login events from both application users are not captured in an
auditable, queryable format.  Incident response or compliance queries cannot reconstruct which
queries were executed and by whom.

**Recommendation**

1. Enable `pgaudit` on the Flexible Server: set `pgaudit.log = 'ddl,mod,role'` via Bicep server parameters.
2. Configure PostgreSQL diagnostic settings to export `PostgreSQLLogs` to the Log Analytics workspace.
3. Set log retention aligned to the organisation's compliance policy (minimum 90 days recommended).

**Related Threats**: [T04.R.1](#postgresql-r), [T04.A.1](#postgresql-a)

---

## FIND-10 {#find-10}

**Title**: ACR Diagnostic Logs and Key Vault Audit Logs Not Exported to Log Analytics

**Tier**: T2 | **SDL Severity**: Moderate | **Remediation Effort**: Low

**CVSS Vector**: `CVSS:4.0/AV:N/AC:L/AT:N/PR:L/UI:N/VC:N/VI:L/VA:N/SC:N/SI:N/SA:N`
**CVSS Score**: 4.8

**CWE**: [CWE-778 — Insufficient Logging](https://cwe.mitre.org/data/definitions/778.html)
**OWASP**: A09:2025 — Security Logging and Monitoring Failures

**Affected Component**: AzureContainerRegistry, KeyVault (`infra/modules/app-stack.bicep`)

**Description**

Neither the ACR nor the Key Vault Bicep modules configure diagnostic settings to forward audit
events to the shared Log Analytics workspace.  Image push, pull, and delete events in ACR and
secret read/write events in Key Vault are not available via the application's monitoring tooling.
These logs are essential for supply-chain incident response and secret-access anomaly detection.

**Recommendation**

1. Add `Microsoft.Insights/diagnosticSettings` Bicep resources for the ACR resource exporting `ContainerRegistryLoginEvents` and `ContainerRegistryRepositoryEvents`.
2. Add `Microsoft.Insights/diagnosticSettings` for the Key Vault resource exporting `AuditEvent` and `AllMetrics`.
3. Route both to the existing Log Analytics workspace defined in `infra/modules/app-stack.bicep`.

**Related Threats**: [T07.R.1](#azurecontainerregistry-r), [T05.R.1](#keyvault-r)

---

## FIND-11 {#find-11}

**Title**: DBRefreshJob Uses Admin PostgreSQL Credentials for Full Schema Rebuild

**Tier**: T3 | **SDL Severity**: Moderate | **Remediation Effort**: Medium

**CVSS Vector**: `CVSS:4.0/AV:N/AC:H/AT:P/PR:H/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N`
**CVSS Score**: 5.4

**CWE**: [CWE-250 — Execution with Unnecessary Privileges](https://cwe.mitre.org/data/definitions/250.html)
**OWASP**: A01:2025 — Broken Access Control

**Affected Component**: DBRefreshJob (`infra/modules/app-stack.bicep`)

**Description**

The DBRefreshJob ACA job uses `NETBALL_STATS_DB_USER = postgresAdminUsername` — the
full-administrator account — for its weekly schema-rebuild cycle.  While the destructive
DROP/CREATE pattern requires DDL rights, using the administrator account grants far broader
access (e.g., user management, extension control, pg_read_all_data) than the job requires.
A compromise of the DBRefreshJob container therefore provides an attacker with full
administrative control of the PostgreSQL server.

**Recommendation**

1. Create a dedicated `netballstats_refresh` PostgreSQL role with only the minimum required rights: ownership of the target schema (for DROP/CREATE) and INSERT/UPDATE/DELETE on target tables.
2. Revoke `pg_read_all_data`, `pg_write_all_data`, and `pg_database_owner` from the refresh role.
3. Rotate the admin password to a value not stored in the application's Key Vault after the refresh role is in place.

**Related Threats**: [T03.E.1](#dbrefreshjob-e), [T03.I.1](#dbrefreshjob-i)

---

## FIND-12 {#find-12}

**Title**: Dockerfile Copies Full Repository Without Verified .dockerignore

**Tier**: T3 | **SDL Severity**: Low | **Remediation Effort**: Low

**CVSS Vector**: `CVSS:4.0/AV:N/AC:H/AT:N/PR:L/UI:N/VC:L/VI:N/VA:N/SC:N/SI:N/SA:N`
**CVSS Score**: 3.0

**CWE**: [CWE-538 — File and Directory Information Exposure](https://cwe.mitre.org/data/definitions/538.html)
**OWASP**: A02:2025 — Security Misconfiguration

**Affected Component**: AzureContainerRegistry (`Dockerfile.azure`)

**Description**

`Dockerfile.azure` uses `COPY . /app` without a verified `.dockerignore` file in the repository.
No `.dockerignore` was found in the directory listing.  Build artefacts, local `.env` files,
editor config, test fixtures, or Git metadata may be included in published image layers,
disclosing development-environment data to anyone with image pull access or `docker inspect`
capability.

**Evidence**

```dockerfile
# Dockerfile.azure
COPY . /app
```

**Recommendation**

1. Create a `.dockerignore` file at the repository root excluding at minimum: `.git/`, `dist/`, `.env`, `*.Rmd`, `threat-model-*/`, `node_modules/`, local config files.
2. Run `docker history` or a layer-inspection tool against a locally built image to verify no sensitive files are present before pushing.

**Related Threats**: [T07.I.1](#azurecontainerregistry-i)

---

## Threat Coverage Verification

| Finding | STRIDE Category | Component | Threat IDs Covered |
|---|---|---|---|
| FIND-01 | Information Disclosure, Denial of Service | PlumberAPI, AppInsights | T02.I.1, T06.S.1, T06.T.1, T06.R.1, T06.D.1 |
| FIND-02 | Tampering, Information Disclosure | PostgreSQL | T04.T.1, T04.I.1 |
| FIND-03 | Tampering, Denial of Service | PlumberAPI | T02.T.1, T02.D.1 |
| FIND-04 | Tampering | SWAFrontend | T01.T.1 |
| FIND-05 | Information Disclosure | AppInsights | T06.I.1 |
| FIND-06 | Tampering, Spoofing | AzureContainerRegistry | T07.T.1, T07.S.1 |
| FIND-07 | Elevation of Privilege | KeyVault, AzureAD | T05.E.1, T09.E.1 |
| FIND-08 | Spoofing | PostgreSQL | T04.S.1 |
| FIND-09 | Repudiation, Abuse | PostgreSQL | T04.R.1, T04.A.1 |
| FIND-10 | Repudiation | AzureContainerRegistry, KeyVault | T07.R.1, T05.R.1 |
| FIND-11 | Elevation of Privilege, Information Disclosure | DBRefreshJob | T03.E.1, T03.I.1 |
| FIND-12 | Information Disclosure | AzureContainerRegistry | T07.I.1 |
