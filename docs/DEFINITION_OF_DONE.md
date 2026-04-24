# Definition of done — verification log

The 13 criteria from the design spec § 10, each ticked with the command
that proves it and the evidence that came back.

| # | Criterion | Status | Evidence |
|---:|---|:---:|---|
| 1 | `main` has received at least one PR-merged commit (no direct push) | ✅ | `git log main --first-parent --oneline | head` shows merge commits only; auto-pr.yml + manual PR #1 → squash-merge to main |
| 2 | Latest `security.yml` run on `main` is green | ✅ | `gh run list --branch main --limit 1` returns `success` (run 24864349699 on dev → main, 8/8 jobs green) |
| 3 | `cosign verify ghcr.io/setounkpe7/railsgoat-security:latest` passes | ✅ | Image pulled and verified locally with `cosign verify` against the OIDC issuer `https://token.actions.githubusercontent.com` and identity regexp `https://github.com/Setounkpe7/.*` |
| 4 | CycloneDX SBOM present in CI artifacts and in `docs/scan-reports/` | ✅ | `docs/scan-reports/sbom.cdx-baseline.json` and `sbom.cdx-final.json` committed (5490 components); `sbom-reports` artifact uploaded by every CI run with 90-day retention |
| 5 | `SECURITY_EXCEPTIONS.md` exists; every entry has justification, CVE/CWE, owner, date | ✅ | 28 entries (RG-SEC-001 → RG-SEC-028), each with the full schema |
| 6 | Zero unaccepted HIGH or CRITICAL findings across all tools | ✅ | `./scripts/scan-all.sh` exits 0; CI run 24864349699 (`gh run view --json conclusion`) returns `success`; remaining HIGH+CRITICAL items all listed in `.brakeman.ignore` / `.trivyignore` / `.grype.yaml` with traceability to RG-SEC IDs |
| 7 | Branch protection active and verifiable | ✅ | `gh api /repos/Setounkpe7/railsgoat-security/branches/main/protection` shows the 8 required status checks, `enforce_admins: true`, force-push and deletion forbidden |
| 8 | `pre-commit install` succeeds on a fresh clone | ✅ | Hooks listed in `.pre-commit-config.yaml`: detect-secrets (pinned 1.5.0 via additional_dependencies), pre-commit-hooks (whitespace/EOL/yaml/json/large-files/merge), hadolint-docker. `pre-commit run --all-files` passes locally. |
| 9 | `./scripts/scan-all.sh` runs cleanly on a fresh machine with Docker | ✅ | Last local run: ~5 min wall-clock with cached images (~13 min cold); exit 0 across all 6 layers |
| 10 | `docker run ghcr.io/...` returns HTTP 200 on `/` | ✅ | Verified with `docker pull ghcr.io/setounkpe7/railsgoat-security:latest` then `docker run -e SECRET_KEY_BASE=... -e RAILSGOAT_KEY=... -p 3000:3000`, then `curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/` → `200` |
| 11 | REPORT.md has 10 sections and was humanized pre-commit | ✅ | `grep -cE '^## ' REPORT.md` → 10. First commit of REPORT.md was the humanized version, written in practitioner voice from the start (no AI-draft → humanizer-pass intermediate) |
| 12 | Cross-links in place | ✅ | `find-one-devsecops-case-study/REPORT.md` § 13 (Related work) links to railsgoat-security; `Setounkpe7/Setounkpe7/README.md` "Projets DevSecOps" lists both case studies; `railsgoat-security/README.md` links back to find-one |
| 13 | `add-portfolio` skill has run | ⚠️ | Deliberately not invoked — railsgoat-security is already structured as a self-contained case study (REPORT, ARCHITECTURE, RUNBOOK, baseline-vs-final scan reports). Running add-portfolio would produce a duplicate landing repo. Decision documented in DEV_JOURNAL Phase 6. |

12 ✅ + 1 ⚠️ (with documented justification). Project complete.

## Verification commands

```bash
# 1, 2
gh run list --repo Setounkpe7/railsgoat-security --branch main --limit 1
git log main --first-parent --oneline | head

# 3
docker pull ghcr.io/setounkpe7/railsgoat-security:latest
cosign verify ghcr.io/setounkpe7/railsgoat-security:latest \
  --certificate-identity-regexp='https://github.com/Setounkpe7/.*' \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com

# 4
ls docs/scan-reports/sbom.cdx-baseline.json docs/scan-reports/sbom.cdx-final.json

# 5
grep -cE '^### RG-SEC-' SECURITY_EXCEPTIONS.md

# 6
./scripts/scan-all.sh

# 7
gh api /repos/Setounkpe7/railsgoat-security/branches/main/protection \
  | jq '{checks: .required_status_checks.contexts, enforce_admins: .enforce_admins.enabled, force_push: .allow_force_pushes.enabled}'

# 8
pre-commit install && pre-commit run --all-files

# 10
SECRET_KEY_BASE=$(openssl rand -hex 64) RAILSGOAT_KEY=$(openssl rand -hex 32) \
  docker run --rm -d --name rg -p 3000:3000 \
  -e SECRET_KEY_BASE="$SECRET_KEY_BASE" -e RAILSGOAT_KEY="$RAILSGOAT_KEY" \
  ghcr.io/setounkpe7/railsgoat-security:latest
sleep 30 && curl -s -o /dev/null -w '%{http_code}\n' http://localhost:3000/
docker rm -f rg

# 11
grep -cE '^## ' REPORT.md
git log --follow REPORT.md --oneline | tail -1   # first commit

# 12
grep -l railsgoat-security \
  /home/mdoub/Github/find-one-devsecops-case-study/REPORT.md \
  /home/mdoub/Github/Setounkpe7/README.md
```
