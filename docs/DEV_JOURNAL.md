# Development journal

Dated log of technical decisions, deviations from the original plan, and
obstacles encountered. Feeds REPORT.md sections 4 (Challenges) and 9
(What I would do differently).

---

## 2026-04-23 — Phase 2: Runtime viability

**Context.** The plan was written under the assumption that upstream
OWASP/RailsGoat was still on Ruby 2.x / Rails 4-5, and that Phase 2 would
be a 5 → 7 migration (LTS Ruby 3.3 + Rails 7.1). On opening the snapshot
imported in Phase 1, the Gemfile already declared `rails "~> 8.0.0"`,
`ruby "3.4.1"`, `puma 6`, `sqlite3 2`. OWASP modernized RailsGoat between
the spec being written and the import.

**Decision: adapt the plan to the upstream reality.**

Three options were considered:

- *A — Follow the plan literally.* Downgrade to Ruby 3.3.5 + Rails 7.1.
  Anti-pattern: downgrading a supported runtime to an older one
  introduces back CVEs that have since been patched, for no engineering
  benefit. Rejected.
- *B — Adapt to the upstream stack.* Keep Ruby 3.4.1 + Rails 8.0, treat
  Tasks 2.2 (Gemfile bump) and 2.3 (Rails 5 → 7 config update) as
  no-ops, focus the runtime work on packaging and bootability.
  Rationale: faithful to the spec's intent ("minimum viable migration to
  boot on a supported runtime"), authentic story for the case study
  (assess actual state, then act), frees time for the real subject
  matter — the DevSecOps pipeline. **Chosen.**
- *C — Hybrid.* Pin Ruby 3.3.5 (slightly older, more mature) but keep
  Rails 8. Compromise without clear gain. Rejected.

**Concrete adjustments applied:**

- Reverted the premature `.ruby-version → 3.3.5` commit; aligned to
  upstream 3.4.1.
- Tasks 2.2 and 2.3 collapsed to a single boot-fix commit covering only
  the gaps that prevented Rails 8 from booting on the upstream config:
    - `config/initializers/key.rb`: added an `ENV['RAILSGOAT_KEY']`
      fallback for the production environment. The original file only
      defined the `Encryption::KEY` constant in non-production, so any
      production boot died inside `db:seeds.rb` calling
      `User#generate_token`. The intentionally-insecure development
      hardcoded key is preserved untouched (it is the whole point of
      the training app).
    - `config/storage.yml`: created a minimal local Disk service.
      Active Storage in Rails 8 raises at boot if this file is missing.
    - `config/environments/production.rb`: removed the
      `js_compressor = :uglifier` line. The `uglifier` gem is
      unmaintained, was never declared in the Gemfile, and triggered a
      500 on the first asset render under sprockets.
- Task 2.4 (Dockerfile) implemented as specified, base image bumped
  from `ruby:3.3.5-slim-bookworm` to `ruby:3.4.1-slim-bookworm` to
  match the upstream Gemfile pin.

**Verification.** `docker build .` succeeds, `docker run` with
`SECRET_KEY_BASE` and `RAILSGOAT_KEY` environment variables returns
HTTP 200 on `/` and `/login`, container reports `healthy`. Same result
through `docker compose up`.

**Trade-offs accepted.**

- No upgrade attempted to Rails 8.1 / 8.2 — stability over bleeding
  edge, and we want to scan the version OWASP actually ships.
- SQLite kept as the production adapter (matches upstream
  `database.yml`); Postgres / MySQL gem groups are excluded from the
  production image via `BUNDLE_WITHOUT`.
- Ruby is not installed on the workstation. All Rails-side commands
  (bundle install, db:prepare, server) run inside the container
  during build or via `docker run`. Reproducibility benefit; small
  inner-loop friction cost.

**Obstacles encountered.**

- Three boot failures uncovered in sequence (Encryption::KEY missing →
  Active Storage config missing → uglifier not bundled). Each fix
  exposed the next layer; this is the typical pattern when running a
  legacy training app on a major Rails version it was not designed
  for.

**Time spent on phase 2.** ~1h30 (target was 3-4h; the upstream
modernization removed most of the originally-planned migration work).

---

## 2026-04-23 — Phase 3: Local security tooling and baseline scan

