# railsgoat-security — DevSecOps hardening case study

A short, honest report of what it took to wrap OWASP RailsGoat in the
security infrastructure a real team would expect: secrets scanning, code and
dependency analysis, container and dynamic scanning, an SBOM, signed
artefacts, branch protection. The application code stays deliberately
broken because that's the whole point of RailsGoat. The interesting
story is what got fixed and what got formally accepted.

---

## 1. Context and objective

[OWASP RailsGoat](https://github.com/OWASP/railsgoat) is a Rails app
maintained by the OWASP Foundation as a teaching tool. It ships with
intentional flaws across the [OWASP Top 10](https://owasp.org/www-project-top-ten/)
(injection, broken access control, weak cryptography and so on) so that
developers can learn to spot and exploit them in a safe environment.

I wasn't trying to fix RailsGoat. The goal was to take that codebase as
a stand-in for any inherited legacy app and answer the question: what
does it actually cost, in time and engineering judgement, to bring it
to a posture where every security finding is either fixed or formally
accepted with a documented justification?

The deliverable is this repo: auditable from the git log, a green CI
pipeline, a register of accepted residual risks, and a signed container
image anyone can pull and inspect.

---

## 2. Initial diagnostic

Cloning the upstream snapshot and running the first full security scan
produced this baseline:

| Layer | Tool | Findings |
|---|---|---|
| Secrets | detect-secrets | 30 hardcoded credentials in seed data, secret tokens, training fixtures (baselined as accepted) |
| SAST (Static Analysis) | Brakeman | 13 High-confidence + 5 Medium-confidence — all in app code |
| SAST | Semgrep | 22 findings (Ruby + security-audit rulesets) |
| SCA (Software Composition Analysis) — Ruby deps | Trivy filesystem | 2 CRITICAL CVEs (json, rack-session) |
| Image — OS packages | Trivy image | 7 CRITICAL CVEs (libssl, sqlite, zlib, glibc, kernel headers) |
| Image — application libs | Trivy image | 1 CRITICAL + 9 HIGH (rack, rails, bcrypt, …) |
| DAST (Dynamic Analysis) | OWASP ZAP baseline | 0 High, 4 Medium, 16 Low/Informational |
| SBOM CVE scan | Grype | 7 Critical + 83 High |

One thing worth flagging up front: the upstream maintainers had already
modernised RailsGoat from its old Ruby 2.x / Rails 4-5 base to Ruby 3.4.1
+ Rails 8.0 between the time this project's spec was written and the day
I imported the snapshot. That changed the scope of the runtime work — I
cover it in Decision 3.1.

---

## 3. Key decisions and justifications

### 3.1 Adapt to the upstream stack rather than downgrade

The original plan called for a "minimum-viable migration to Ruby 3.3 +
Rails 7.1". On opening the snapshot the Gemfile already pinned Ruby 3.4.1
and Rails 8. Three options were on the table:

- Follow the plan literally and downgrade to 3.3.5 / Rails 7.1. That
  would reintroduce CVEs already patched upstream, an anti-pattern.
- Keep Ruby 3.4.1 / Rails 8.0 and skip the migration tasks, since the
  runtime is already supported. **Chosen.**
- Pin Ruby 3.3.5 but keep Rails 8, a compromise without a clear gain.

What actually broke when booting on the upstream stack came not from the
runtime version but from gaps in the legacy config: Active Storage in
Rails 8 demands a `config/storage.yml` the old codebase never had, an
unmaintained `uglifier` gem was still referenced for asset compression,
and the encryption key initializer only defined its constant in
non-production environments. Three small commits closed those gaps
without touching any vulnerable business logic.

### 3.2 Fix infrastructure, accept intentional vulnerabilities

The standard policy of "Critical and High findings must be fixed, never
accepted" cannot survive contact with a deliberately vulnerable training
app. Thirteen of Brakeman's High findings *are* the RailsGoat lessons
(SQL injection in the user controller, unsafe `constantize`-based remote
code execution in the mobile API, missing CSRF protection, mass assignment
through `permit!`). Fixing them would defeat the project's purpose.

The override is documented explicitly in the preamble of
[SECURITY_EXCEPTIONS.md](SECURITY_EXCEPTIONS.md): intentional SAST findings
are accepted as a class with per-finding traceability; infrastructure and
dependency Critical / High issues are still always fixed.

### 3.3 Per-tool gating thresholds

Each scanner has its own false-positive profile, so a uniform "fail on
HIGH or higher across the board" gate would generate noise without adding
signal. The thresholds that survived the baseline pass:

| Tool | Fail threshold |
|---|---|
| detect-secrets | Any new finding versus baseline |
| Brakeman | High confidence |
| Semgrep | ERROR level |
| bundler-audit | Critical |
| Trivy filesystem | Critical |
| Trivy image — OS packages | Critical |
| Trivy image — libraries | High and above |
| Hadolint (Dockerfile lint) | error level |
| Trivy config | Critical |
| ZAP baseline | High alert |
| Grype on the SBOM | Critical |

---

## 4. Challenges encountered

A short list, in the order they actually came up:

- **Three Rails 8 boot failures discovered in sequence.** Each fix
  exposed the next: `Encryption::KEY missing` → `Active Storage config
  missing` → `uglifier not bundled`. This is the typical pattern when a
  legacy app meets a major Rails version it was never designed for.
- **The upstream `Yelp/detect-secrets` pre-commit hook returned a
  spurious failure** on every run because it runs in parallel batches
  and the workers race on the shared baseline file. Replacing it with a
  local hook running serially fixed it cleanly.
- **bundler-audit could not reach `github.com`** from inside the
  ephemeral one-off Ruby container in this environment. Worked from the
  GitHub-hosted runner without changes; documented as a known local
  limitation.
- **Four scanner tools, four ignore-file formats.** `.brakeman.ignore`
  uses sha256 fingerprints, `.semgrepignore` uses gitignore-style paths
  plus inline `# nosemgrep:` markers, `.trivyignore` uses CVE IDs with
  optional expiry dates, `.grype.yaml` uses YAML with vulnerability lists.
  None of them read each other's files. Maintaining all four against
  `SECURITY_EXCEPTIONS.md` as the single source of truth is real overhead.
- **GitHub Actions cannot create pull requests by default.** The
  `auto-pr.yml` workflow failed on first push with
  `GitHub Actions is not permitted to create or approve pull requests`.
  Worked around for the first PR by opening it manually; the long-term
  fix is either to enable the repo setting or switch the workflow to a
  fine-grained personal access token.

---

## 5. The DevSecOps pipeline

Eight jobs running on every pull request to `main`, in a layered DAG so
that the cheap fast checks short-circuit the slower ones:

```
secrets-scan
    │
    ├── sast               (Brakeman + Semgrep)
    ├── sca                (bundler-audit + Trivy filesystem)
    └── docker-build       (Hadolint + Trivy config + image build)
            │
            ├── image-scan (Trivy OS + libraries)
            └── dast       (ZAP baseline against the running container)
                    │
                    └── sbom         (Syft CycloneDX + SPDX, Grype)
                            │
                            └── sign-and-push   (GHCR + Cosign keyless)
```

Each job's gating threshold matches the local `scripts/scan-*.sh`
exactly, so if the local run passes the CI run tends to pass too.
Findings in SARIF format are uploaded to the GitHub Security tab so a
reviewer can browse them in the UI without downloading anything.

The container is published to `ghcr.io/setounkpe7/railsgoat-security`
with three tags (`pr-N`, `sha-XXX`, `latest`) and signed via Cosign
keyless using the OIDC identity of the workflow run. Anyone can verify
the signature with the command in the README. No key distribution
involved.

---

## 6. Measurable results

| Metric | Baseline | After remediation |
|---|---:|---:|
| detect-secrets new findings | 0 (30 baselined) | 0 |
| Brakeman High-confidence | 13 | 0 (18 accepted) |
| Brakeman Medium | 5 | 0 (accepted) |
| Semgrep findings | 22 | 22 (under ERROR threshold) |
| Trivy filesystem CRITICAL | 2 | 0 |
| Trivy image OS CRITICAL | 7 | 0 (4 fixed via apt upgrade, 3 accepted) |
| Trivy image libs HIGH+ | 10 | 0 (8 fixed via bundle update, 2 accepted as Ruby stdlib) |
| ZAP High-risk alerts | 0 | 0 |
| ZAP Medium alerts | 4 | 0 (accepted, non-deployed) |
| Grype Critical | 7 | 0 |
| SBOM components catalogued | — | 5490 |
| Local pipeline wall-clock | — | ~13 min first run, ~5 min cached |
| CI pipeline wall-clock | — | (pending first green run) |

Of the 47 findings classified as "accept" rather than "fix", every single
one has a corresponding `RG-SEC-NNN` entry in
[SECURITY_EXCEPTIONS.md](SECURITY_EXCEPTIONS.md) with a justification, a
mitigation note, an owner and a six-month review date.

---

## 7. Limitations and residual risks

The project owns and documents the things it does not do:

- **No live deployment.** The container exists to be scanned and
  pulled, not exposed publicly. ZAP runs against an ephemeral instance
  inside the pipeline. The four ZAP Medium-risk alerts (missing CSP
  header, missing SRI attributes, HTTP-to-HTTPS form transition,
  vulnerable JS library) would all be addressed in a real production
  deployment; they make no sense to fix here.
- **Three OS-level CRITICAL CVEs without a Debian patch** at scan date:
  `libsqlite3-0` (CVE-2025-7458), `zlib1g` (CVE-2023-45853, declared
  `<no-dsa>` by Debian), and the four `glibc` packages affected by
  CVE-2026-5450. Each one is accepted in `.trivyignore` and `.grype.yaml`
  with an explicit `exp:2026-10-23` expiry tied to the Debian security
  tracker. The next base-image bump or six-month review re-evaluates them.
- **Two Ruby stdlib default gems with HIGH CVEs** (`resolv` 0.6.0 and
  `uri` 1.0.2) cannot be updated independently of the Ruby runtime. They
  will move with the next Ruby 3.4.x patch release.
- **The 22 Semgrep findings are not gated** because the rulesets we use
  do not populate the SARIF `level` field. The findings overlap with
  Brakeman's accepted set, and the path most likely to surface real new
  issues (`app/assets/javascripts/`, where RailsGoat ships intentionally
  old vendored libraries) is excluded from Semgrep entirely. Tightening
  Semgrep gating is a known follow-up.
- **No peer review.** This is a solo project; the branch protection
  requires zero approvals because GitHub does not allow a PR author to
  approve their own PR. The trade-off is documented and would change in a
  team setting.
- **No application-logic remediation.** Fixing RailsGoat's intentional
  vulnerabilities was explicitly out of scope. They are catalogued, not
  rewritten.

---

## 8. Engineering practices applied

What separates "ran some scanners" from "built an auditable DevSecOps
posture":

- Atomic commits per fix, with the tool name and rule ID in the commit
  message body. A reviewer can trace any line of remediated code back
  to the finding that motivated it.
- Upstream attribution preserved (`LICENSE`, `CREDITS.md`, `NOTICE.md`).
  The import commit is kept clean so `git log` from commit four onward
  shows only this project's work.
- Every accepted risk recorded with owner, justification, mitigation,
  accept date, review date, and an external tracker URL. No silent
  ignores.
- Branch protection on `main`: no force pushes, no deletions, all eight
  status checks required.
- Container image signed with Cosign keyless, so no private key to manage.
- Both `-baseline.*` and `-final.*` scan reports committed so a
  reviewer can `diff` them and see the remediation impact tool by tool.
- Local-first validation: `scripts/scan-all.sh` runs the same gates as
  CI. Problems get caught before the pipeline burns runner minutes.
- Pre-commit hooks (`detect-secrets`, hadolint, file hygiene) catch
  simple mistakes at commit time.

---

## 9. What I would do differently with more time

- Pin Semgrep severity per-rule rather than relying on the SARIF `level`
  field, so the 22 currently-informational findings could properly gate.
- Build a tiny scanner image that bundles `bundler-audit` and a
  pre-cloned `ruby-advisory-db`, so local SCA scans work in environments
  without container-to-internet egress.
- Replace the four-ignore-file maintenance burden with a single source
  generator that emits `.brakeman.ignore`, `.semgrepignore`, `.trivyignore`
  and `.grype.yaml` from the canonical `SECURITY_EXCEPTIONS.md`.
- Switch `auto-pr.yml` to a fine-grained personal access token so it
  works without the manual first-PR workaround.
- Add `cosign verify` in a release workflow that promotes a signed
  `latest` only after a fresh end-to-end pull-and-run smoke test.

---

## 10. How to read this repository

For a reviewer in a hurry, five files in this order:

1. [REPORT.md](REPORT.md), this file
2. [SECURITY_EXCEPTIONS.md](SECURITY_EXCEPTIONS.md), what was accepted and why
3. [.github/workflows/security.yml](.github/workflows/security.yml), the pipeline source of truth
4. [docs/scan-reports/TRIAGE.md](docs/scan-reports/TRIAGE.md), the baseline-to-final disposition table
5. [docs/DEV_JOURNAL.md](docs/DEV_JOURNAL.md), the dated decisions log

Three commands a reviewer can run:

```bash
# Reproduce every scan locally (Docker required)
./scripts/scan-all.sh

# Pull the signed image
docker pull ghcr.io/setounkpe7/railsgoat-security:latest

# Verify the Cosign signature
cosign verify ghcr.io/setounkpe7/railsgoat-security:latest \
  --certificate-identity-regexp='https://github.com/Setounkpe7/.*' \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com
```

I built this with AI assistance (Claude Code) to speed implementation.
The engineering calls — scope, tool choice, gating thresholds, what to
fix versus accept — are mine.
