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

<!-- Populated in Task 4.4. -->
