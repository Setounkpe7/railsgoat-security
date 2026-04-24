# Security exceptions register

Every finding listed here is a residual risk the project owner has
**formally accepted** rather than fixed. Each entry is reviewable, dated,
and tied to an `RG-SEC-XXX` identifier.

## Severity policy

The standard rule is: **Critical and High findings must be fixed, never
accepted.** Two project-specific exceptions to this rule, documented up
front:

1. **Intentional SAST findings (Brakeman + Semgrep) on application code
   are accepted as a class.** RailsGoat is a deliberately vulnerable
   training application — its SQL injection, mass assignment, unsafe
   `constantize`, missing CSRF, weak crypto, etc. are *the lesson*.
   Fixing them would destroy the project's purpose. They are catalogued
   here individually with justification and OWASP wiki link, the
   corresponding rules are silenced via `.brakeman.ignore` and
   `.semgrepignore` / inline `# nosemgrep:` markers so the pipeline
   gates only on *new* SAST findings introduced after baseline.

2. **OS-level Critical CVEs without an upstream Debian patch** are
   accepted with a `.trivyignore` expiry tied to the next base-image
   bump. Each one links to the Debian security tracker; on every
   Dockerfile change the tracker is re-checked and the entry either
   refreshed or removed.

Dependency-level Critical/High findings (Ruby gems with CVE fixes
released) are **always fixed** by version bump, never accepted.

## Schema

Every entry MUST include:

- **ID** — `RG-SEC-XXX` (zero-padded, sequential)
- **Tool** — Brakeman / Semgrep / bundler-audit / Trivy / ZAP / Grype
- **Finding** — rule name, CVE, or CWE reference
- **Severity** — Critical / High / Medium / Low
- **Location** — `file:line` or `package@version`
- **Justification** — concrete reason for accepting
- **Mitigation** — compensating control, if any
- **Owner** — Michel-Ange Doubogan
- **Accepted date** — ISO date
- **Review date** — ISO date, default +6 months
- **Linked OWASP/CVE/tracker** — URL

---

## Entries

### Brakeman / Semgrep — RailsGoat intentional training vulnerabilities

The 13 High-confidence + 5 Medium-confidence Brakeman findings and the
22 Semgrep findings on application code are all part of RailsGoat's
training material. The corresponding fingerprints and paths are
silenced in `.brakeman.ignore`, `.semgrepignore`, and inline
`# nosemgrep:` comments. Each is catalogued below for traceability.

Common fields for RG-SEC-001 → RG-SEC-018:
- **Owner:** Michel-Ange Doubogan
- **Accepted date:** 2026-04-23
- **Review date:** 2026-10-23
- **Mitigation:** none — RailsGoat is never deployed publicly; the image
  is run only inside the CI pipeline (DAST), never reachable from the
  internet. The intentional vulnerabilities are studied, not exploited
  in production.