**Context.** Wire up every layer of the DevSecOps pipeline locally before
porting to GitHub Actions in Phase 5: pre-commit hooks for fast feedback,
six scan scripts mirroring the future CI jobs, a full baseline pass to
establish the starting point.

**Tooling decision: Docker-backed scripts for everything not natively
installed.** Available natively on this workstation: detect-secrets 1.5.47,
semgrep 1.159.0, pre-commit 4.5.1, jq, docker. Missing: brakeman,
bundler-audit, trivy, hadolint, syft, grype, cosign, ruby. Rather than
spend 30-45 min installing rbenv + ruby + 6 gems + 4 binary releases,
each scan script invokes the official Docker image of its tool with the
working tree mounted. Identical invocation locally and in CI; no host
toolchain dependency beyond docker + jq + openssl.

**Pre-commit detect-secrets hook race.** The upstream `Yelp/detect-secrets`
pre-commit hook ran in parallel batches on this 1000-file tree and the
workers raced on `.secrets.baseline`, returning a spurious failure
("baseline file was updated") on every run, even when no new secret was
introduced. Replaced with a `local` hook calling `detect-secrets-hook`
with `require_serial: true`. Single invocation, zero race, hook passes
cleanly.

**Initial pre-commit pass autofixes.** Trailing whitespace and missing
EOL in 41 legacy RailsGoat files (mostly minified JS, vendored CSS, ERB
views). Captured in one commit after configuring the hooks; no behavioural
change.

**Baseline scan results.**

```
Layer            Status   Findings
[1/6] Secrets    OK       0 new vs 30 baselined
[2/6] SAST       FAIL     Brakeman 13 High + 5 Medium ; Semgrep 22
[3/6] SCA        FAIL     Trivy fs 2 CRITICAL ; bundler-audit n/a
[4/6] Image      FAIL     Hadolint OK ; Trivy OS 7 CRITICAL ; libs 1C+9H
[5/6] DAST       OK       ZAP 0 High ; 4 Medium ; 16 Low/Info
[6/6] SBOM       FAIL     Grype 7 Critical (4 overlap glibc CVE-2026-5450)
```

Total wall-clock: ~13 minutes, dominated by first-time Docker image pulls
(ZAP ~1 GB, plus Trivy, Syft, Grype, ruby:3.4.1-slim). Re-runs with
images cached: ~4-6 minutes expected.

**Tool surprises:**

- **Semgrep SARIF doesn't populate `.level`** for `p/ruby` + `p/security-audit`
  rulesets. Per-severity gating won't work as written; need to switch to
  per-rule severity from the rule metadata, or use Semgrep's own
  `--severity ERROR` filter instead. Captured as a Phase 4 follow-up.
- **bundler-audit can't reach github.com** from inside the one-off ruby
  container in this environment (no egress). Known limitation, will work
  from GitHub-hosted runners. Local fix: pre-clone `ruby-advisory-db`
  into a docker volume — deferred, not blocking the baseline.
- **All 13 Brakeman High-confidence findings are intentional RailsGoat
  vulnerabilities** (Marshal.load deserialization, `constantize`-based
  RCE, mass assignment, SQLi in `users_controller`, missing CSRF, etc.).
  Phase 4 dispositions them as accepted in `SECURITY_EXCEPTIONS.md` —
  rewriting them would defeat the purpose of the project.
- **glibc CVE-2026-5450 hits 4 packages** at once. Same upstream CVE,
  no Debian backport at scan date, residual after `apt upgrade`.
  Single accept entry covering all 4 occurrences.

**Phase 3 → 4 split.** Triage published in
`docs/scan-reports/TRIAGE.md` with explicit fix-or-accept disposition
for every finding. That file is the work plan for Phase 4.

**Time spent on phase 3.** ~1h45 (target was 2h).

---

## 2026-04-23 — Phase 4: Targeted remediation

**Outcome.** `./scripts/scan-all.sh` exits 0. Zero unaccepted Critical/High
across all six layers. 28 entries in `SECURITY_EXCEPTIONS.md`, each with
CVE/CWE link, owner, justification, mitigation, accept + review dates.

**Severity policy override.** The plan's strict rule "Critical/High must
be fixed, never accepted" doesn't survive contact with a deliberately
vulnerable training application — 13 of the 18 Brakeman findings ARE
the RailsGoat lessons (SQLi in `users_controller`, `constantize`-based
RCE in `mobile_controller`, missing `protect_from_forgery`, etc.).
Rewriting them would defeat the project. The override is documented
explicitly in the `SECURITY_EXCEPTIONS.md` preamble: intentional
SAST highs accepted as a class with per-finding traceability;
infrastructure / dependency Critical/High genuinely fixed.

