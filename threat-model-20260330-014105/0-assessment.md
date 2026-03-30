# Security Assessment — netballstats

## Report Files

| File | Description |
|---|---|
| `0-assessment.md` | This executive summary and risk rating |
| `0.1-architecture.md` | System architecture, component inventory, exposure table, security posture |
| `1-threatmodel.md` | Data flow diagram, element table, trust boundary table, flow table |
| `1.1-threatmodel.mmd` | Raw Mermaid DFD source |
| `2-stride-analysis.md` | Full STRIDE-A analysis — 54 threats across 9 components |
| `3-findings.md` | 12 security findings with CVSS, CWE, OWASP, and recommendations |
| `threat-inventory.json` | Machine-readable inventory of all components, boundaries, flows, threats, and findings |

---

## Metadata

| Field | Value |
|---|---|
| Repository | `https://github.com/craigmoyle/netballstats.git` |
| Branch | `main` |
| Commit | `294516c` |
| Commit Date | `2026-03-30 12:10:17 +1100` |
| Analysis Start | `2026-03-30 01:41:05 UTC` |
| Analysis End | `2026-03-30 01:56:57 UTC` |
| Analyst | GitHub Copilot CLI (`threat-model-analyst` skill) |
| Hostname | `Mac.lan` |
| Deployment Classification | `NETWORK_SERVICE` |

---

## Executive Summary

`netballstats` is a publicly accessible Super Netball statistics archive comprising a static
frontend on Azure Static Web Apps and a read-only R Plumber API on Azure Container Apps backed
by Azure Database for PostgreSQL.  The system has a well-defined security posture for its
primary use case — parameterised read-only SQL, allowlisted stat validation, CORS restrictions,
and non-root container execution — but carries several concrete risks arising from its fully
public exposure model and infrastructure configuration choices.

**The most significant finding (FIND-02) is that the PostgreSQL server is reachable from any
Azure resource globally**, owing to `postgresPublicNetworkAccess: 'Enabled'` combined with the
"Allow Azure Services" firewall rule.  This directly contradicts the "AzureData private
boundary" described in the architecture and meaningfully reduces the effort required for a
credential-based database attack.

**The second most operationally critical finding (FIND-01) is the public exposure of the App
Insights connection string** via the unauthenticated `/meta` endpoint.  The connection string is
the only credential required to submit forged telemetry, potentially compromising operational
dashboards and increasing Azure costs.

**FIND-03 (per-replica rate limiter) demonstrates a design gap** where the in-process rate
limit state is not shared across ACA replicas, halving the intended DoS protection at the
configured maximum scale.

---

## Overall Risk Rating

**ELEVATED**

| Tier | Count | Highest CVSS | SDL Severity Ceiling |
|---|---|---|---|
| Tier 1 (no prerequisites) | 5 | 7.3 (FIND-02) | Important |
| Tier 2 (authenticated / adjacent) | 5 | 6.7 (FIND-06) | Moderate |
| Tier 3 (host/OS access required) | 2 | 5.4 (FIND-11) | Moderate |
| **Total** | **12** | | |

Rationale: Two Important-severity findings require no authentication to reach, and the primary
data store is reachable from the public internet.  No Critical (CVSS ≥ 9.0) findings were
identified; the read-only API posture, parameterised SQL, and Key Vault secret management
constrain the worst-case impact.

---

## Priority Action Plan

### Immediate (before next production deploy)

| Priority | Finding | Action |
|---|---|---|
| 1 | FIND-02 | Enable PostgreSQL private networking; disable public endpoint |
| 2 | FIND-01 | Evaluate connection-string exposure; add App Insights workspace daily cap alert |
| 3 | FIND-03 | Pin ACA to single replica OR migrate rate-limit state to Redis |

### Near-term (next sprint)

| Priority | Finding | Action |
|---|---|---|
| 4 | FIND-05 | Anonymise client IP before forwarding to App Insights |
| 5 | FIND-07 | Create separate managed identities for PlumberAPI and DBRefreshJob |
| 6 | FIND-09 | Enable pgaudit and export PostgreSQL logs to Log Analytics |
| 7 | FIND-10 | Add ACR and Key Vault diagnostic settings to Bicep |

### Planned (backlog)

| Priority | Finding | Action |
|---|---|---|
| 8 | FIND-04 | Add SRI hashes to App Insights CDN script tags or self-host SDK |
| 9 | FIND-06 | Upgrade ACR SKU and integrate image signing into CI/CD |
| 10 | FIND-08 | Change sslmode to `verify-full` with CA bundle |
| 11 | FIND-11 | Create least-privilege DB role for DBRefreshJob |
| 12 | FIND-12 | Add `.dockerignore` to repository root |

---

## Scope and Assumptions

- Analysis is based on static source code review, Bicep infrastructure as code, GitHub Actions workflows, and `renv.lock` dependency inventory.
- Runtime configuration (actual Key Vault secret values, Champion Data credentials, Azure RBAC assignments) was not inspected.
- `scripts/build_database.R` was not available in the visible repository listing; input-validation behaviour during the schema rebuild cycle is based on architectural inference only.
- No penetration testing or dynamic analysis was performed.
- Findings reflect the state of commit `294516c` on branch `main`.

---

## References

- [STRIDE-A Analysis](2-stride-analysis.md)
- [Security Findings](3-findings.md)
- [Architecture Overview](0.1-architecture.md)
- [Threat Model DFD](1-threatmodel.md)
- [CVSS 4.0 Calculator](https://www.first.org/cvss/calculator/4.0)
- [CWE Top 25 (2024)](https://cwe.mitre.org/top25/archive/2024/2024_cwe_top25.html)
- [OWASP Top 10 (2025)](https://owasp.org/Top10/)
- [Azure PostgreSQL Private Networking](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-networking-private)
- [Azure Container Registry Content Trust](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-content-trust)