| ID | Tool | Finding | Sev. | Location | Justification |
|---|---|---|---|---|---|
| RG-SEC-001 | Brakeman | Marshal.load deserialization (CWE-502) | Medium | app/controllers/password_resets_controller.rb:6 | Intentional unsafe deserialization demo for OWASP A08 |
| RG-SEC-002 | Brakeman | Open redirect (CWE-601) | High | app/controllers/sessions_controller.rb:26 | Intentional open redirect demo for OWASP A01 |
| RG-SEC-003 | Brakeman | SQL injection (CWE-89) | Medium | app/models/analytics.rb:3 | Intentional string-interpolated SQL for OWASP A03 |
| RG-SEC-004 | Brakeman | Dangerous send / user-controlled method dispatch (CWE-77) | High | app/controllers/dashboard_controller.rb:16 | Intentional `send`-based RCE demo |
| RG-SEC-005 | Brakeman | Session cookie missing HttpOnly (CWE-1004) | High | config/initializers/session_store.rb:4 | Intentional weak session config demo for OWASP A05 |
| RG-SEC-006 | Brakeman | CSRF protection not enabled (CWE-352) | High | app/controllers/application_controller.rb:2 | Intentional missing `protect_from_forgery` for OWASP A01 |
| RG-SEC-007 | Brakeman | Session secret hardcoded in repo (CWE-798) | High | config/initializers/secret_token.rb:8 | Intentional secret-in-VCS demo for OWASP A07 |
| RG-SEC-008 | Brakeman | Unsafe reflection via `constantize` (CWE-470) | High | app/controllers/api/v1/mobile_controller.rb:17 | Intentional dynamic class instantiation RCE demo |
| RG-SEC-009 | Brakeman | Mass assignment dangerous key (CWE-915) | High | app/controllers/users_controller.rb:55 | Intentional mass-assignment privilege escalation demo |
| RG-SEC-010 | Brakeman | SQL injection (CWE-89) | High | app/controllers/users_controller.rb:29 | Intentional SQLi in `find_by_sql` for OWASP A03 |
| RG-SEC-011 | Brakeman | XSS via JSON HTML entities (CWE-79) | Medium | config/environments/production.rb:2 | Intentional missing `escape_html_entities_in_json` |
| RG-SEC-012 | Brakeman | Mass assignment via `permit!` (CWE-915) | Medium | app/controllers/users_controller.rb:50 | Intentional `params.permit!` demo |
| RG-SEC-013 | Brakeman | Insufficient email format validation (CWE-777) | High | app/models/user.rb:13 | Intentional weak regex demo |
| RG-SEC-014 | Brakeman | Possible command injection (CWE-77) | Medium | app/models/benefits.rb:15 | Intentional shell-out interpolation demo |
| RG-SEC-015 | Brakeman | Unsafe reflection via `constantize` (CWE-470) | High | app/controllers/api/v1/mobile_controller.rb:10 | Same as RG-SEC-008, second entrypoint |
| RG-SEC-016 | Brakeman | Path traversal in file access (CWE-22) | High | app/controllers/benefit_forms_controller.rb:13 | Intentional unsanitized path parameter |
| RG-SEC-017 | Brakeman | XSS via unescaped cookie (CWE-79) | High | app/views/layouts/application.html.erb:427 | Intentional reflected XSS via cookie |
| RG-SEC-018 | Brakeman | Unsafe reflection via `constantize` (CWE-470) | High | app/controllers/benefit_forms_controller.rb:12 | Same as RG-SEC-008, third entrypoint |
| RG-SEC-019 | Semgrep | Various Ruby/Rails security rules (22 findings) | mixed | app/, config/ | Overlap with RG-SEC-001..018; covered by `.semgrepignore` paths and the deliberately-old vendored JS libs in `app/assets/javascripts/` (jquery 1.x, bootstrap 2.x, moment.js — RailsGoat ships them on purpose) |