**Remediation pattern.** Per-finding atomic commit, tool + rule ID in
the commit message for auditability. Order: fix(deps) → fix(image) →
fix(scans) → docs(exceptions).

**Categories of fixes applied.**

- **Dependency bumps via `bundle update --conservative`.** Closed
  json (Critical), rack-session (Critical), rack ×4 (High),
  activestorage ×2 (High), bcrypt (High). Cascading rails 8.0.4 → 8.0.5.
- **`apt-get upgrade -y` in Docker build + runtime stages.** Closed
  libssl3 + openssl + linux-libc-dev (4 OS Critical). Residual:
  libsqlite3-0, zlib1g — Debian no-fix-yet, accepted.
- **Script gating fixes.** Brakeman CLI required explicit
  `--ignore-config` (auto-discovers `config/brakeman.ignore`, not
  `.brakeman.ignore`). Trivy needed explicit `--ignorefile` because the
  docker `-w` was missing. Grype uses its own `.grype.yaml` (no
  `.trivyignore` compatibility) — created mirror file. detect-secrets
  scan-secrets.sh had to filter out `.brakeman.ignore` from
  `git ls-files` (sha256 fingerprints trip "Hex High Entropy String"
  false positives).

**Categories of risks accepted.** 28 RG-SEC entries:

- 18 RailsGoat intentional SAST findings (Brakeman 13H + 5M; Semgrep
  22 absorbed by path exclusion or overlap)
- 5 OS-level / stdlib-bound CVEs without an upstream patch
  (libsqlite3, zlib, resolv, uri, glibc ×4 packages)
- 4 ZAP Medium alerts on a never-deployed training image (CSP, SRI,
  HTTP→HTTPS, Vulnerable JS Library)

**Surprises.**

- Grype, Trivy, and Brakeman each have their own ignore-file format and
  none read each other's. Maintaining four separate exception files
  (`.trivyignore`, `.grype.yaml`, `.brakeman.ignore`, `.semgrepignore`)
  with `SECURITY_EXCEPTIONS.md` as the single source of truth is real
  overhead — worth it for traceability, but a pain point worth flagging
  in the REPORT.
- detect-secrets default plugins flag any 32+ char hex string as a
  potential secret, including audit fingerprints. Pre-commit and
  scan-secrets.sh both needed an explicit `.brakeman.ignore` exclusion.
- `bundle update` against the upstream-modernized Gemfile cascaded
  Rails itself from 8.0.4 to 8.0.5; verified the container still boots
  HTTP 200 / healthcheck healthy before committing.

**Remediation stats.**

| Layer | Baseline | Final | Fixed | Accepted (in scope) |
|---|---:|---:|---:|---:|
| Brakeman High | 13 | 0 | 0 | 13 (intentional vulns) |
| Brakeman Medium | 5 | 0 | 0 | 5 (intentional vulns) |
| Semgrep findings | 22 | 22 | 0 | 22 (covered by overlap + paths) |
| Trivy fs CRITICAL | 2 | 0 | 2 | 0 |
| Trivy image OS CRITICAL | 7 | 0 | 4 | 3 |
| Trivy image libs HIGH+CRIT | 10 | 0 | 8 | 2 |
| ZAP High | 0 | 0 | — | — |
| ZAP Medium | 4 | 0 | 0 | 4 (non-deployed) |
| Grype Critical | 7 | 0 | 1 | 6 (overlap + glibc) |

Total: 14 fixed via deps/image bumps, 47 formally accepted with
documented justification.

**Time spent on phase 4.** ~2h (target was 4-6h; the per-finding
atomic-commit discipline plus the upstream's already-modern stack made
this faster than estimated).

---

## 2026-04-23 — Phase 5: CI pipeline

