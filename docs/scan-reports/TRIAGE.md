# Baseline triage — 2026-04-23

First full pass of `./scripts/scan-all.sh`. Drives the Phase 4 remediation
work and the contents of `SECURITY_EXCEPTIONS.md`.

**Total runtime:** ~13 min wall-clock (most of it Docker image pulls — ZAP
~1 GB, Trivy, Syft, Grype). Re-runs with images cached: ~4-6 min expected.

## Summary

| Layer | Total | Critical | High | Medium | Low / Info |
|---|---:|---:|---:|---:|---:|
| detect-secrets (vs baseline) | 0 new | — | — | — | — |
| Brakeman | 18 | — | 13 | 5 | 0 |
| Semgrep | 22 | — | — | — | — |
| bundler-audit | n/a | — | — | — | — |
| Trivy fs | 2 | 2 | — | — | — |
| Trivy image — OS | 7 | 7 | — | — | — |
| Trivy image — libs | 10 | 1 | 9 | — | — |
| Hadolint | 0 | — | — | — | — |
| Trivy config | 0 | — | — | — | — |
| ZAP baseline | 20 | — | 0 | 4 | 16 |
| Grype (on SBOM) | 353 | 7 | 83 | 125 | 132 |

> Brakeman uses `confidence` (High/Medium/Weak) not severity; mapped above
> as Critical=—, High=High, Medium=Medium.
> Semgrep SARIF from `p/ruby` + `p/security-audit` does not populate the
> `level` field on individual results, so per-severity counts are not
> reliable here. The 22 findings are listed in `semgrep.sarif`.
> bundler-audit: scan didn't complete — the one-off ruby container could
> not reach `github.com/rubysec/ruby-advisory-db.git`. Network egress
> from the container is blocked in this environment. Tracked as a known
> limitation; CI runners have direct egress and the same script will
> work there. Local fix: pre-clone the advisory DB into a mounted volume
> (deferred, not blocking).

## Reading guide

- **"Fix"** entries get an atomic remediation commit in Phase 4.
- **"Accept"** entries land in `SECURITY_EXCEPTIONS.md` with CVE/CWE,
  justification, owner, review date.
- The split is driven by the spec rule: infrastructure / dependency CVEs
  are fixed; intentionally-vulnerable application logic is accepted
  (RailsGoat is a training app — rewriting its vulnerabilities would
  defeat the whole point).

---

## SAST — Brakeman (13 High-confidence)

All in RailsGoat's intentional vulnerable business logic. **Action: accept all 13** in `SECURITY_EXCEPTIONS.md` with justification "intentional training vulnerability — see RailsGoat wiki for the lesson it teaches".

| # | Type | File:line | Action |
|---|---|---|---|
| 1 | Redirect (open redirect) | sessions_controller.rb:26 | Accept |
| 2 | Dangerous Send | dashboard_controller.rb:16 | Accept |
| 3 | Session Setting (no HttpOnly) | session_store.rb:4 | Accept |
| 4 | CSRF (no protect_from_forgery) | application_controller.rb:2 | Accept |
| 5 | Session secret committed | secret_token.rb:8 | Accept |
| 6 | RCE via `constantize` | api/v1/mobile_controller.rb:17 | Accept |
| 7 | Mass Assignment | users_controller.rb:55 | Accept |
| 8 | SQL Injection | users_controller.rb:29 | Accept |
| 9 | Insufficient email regex | user.rb:13 | Accept |
| 10 | RCE via `constantize` | api/v1/mobile_controller.rb:10 | Accept |
| 11 | File Access (path traversal) | benefit_forms_controller.rb:13 | Accept |
| 12 | XSS unescaped cookie | layouts/application.html.erb:427 | Accept |
| 13 | RCE via `constantize` | benefit_forms_controller.rb:12 | Accept |

5 Medium-confidence (Marshal.load RCE, SQL injection in analytics, XSS via JSON, Mass Assignment via permit!, Command Injection in benefits) — same disposition: accept.

## SAST — Semgrep (22 findings, top rule families)

