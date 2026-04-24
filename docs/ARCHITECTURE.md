# Architecture

## Branch and pull-request flow

```
main  ←  protected: squash-merge only, 8 required status checks,
  ↑       no force-push, no deletion
  │
  │  Pull request opened automatically by .github/workflows/auto-pr.yml
  │  (or manually for the very first PR — see DEV_JOURNAL Phase 5)
  │
dev   ←  working branch, direct pushes allowed
          local pre-commit hooks run on every commit
```

No feature branches. Solo project: documented as a trade-off in
`REPORT.md` § 7.

## CI pipeline (`.github/workflows/security.yml`)

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

Triggers: `pull_request` to `main`, plus `workflow_dispatch`.
Concurrency group `security-${ref}` cancels in-progress runs.
Permissions: `contents:read`, `packages:write`, `id-token:write` (OIDC
for Cosign), `security-events:write` (SARIF upload), `pull-requests:write`.
Estimated runtime: 12 to 16 minutes per run.

## Per-tool gating thresholds

| Tool | Fails on |
|---|---|
| detect-secrets | Any new finding versus `.secrets.baseline` |
| Brakeman | High-confidence finding (after `.brakeman.ignore`) |
| Semgrep | ERROR-level finding |
| bundler-audit | Critical CVE in Gemfile.lock |
| Trivy filesystem | Critical CVE |
| Trivy image — OS packages | Critical CVE (after `.trivyignore`) |
| Trivy image — libraries | High or Critical CVE (after `.trivyignore`) |
| Hadolint | error level (config in `.hadolint.yaml`) |
| Trivy config | Critical Dockerfile / IaC misconfiguration |
| ZAP baseline | High-risk alert |
| Grype on the SBOM | Critical CVE (after `.grype.yaml`) |

## Artifact lifecycle

| Artifact | Where it lives | Retention |
|---|---|---|
| Baseline scan reports | `docs/scan-reports/*-baseline.*` (committed) | permanent |
| Final scan reports | `docs/scan-reports/*-final.*` (committed) | permanent |
| Per-run scan reports | GitHub Actions artifacts | 30 days |
| SBOM artefacts | GitHub Actions artifacts | 90 days |
| SARIF findings | GitHub Security tab via `codeql-action/upload-sarif` | per repo policy |
| Signed container image | `ghcr.io/setounkpe7/railsgoat-security` | permanent |
| Cosign signature bundle | Sigstore Rekor transparency log | permanent |

## Local mirror

`scripts/scan-all.sh` runs the same six layers as CI in the same order
with the same gating thresholds. Tools that aren't installed natively
(Brakeman, Trivy, Hadolint, Syft, Grype, ZAP, bundler-audit) are invoked
through their official Docker images; the only host requirement beyond
Docker is `jq` and `openssl`. Green local = green CI.

## Where the four ignore files live and what they cover

| File | Read by | Covers |
|---|---|---|
| `.secrets.baseline` | detect-secrets | 30 baselined hardcoded credentials |
| `.brakeman.ignore` | Brakeman | 18 SHA-256 fingerprints (intentional vulns) |
| `.semgrepignore` | Semgrep | path exclusions (vendored libs, scan reports) |
| `.trivyignore` | Trivy fs + Trivy image | 5 CVE IDs with `exp:YYYY-MM-DD` expiries |
| `.grype.yaml` | Grype | mirror of `.trivyignore` (different format) |

[SECURITY_EXCEPTIONS.md](../SECURITY_EXCEPTIONS.md) is the single source of
truth: every entry above corresponds to one or more `RG-SEC-NNN` IDs
catalogued there.