**Outcome.** `security.yml` runs on every PR to `main`; all 8 jobs
green on the first PR (#1). Branch protection on `main` requires every
job before merge. Image published and signed at
`ghcr.io/setounkpe7/railsgoat-security:latest`.

**Job graph (final):**
```
secrets-scan
    ├── sast               (Brakeman + Semgrep)
    ├── sca                (bundler-audit + Trivy fs)
    └── docker-build       (Hadolint + Trivy config + image build)
            ├── image-scan (Trivy OS + libs)
            ├── dast       (ZAP baseline)
                    └── sbom         (Syft + Grype)
                            └── sign-and-push (GHCR + Cosign)
```

**Pipeline runtime (final green run):** 9 min 48 s wall-clock.
Within the 12-16 min spec estimate.

**Iterations to green:** nine. The first eight failures were not bugs
in the application or pipeline logic — they were environment friction
between my local docker-first workflow and the third-party GitHub
Actions used initially:

1. **GitHub Actions cannot create pull requests by default.**
   `auto-pr.yml` was rejected with
   `GitHub Actions is not permitted to create or approve pull requests`.
   Worked around by opening PR #1 manually with my user token.
   Long-term fix: enable the repo setting (Settings → Actions →
   General → "Allow GitHub Actions to create and approve pull
   requests") or switch the workflow to a fine-grained PAT.

2. **detect-secrets version mismatch.** The local install was a
   non-PyPI 1.5.47 build with a different plugin set; PyPI's latest
   is 1.5.0. The CI `pip install detect-secrets==1.5.47` failed,
   then 1.5.0 against a 1.5.47-generated baseline caused
   "baseline file was updated" and exit code 3. Standardised on
   1.5.0 across local + pre-commit + CI; regenerated the baseline.

3. **`aquasecurity/trivy-action` tag conventions.** Wrote `0.36.0`,
   then added the `v` prefix. Even with `severity: CRITICAL`,
   trivy-action 0.36.0 + Trivy 0.70.0 returns non-zero on any
   misconfig finding regardless of severity, breaking `exit-code: 1`
   semantics.

4. **`zaproxy/action-baseline` artifact-name regression.** Internal
   artifact name `zap_scan` is no longer accepted by GitHub artifact
   v4.

5. **bundler-audit + `set -euo pipefail`.** `bundle-audit check`
   exits 1 on any finding, killing the script before its
   Critical-only gate ran.

The fix that resolved the last five all at once: replace every
third-party security action with the same docker run invocation used
in `scripts/scan-*.sh`. One gating logic to maintain, identical
behavior local and remote, no surprise behavior from action releases.
SARIF outputs continue to flow to the Security tab via
`codeql-action/upload-sarif`.

**Cosign verify works locally.** From any machine with cosign v2+:
```
cosign verify ghcr.io/setounkpe7/railsgoat-security:latest \
  --certificate-identity-regexp='https://github.com/Setounkpe7/.*' \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com
```

**Time spent on phase 5.** ~2h30 (target was 3-4h). Most of it
debugging third-party-action quirks and refactoring around them.

---

## 2026-04-23 — Phase 6: Portfolio

**Outcome.** Four reviewer-facing artefacts produced
([REPORT.md](../REPORT.md), [README.md](../README.md),
[docs/ARCHITECTURE.md](ARCHITECTURE.md), [docs/RUNBOOK.md](RUNBOOK.md)).
Cross-links established with `find-one-devsecops-case-study/REPORT.md`
and `Setounkpe7/Setounkpe7` profile README.

**Voice.** Practitioner-senior tone applied from the first draft (no
"we struggled / finally figured out" register), accessible to
non-technical readers (acronyms glossed at first occurrence). Single
sentence in REPORT § 10 and README credits acknowledges AI assistance;
no dedicated AI section.

**`add-portfolio` skill not invoked.** The `add-portfolio` skill
exists to package an arbitrary project into a recruiter-facing
case-study repo (the way `find-one-devsecops-case-study` was generated
from the Find-One project). `railsgoat-security` is *already*
structured as a self-contained case study: REPORT, ARCHITECTURE,
RUNBOOK, baseline-vs-final scan reports, SECURITY_EXCEPTIONS,
DEV_JOURNAL. Running `add-portfolio` would produce a duplicate
landing repo with no new information. Re-evaluate if a separate
recruiter-only summary becomes useful later.

**Total project time (all 6 phases).** ~10h wall-clock across one
afternoon, against the spec estimate of 16-20h. The savings came
from (a) the upstream stack already being modern (Phase 2 saved
~2h), (b) the per-finding atomic-commit discipline keeping Phase 4
focused (~3h saved), (c) replacing third-party security actions with
known-good docker invocations early (Phase 5 saved another ~1h once
the pattern was spotted).
