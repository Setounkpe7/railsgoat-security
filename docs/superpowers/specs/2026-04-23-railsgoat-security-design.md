# railsgoat-security — DevSecOps hardening design

**Status:** approved
**Owner:** Michel-Ange Doubogan
**Date:** 2026-04-23
**Target repo:** `github.com/Setounkpe7/railsgoat-security`
**Local workspace:** `/home/mdoub/Github/railsgoat-security/`

---

## 1. Context

[OWASP RailsGoat](https://github.com/owasp/railsgoat) is a deliberately vulnerable Ruby on Rails training application, MIT-licensed, maintained by the OWASP Foundation. It is frozen on Ruby 2.x / Rails 4-5 (both end-of-life) and ships with dozens of intentional vulnerabilities across all OWASP Top 10 categories.

This project takes a snapshot of RailsGoat and applies a full DevSecOps lifecycle to it: secrets scanning, SAST, SCA, DAST, SBOM generation, container signing, branch protection, pre-commit hooks, and auto-PR workflow — with targeted remediation of the critical/high findings and documented risk acceptance of the residual medium/low findings.

The deliverable is a portfolio case study demonstrating the ability to inherit a known-vulnerable legacy application and bring it to a controlled security posture in which every finding is either fixed or formally accepted.

## 2. Goals and non-goals

### Goals

- Produce a reproducible DevSecOps pipeline on GitHub Actions with eight distinct security layers
- Fix every critical/high finding across secrets, SAST, SCA, and DAST
- Document every residual medium/low finding in `SECURITY_EXCEPTIONS.md` with CVE/CWE, justification, owner, and review date
- Publish a signed container image on GitHub Container Registry (GHCR)
- Generate a CycloneDX SBOM as a committed artifact and CI output
- Enforce branch protection on `main` with required status checks
- Produce a recruiter-facing `REPORT.md` that tells the engineering story (challenges, decisions, limitations) rather than listing tools
- Cross-link with the existing `find-one-devsecops-case-study` and update the `Setounkpe7/Setounkpe7` profile README

### Non-goals (YAGNI)

- No live deployment to Fly.io, Vercel, AWS, or any hosting platform
- No Terraform or IaC for cloud infrastructure
- No runtime observability (Prometheus, Grafana)
- No OPA/conftest policies on Kubernetes manifests
- No full rewrite of the Rails application — migration is the **minimum** required for a supported Ruby runtime
- No remediation of medium/low findings — they are documented, not fixed
- No peer code review (solo project, documented as a limitation)

## 3. Key decisions and rationale

### 3.1 Remediation scope: B — detect all, fix critical/high, accept medium/low

Alternatives considered:
- **A. Full remediation** (fix everything, upgrade Ruby/Rails to latest): 1-3 days of Ruby migration work plus full logic rewrite of vulnerable code. High effort, low authenticity — real teams rarely rewrite inherited legacy.
- **C. Detection only** (let the pipeline fail, reports are the deliverable): contradicts the explicit requirement that the code must run before reaching main.

**Chosen: B.** Matches real-world engineering where residual risk acceptance is itself a professional artifact. `SECURITY_EXCEPTIONS.md` becomes a first-class deliverable.

### 3.2 Runtime migration: minimum viable to boot on a supported Ruby

Ruby 2.x is out of support and fails on recent GitHub runners. The minimum viable migration is:

- Ruby 3.3.x, Rails 7.1.x
- Gemfile and Gemfile.lock re-resolved against Rails 7 compatibility
- Rails-specific config updates required by 5 → 7 (`config/credentials`, `strong_parameters`, asset pipeline, route syntax)
- No change to vulnerable business logic (that is the point of RailsGoat)

If Rails 7.1 turns out to require too much application logic rewrite to even boot, fallback to Rails 6.1 (EOL but still scannable) is accepted and documented.

### 3.3 Deployment target: A — GHCR image only, no live hosting

Alternatives considered:
- **B. Fly.io** with Cloudflare Access: exposing a known-vulnerable app publicly carries reputational and operational risk not justified by portfolio value
- **C. AWS/GCP with IaC**: scope creep, real cost risk

**Chosen: A.** Image on `ghcr.io/setounkpe7/railsgoat-security`, signed with Cosign keyless OIDC, pullable and runnable by any reviewer. DAST runs in the pipeline against an ephemeral container in the runner.

### 3.4 Starting point: B — snapshot in new repo with formal attribution

Alternatives considered:
- **A. Fork**: pollutes commit history with OWASP contributors' commits, obscuring my own work
- **C. Fork + squash**: middle ground, but confusing for readers

**Chosen: B.** Fresh repo with a baseline commit `chore: import OWASP/railsgoat snapshot`, followed by `CREDITS.md`/`NOTICE.md`/`LICENSE` attribution commit, then all subsequent commits are my work. Clean `git log --since=<commit-3>` output for reviewers.

### 3.5 Gating policy: D — per-tool severity thresholds

Alternatives considered:
- **A. Strict, uniform** (fail on all HIGH+): simpler, but generates noise on transitive CVEs
- **B. Pragmatic** (fail on CRITICAL only): too loose for a DevSecOps portfolio

**Chosen: D.** Each tool has its own threshold calibrated to its false-positive profile:

| Tool | Fail threshold |
|---|---|
| detect-secrets | Any new finding |
| Brakeman | High+ |
| Semgrep | ERROR (= High+) |
| bundler-audit | Critical |
| Trivy fs | Critical |
| Trivy image (OS packages) | Critical |
| Trivy image (application libs) | High+ |
| Hadolint | Error level |
| Trivy config | Critical |
| ZAP baseline | High alert |
| Grype (on SBOM) | Critical |

### 3.6 Branch protection: pragmatic solo

`main` is protected, all status checks required, force-push and deletion forbidden, **0 approvals required**. Solo project constraint: GitHub does not allow a PR author to approve their own PR, so requiring 1 approval would block the author. This trade-off is documented in `REPORT.md`.

### 3.7 AI assistance: mentioned as a detail

This project was built with AI assistance (Claude Code) to speed implementation. The engineering decisions — scope, tooling, gating thresholds, risk acceptance — are the author's. A single sentence in the project README and profile README acknowledges this honestly. No dedicated section, no callout, no attribution tracking.

## 4. Architecture

### 4.1 Repository structure

```
railsgoat-security/
├── .github/workflows/
│   ├── security.yml              # DevSecOps pipeline on PR → main
│   └── auto-pr.yml               # auto-PR dev → main on push to dev
├── .secrets.baseline             # detect-secrets baseline (committed)
├── .pre-commit-config.yaml
├── .brakeman.ignore
├── .semgrepignore
├── .trivyignore
├── .hadolint.yaml
├── .dockerignore
├── .gitignore
├── Dockerfile                    # multi-stage, non-root
├── docker-compose.yml            # local dev
├── Gemfile / Gemfile.lock
├── LICENSE                       # MIT, intact
├── CREDITS.md                    # OWASP attribution
├── NOTICE.md                     # legal notice
├── SECURITY_EXCEPTIONS.md        # accepted risks register
├── README.md
├── REPORT.md                     # portfolio case study (10 sections)
├── docs/
│   ├── DEV_JOURNAL.md            # dated technical decisions
│   ├── ARCHITECTURE.md           # pipeline diagram + PR flow
│   ├── RUNBOOK.md                # reproduction guide
│   └── scan-reports/             # committed scan outputs
│       ├── README.md
│       ├── brakeman-baseline.html
│       ├── brakeman-final.html
│       ├── semgrep-baseline.sarif
│       ├── semgrep-final.sarif
│       ├── bundler-audit-baseline.txt
│       ├── bundler-audit-final.txt
│       ├── trivy-fs-final.json
│       ├── trivy-image-final.json
│       ├── zap-baseline-final.html
│       ├── sbom.cdx.json
│       └── grype-final.json
├── scripts/
│   ├── scan-all.sh               # full local pipeline
│   ├── scan-secrets.sh
│   ├── scan-sast.sh
│   ├── scan-sca.sh
│   ├── scan-image.sh
│   ├── scan-dast.sh
│   ├── generate-sbom.sh
│   └── setup-branch-protection.sh
└── app/ config/ db/ lib/ public/ spec/  # Rails codebase (remediated)
```

### 4.2 Branch strategy

- `main` — protected, merge via PR only, all status checks required, 0 approvals, force-push/deletion forbidden
- `dev` — working branch, direct push allowed, source of auto-PRs to main

No feature branches. Solo project, documented in REPORT.md as a trade-off.

### 4.3 CI pipeline graph (`security.yml`)

```
secrets-scan
    ↓
    ├── sast (Brakeman + Semgrep)      ─┐
    ├── sca (bundler-audit + Trivy fs) ─┤
    └── docker-build                   ─┤
          ├── image-scan (Trivy image)  ├→ sbom (Syft + Grype)
          └── dast (ZAP baseline)      ─┘        ↓
                                             sign-and-push
                                             (Cosign + GHCR)
```

Triggers: `pull_request` to `main`, plus `workflow_dispatch`.
Concurrency: `security-${ref}`, cancel in progress.
Permissions: `contents: read`, `packages: write`, `id-token: write`, `security-events: write`, `pull-requests: write`.
Estimated runtime: 12-16 minutes.

### 4.4 Auto-PR workflow (`auto-pr.yml`)

Trigger: `push` to `dev`. Uses `peter-evans/create-pull-request@v6` to create or update a PR `dev → main` with commits summary in the body. ~20 lines of YAML.

### 4.5 Local developer workflow

Pre-commit hooks (fast, <5s total): detect-secrets, hadolint, bundler-audit on Gemfile.lock changes, YAML/JSON validators, whitespace fixers.

Full local pipeline reproduced by `scripts/scan-all.sh` (5-10 minutes): secrets, SAST, SCA, docker build + lint, image scan, DAST, SBOM. Same flags as CI — green locally guarantees green in CI.

Monitoring after push: `gh run watch --exit-status`, debug via `gh run view --log-failed`. Loop until green.

## 5. Tool stack

| Layer | Tool | Notes |
|---|---|---|
| Secrets | detect-secrets (Yelp) | Baseline committed, pre-commit hook, CI job |
| SAST (Rails-aware) | Brakeman | Ruby-native, CWE-tagged findings, SARIF output |
| SAST (general) | Semgrep | OSS, Ruby + OWASP rulesets, SARIF output |
| SCA (Ruby deps) | bundler-audit | ruby-advisory-db, fast |
| SCA (filesystem) | Trivy fs | Multi-ecosystem, Dockerfile + deps |
| SCA (image) | Trivy image | OS packages + application libs |
| DAST | OWASP ZAP baseline action | Passive scan against container |
| SBOM | Syft (CycloneDX) | Industry standard format |
| CVE on SBOM | Grype | Complementary to Trivy |
| Dockerfile lint | Hadolint | Best-practices enforcement |
| Docker config | Trivy config | Misconfiguration scan |
| Image signing | Cosign keyless | Sigstore OIDC, no key management |
| Dependency PRs | Dependabot (parallel) | Active separately from pipeline |

## 6. Artifacts

Each CI run produces:

- `brakeman-report.{html,sarif}`
- `semgrep-report.sarif`
- `bundler-audit.txt`
- `trivy-fs.json`, `trivy-image.json`, `trivy-config.json`
- `zap-baseline.{html,json}`
- `sbom.cdx.json` (CycloneDX), `sbom.spdx.json`
- `grype-scan.json`
- `cosign-bundle.json`

Uploaded to GitHub Actions artifacts (30-day retention). SARIF files also uploaded to the GitHub Security tab via `github/codeql-action/upload-sarif`, making findings visible as Code scanning alerts.

## 7. Implementation phases

Each phase ends with all local scans green, a commit on `dev`, an auto-PR to `main`, and a merge once CI is green.

| Phase | Content | Estimated time |
|---|---|---|
| 1. Bootstrap | Snapshot import, attribution, branch protection, dev branch | 1h |
| 2. Runtime viable | Minimum Ruby 3.3 / Rails 7.1 migration, Dockerfile, `docker run` returns HTTP 200 | 3-4h |
| 3. Security tooling local | Install + baseline all tools, local full scan, triage critical/high vs medium/low | 2h |
| 4. Targeted remediation | Fix critical/high, write SECURITY_EXCEPTIONS.md for residuals, atomic commits | 4-6h |
| 5. CI pipeline | `security.yml` + `auto-pr.yml`, iterate via `gh run watch` to green | 3-4h |
| 6. Portfolio | REPORT.md + README + cross-links + profile update + `add-portfolio` skill invocation | 2h |

**Total: 16-20 hours** across 3 sessions.

## 8. REPORT.md structure (10 sections)

1. Context and objective — why RailsGoat, why this matters
2. Initial diagnostic — state of the legacy at takeover
3. Key decisions and justifications — minimum Ruby migration, option B remediation, gating D
4. Challenges encountered — populated from DEV_JOURNAL during work
5. DevSecOps pipeline built
6. Measurable results — before/after counts: findings by severity, CVE count, SBOM coverage, pipeline runtime
7. Limitations and residual risks — medium findings left in place (list), no live deployment, no peer review, DAST baseline limits
8. Engineering practices applied — atomic commits, upstream attribution, documented accepted risks with owner+date, branch protection, image signature, auditable baselines, local-first validation
9. What I would do differently / with more time
10. How to read this repo — navigation guide for the hurried reviewer

Language constraints:
- Accessible to non-technical readers (recruiters, hiring managers)
- Acronyms glossed at first occurrence
- Practitioner-senior tone, no "I struggled / finally figured out" voice
- Humanizer skill applied **before** first commit of REPORT.md

## 9. Portfolio integration

- `railsgoat-security/README.md` — one sentence mentioning AI-assisted speed of implementation
- `find-one-devsecops-case-study/REPORT.md` — new *Related work* section linking to railsgoat-security
- `railsgoat-security/README.md` — reciprocal link to find-one-devsecops-case-study
- `Setounkpe7/Setounkpe7` profile README — new *DevSecOps projects* section listing both case studies with a 2-3 line pitch each; same one-line AI mention

## 10. Definition of done

The project is complete when **all** of the following are true:

- [ ] `main` has received at least one PR-merged commit (no direct push in history)
- [ ] Latest `security.yml` run on `main` is green
- [ ] Image `ghcr.io/setounkpe7/railsgoat-security:latest` is pullable and `cosign verify` passes
- [ ] SBOM CycloneDX present in CI artifacts and in `docs/scan-reports/`
- [ ] `SECURITY_EXCEPTIONS.md` exists; every entry has justification, CVE/CWE, owner, date
- [ ] Zero unaccepted HIGH or CRITICAL findings across all tools
- [ ] Branch protection active and verifiable (output of `gh api /repos/.../branches/main/protection` captured in docs)
- [ ] `pre-commit install` on a fresh clone succeeds
- [ ] `./scripts/scan-all.sh` runs cleanly on a fresh machine with Docker
- [ ] `docker run ghcr.io/...` returns HTTP 200 on `/`
- [ ] REPORT.md covers all 10 sections and has been passed through humanizer before first commit
- [ ] find-one-devsecops-case-study and Setounkpe7 profile README updated
- [ ] `add-portfolio` skill has been invoked and its output committed

## 11. Risks and fallbacks

| Risk | Fallback |
|---|---|
| Rails 7.1 migration too heavy, app does not boot | Fallback to Rails 6.1 (EOL but scannable), document decision |
| ZAP baseline too noisy on intentionally-vulnerable app | Tune `.zap/rules.tsv` to ignore alerts already covered by SAST |
| Runner RAM insufficient for Rails + Postgres + ZAP | Add resource limits in compose, or use larger-size runner (free for public repos) |
| Ruby base image has unpatchable critical CVEs | Switch to `ruby:3.3-slim` or distroless base |
| detect-secrets false positives on RailsGoat fake creds | Add to baseline with `--update` during phase 3 |

New risks discovered during implementation are logged in `docs/DEV_JOURNAL.md` and mirrored in REPORT.md section 7.

## 12. Out of scope (explicit)

To forestall scope creep during implementation:

- Live hosting (Fly.io, Vercel, any cloud)
- Terraform / IaC
- Runtime monitoring stack
- Medium/low finding remediation
- Full Rails application logic rewrite
- Kubernetes manifests or helm charts
- Secret management tooling (Vault, AWS SM) — Rails credentials.yml.enc is sufficient for a non-deployed app
- Performance testing, load testing
- Multi-language i18n of reports