Reference: [OWASP RailsGoat Wiki](https://github.com/OWASP/railsgoat/wiki) — every finding above maps to a wiki tutorial.

---

### Trivy / Grype — infrastructure CVEs without an upstream patch

#### RG-SEC-020 — libsqlite3-0 (CVE-2025-7458)

- **Tool:** Trivy image (OS) + Grype (SBOM)
- **Severity:** Critical
- **Location:** `libsqlite3-0@3.40.1-2+deb12u2` (debian:bookworm)
- **Justification:** No fixed version available in Debian bookworm at scan date.
- **Mitigation:** SQLite is read by the Rails app from a local file, never exposed over the network; CVE-2025-7458 affects parsing of malformed SQL from external sources, which is not the application's threat model.
- **Owner:** Michel-Ange Doubogan
- **Accepted date:** 2026-04-23
- **Review date:** 2026-10-23 (or earlier on base-image bump)
- **Linked tracker:** https://security-tracker.debian.org/tracker/CVE-2025-7458

#### RG-SEC-021 — zlib1g / zlib1g-dev (CVE-2023-45853)

- **Tool:** Trivy image (OS) + Grype (SBOM)
- **Severity:** Critical
- **Location:** `zlib1g@1:1.2.13.dfsg-1`, `zlib1g-dev@1:1.2.13.dfsg-1` (debian:bookworm)
- **Justification:** Debian declared `<no-dsa>` (minor issue) and will not backport the fix to bookworm. The CVE is a buffer overflow in MiniZip's `zipOpenNewFileInZip4_64`, which is not used by Rails/Puma/our application.
- **Mitigation:** Application code does not call MiniZip; only Active Storage uses zlib transparently and never on attacker-controlled archive structures.
- **Owner:** Michel-Ange Doubogan
- **Accepted date:** 2026-04-23
- **Review date:** 2026-10-23 (or earlier on base-image bump)
- **Linked tracker:** https://security-tracker.debian.org/tracker/CVE-2023-45853

#### RG-SEC-022 — resolv (CVE-2025-24294)

- **Tool:** Trivy image (libs)
- **Severity:** High
- **Location:** `resolv@0.6.0` (Ruby 3.4.1 stdlib default gem)
- **Justification:** `resolv` is a Ruby stdlib default gem; its version is bound to the Ruby runtime and cannot be upgraded via `bundle update`. Will move with the next Ruby minor/patch release.
- **Mitigation:** Application does not perform DNS lookups on attacker-controlled inputs.
- **Owner:** Michel-Ange Doubogan
- **Accepted date:** 2026-04-23
- **Review date:** 2026-10-23 (or earlier on Ruby 3.4.x patch release)
- **Linked tracker:** https://github.com/advisories/GHSA-q628-fr66-cm6q

#### RG-SEC-023 — uri (CVE-2025-61594)

- **Tool:** Trivy image (libs)
- **Severity:** High
- **Location:** `uri@1.0.2` (Ruby 3.4.1 stdlib default gem)
- **Justification:** Same as RG-SEC-022 — stdlib default gem, version bound to the Ruby runtime.
- **Mitigation:** Application uses `URI.parse` only on internally-constructed URLs.
- **Owner:** Michel-Ange Doubogan
- **Accepted date:** 2026-04-23
- **Review date:** 2026-10-23 (or earlier on Ruby 3.4.x patch release)
- **Linked tracker:** https://github.com/advisories/GHSA-pj44-39h9-vmxr

#### RG-SEC-024 — glibc CVE-2026-5450 (libc6 / libc6-dev / libc-bin / libc-dev-bin)

- **Tool:** Grype (SBOM)
- **Severity:** Critical (×4 packages, same upstream CVE)
- **Location:** `libc6@2.36-9+deb12u9`, `libc6-dev@2.36-9+deb12u9`, `libc-bin@2.36-9+deb12u9`, `libc-dev-bin@2.36-9+deb12u9` (debian:bookworm)
- **Justification:** No fixed version in Debian bookworm at scan date; reported as `<not-affected>` for some configurations on the Debian tracker but Grype flags it conservatively.
- **Mitigation:** Container runs as non-root uid 1000; the affected glibc surface is not reachable from Rails request handling.
- **Owner:** Michel-Ange Doubogan
- **Accepted date:** 2026-04-23
- **Review date:** 2026-10-23 (or earlier on base-image bump)
- **Linked tracker:** https://security-tracker.debian.org/tracker/CVE-2026-5450

---

### ZAP baseline — Medium-risk alerts on a non-deployed training app

Common fields for RG-SEC-025 → RG-SEC-028:
- **Tool:** OWASP ZAP baseline
- **Severity:** Medium
- **Owner:** Michel-Ange Doubogan
- **Accepted date:** 2026-04-23
- **Review date:** 2026-10-23
- **Mitigation:** The container is never deployed publicly; ZAP runs against an ephemeral instance inside the CI pipeline. There is no real user, no real session data, and no real attacker.

| ID | Alert | Justification |
|---|---|---|
| RG-SEC-025 | Content Security Policy (CSP) Header Not Set | Adding CSP would require app-level changes that overlap with the intentional XSS demos (RG-SEC-011, RG-SEC-017); accept for the training context |
| RG-SEC-026 | HTTP to HTTPS Insecure Transition in Form Post | TLS termination is out of scope; image is local-only behind no proxy |
| RG-SEC-027 | Sub Resource Integrity Attribute Missing | Vendored JS libs (RG-SEC-019) are pinned in-repo; SRI would not add value |
| RG-SEC-028 | Vulnerable JS Library | RailsGoat ships old jquery / bootstrap / moment.js intentionally — covered by RG-SEC-019 |

The 16 Low/Informational ZAP alerts are accepted in bulk under the same justification as the four Medium entries above; they include Cookie-without-Secure, X-Content-Type-Options missing, Strict-Transport-Security missing, server header banner, etc. All would normally be fixed in production but are out of scope for an intentionally-vulnerable training image that never serves real traffic.

---

## Re-baseline procedure

To revisit the entries above on the review date or on a base-image bump:

1. Run `./scripts/scan-all.sh` and capture fresh reports.
2. For each `.trivyignore` entry: re-check the Debian / advisory tracker URL above; if a fix is now available, remove the entry and bump the package.
3. For each Brakeman/Semgrep entry: only edit if RailsGoat upstream changes the vulnerable code (rare).
4. For ZAP entries: re-evaluate if deployment posture changes (e.g. exposed publicly).
5. Update review dates on accepted-as-is entries to today + 6 months.
