# Runbook — reproducing every scan locally

## Prerequisites

- Docker (the scan scripts use official tool images for everything that
  isn't installed natively)
- `jq`
- `openssl`
- `gh` CLI authenticated against your GitHub account

Optionally, for faster local iteration:

- `detect-secrets` ≥ 1.5.47 (`pipx install detect-secrets`)
- `pre-commit` ≥ 4.5 (`pipx install pre-commit`)
- `semgrep` (`pipx install semgrep`)

## One-time setup

```bash
git clone https://github.com/Setounkpe7/railsgoat-security.git
cd railsgoat-security
pre-commit install     # uses .pre-commit-config.yaml
```

That's it — no Ruby, no rbenv, no per-tool installs. The first
`scripts/scan-all.sh` run will pull the required Docker images (about
1.5 GB total, mostly ZAP).

## Run the full pipeline locally

```bash
./scripts/scan-all.sh
```

Reports land in `docs/scan-reports/`. The script exits non-zero on any
gate failure with the same semantics as CI:

| Layer | Script | Gate |
|---|---|---|
| 1. Secrets | `scan-secrets.sh` | any new finding versus `.secrets.baseline` |
| 2. SAST | `scan-sast.sh` | Brakeman High-confidence; Semgrep ERROR |
| 3. SCA | `scan-sca.sh` | bundler-audit Critical; Trivy fs Critical |
| 4. Image | `scan-image.sh` | Hadolint error; Trivy OS Critical; Trivy libs High+ |
| 5. DAST | `scan-dast.sh` | ZAP High-risk alert |
| 6. SBOM | `generate-sbom.sh` | Grype Critical |

## Run one layer at a time

```bash
./scripts/scan-secrets.sh
./scripts/scan-sast.sh
./scripts/scan-sca.sh
./scripts/scan-image.sh
./scripts/scan-dast.sh       # builds + runs the container, then ZAP
./scripts/generate-sbom.sh   # depends on a built railsgoat-security:local image
```

## Run the application by itself

```bash
docker compose up -d         # exports SECRET_KEY_BASE + RAILSGOAT_KEY required
curl -fsS http://localhost:3000/    # 200
docker compose down
```

If you don't have `SECRET_KEY_BASE` and `RAILSGOAT_KEY` exported, compose
fails fast with a useful message rather than a Rails stack trace.

## Pull and verify the published image

```bash
docker pull ghcr.io/setounkpe7/railsgoat-security:latest
cosign verify ghcr.io/setounkpe7/railsgoat-security:latest \
  --certificate-identity-regexp='https://github.com/Setounkpe7/.*' \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com
```

## Re-apply branch protection

```bash
./scripts/setup-branch-protection.sh
```

The script is idempotent. Run it after any change to required-status-check
names (workflow job renames). You need a `gh` session with admin rights on
the repo.

## Re-baseline procedure (every six months, or on base-image bump)

1. Run `./scripts/scan-all.sh` and capture fresh reports.
2. For each `.trivyignore` and `.grype.yaml` entry, re-check the
   Debian / GHSA tracker URL listed in `SECURITY_EXCEPTIONS.md`. If a fix
   landed, remove the entry, bump the package, re-run.
3. For each Brakeman / Semgrep entry, only edit if RailsGoat upstream
   changes the vulnerable code (rare).
4. Update `Accepted date` and `Review date` in `SECURITY_EXCEPTIONS.md`
   for entries kept as-is.
5. Replace `docs/scan-reports/*-final.*` with the new outputs.
6. Commit on `dev`. Auto-PR opens, security pipeline gates the merge.

## Troubleshooting

- **`docker run` returns 500 on `/`** — check that both `SECRET_KEY_BASE`
  and `RAILSGOAT_KEY` env vars are set.
- **`detect-secrets` flags a legitimate baseline entry** — run
  `detect-secrets audit .secrets.baseline` to mark it as accepted, then
  re-run the scan.
- **bundler-audit can't reach github.com** — the one-off Ruby container
  needs egress to download `ruby-advisory-db`. Workaround: pre-clone the
  database into a Docker volume and mount it; or rely on CI (the
  GitHub-hosted runner has direct egress).
- **Trivy DB outdated locally** — `docker run --rm aquasec/trivy image
  --download-db-only` refreshes it.
- **Cosign verify works in CI but not locally** — you need `cosign` v2+
  locally (`cosign version` to check).
- **Auto-PR workflow fails with "GitHub Actions is not permitted to
  create or approve pull requests"** — enable
  *Settings → Actions → General → Workflow permissions → Allow GitHub
  Actions to create and approve pull requests*, or switch the workflow
  to a fine-grained personal access token.