| Rule family | Count | Action |
|---|---:|---|
| ruby weak-hashes-md5 | 6 | Accept (intentional weak hash use in RailsGoat) |
| brakeman.check-unsafe-reflection | 3 | Accept (overlaps Brakeman RCE entries) |
| brakeman.check-unscoped-find | 3 | Accept (intentional IDOR demo) |
| brakeman.check-redirect-to | 1 | Accept (overlaps Brakeman #1) |
| brakeman.check-secrets | 1 | Accept (overlaps Brakeman #5) |
| missing-csrf-protection | 1 | Accept (overlaps Brakeman #4) |
| weak-hashes-sha1 | 1 | Accept |
| bad-deserialization | 1 | Accept (overlaps Brakeman Marshal.load) |
| audit.xss.avoid-redirect | 1 | Accept |
| brakeman.check-rails-session-secret-handling | 1 | Accept |
| (4 more) | 4 | Accept |

All overlap with Brakeman or are intentional training patterns. Consolidate justification under one "RailsGoat-intentional" exception covering both tools.

## SCA — Trivy fs (2 CRITICAL)

| Package | Version | CVE | Action |
|---|---|---|---|
| json | 2.18.0 | CVE-2026-33210 (DoS / format string) | **Fix** — bump |
| rack-session | 2.1.1 | CVE-2026-39324 | **Fix** — bump |

These are transitive Rails 8 deps. Update with `bundle update json rack-session`, accept whatever cascading bumps Bundler proposes, re-scan, re-baseline.

## Container image — Trivy OS (7 CRITICAL on debian-12.x)

| Package | CVE | Action |
|---|---|---|
| libsqlite3-0 | CVE-2025-7458 | **Fix** — apt upgrade in Dockerfile, or bump base |
| libssl-dev / libssl3 / openssl | CVE-2025-15467 | **Fix** — same |
| linux-libc-dev | CVE-2026-23112 | **Fix** — same |
| zlib1g / zlib1g-dev | CVE-2023-45853 | Accept if Debian backport not available; otherwise fix |

Strategy: add an `apt-get upgrade -y` step in the build stage of the Dockerfile, then re-scan. Anything still present after upgrade gets accepted with `linked-debian-tracker-URL` justification.

## Container image — Trivy libs (1 CRITICAL + 9 HIGH)

| Package | Version | CVE | Severity | Action |
|---|---|---|---|---|
| rack-session | 2.1.1 | CVE-2026-39324 | CRITICAL | **Fix** (same as above) |
| activestorage | 8.0.4 | CVE-2026-33195 | HIGH | **Fix** — bump |
| activestorage | 8.0.4 | CVE-2026-33658 | HIGH | **Fix** |
| bcrypt | 3.1.21 | CVE-2026-33306 | HIGH | **Fix** |
| rack | 3.1.19 | CVE-2026-22860 / 34785 / 34827 / 34829 | HIGH (×4) | **Fix** |
| resolv | 0.6.0 | CVE-2025-24294 | HIGH | **Fix** |
| uri | 1.0.2 | CVE-2025-61594 | HIGH | **Fix** |

All addressed by Bundler updates. One coherent commit `fix(deps): bump Ruby gems with HIGH+ CVEs` after Phase 4 verification.

## SBOM — Grype (7 CRITICAL)

| Package | CVE | Notes |
|---|---|---|
| zlib1g-dev | CVE-2023-45853 | overlap Trivy OS |
| libsqlite3-0 | CVE-2025-7458 | overlap Trivy OS |
| libc-bin / libc-dev-bin / libc6 / libc6-dev | CVE-2026-5450 | glibc — likely no Debian patch yet |
| rack-session | GHSA-33qg-7wpp-89cq | overlap rack-session 2.1.1 |

glibc CVE-2026-5450 across 4 packages: same upstream CVE. **Action: accept** with justification "Debian security tracker shows no fixed version available for bookworm at scan date; revisit on each base-image bump".

## Container image — Hadolint (0 errors)

Dockerfile is clean at `failure-threshold: error`. Likely some Info/Warn-level
suggestions which we ignore by policy.

## DAST — ZAP baseline (4 Medium-risk, 0 High)

All Medium alerts are header / SRI / CSP related — **Action: accept** for a non-deployed training app with documented justification (no public surface, no real user data).

| Alert | Action |
|---|---|
| Content Security Policy (CSP) Header Not Set | Accept |
| HTTP to HTTPS Insecure Transition in Form Post | Accept (SSL termination is out of scope, image is local-only) |
| Sub Resource Integrity Attribute Missing | Accept |
| Vulnerable JS Library | Accept (RailsGoat ships old jquery/bootstrap intentionally) |

16 Low/Informational alerts: blanket-accept in the SECURITY_EXCEPTIONS.md ZAP entry.

---

## Phase 4 work plan derived from this triage

1. **fix(deps)** — `bundle update json rack-session activestorage bcrypt rack resolv uri`. Re-scan, re-baseline. (Closes ~12 SCA findings.)
2. **fix(image)** — Add `apt-get update && apt-get upgrade -y` in the Dockerfile build stage. Re-scan OS layer. (Closes 4-6 of the 7 OS CRITICAL.)
3. **chore(triage)** — populate `SECURITY_EXCEPTIONS.md`:
   - 13 Brakeman High + 5 Brakeman Medium + 22 Semgrep — one consolidated "intentional RailsGoat training vulnerabilities" entry, with per-finding sub-entries.
   - 1-3 residual OS CVEs — one entry per CVE, link to Debian tracker.
   - 1 glibc CVE-2026-5450 spanning 4 packages.
   - 4 ZAP Medium alerts — one entry covering the non-deployed-training-app justification.
4. **chore(baseline)** — write `.brakeman.ignore`, `.semgrepignore`, `.trivyignore` matching the accepted findings so re-runs don't fail.
5. **fix(local-tooling)** — pre-clone `ruby-advisory-db` into a docker volume so `scan-sca.sh` runs bundler-audit offline.

Each step ends with `./scripts/scan-all.sh` rerun and only the accepted findings remaining.
