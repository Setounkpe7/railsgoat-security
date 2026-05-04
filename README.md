# railsgoat-security

DevSecOps hardening of [OWASP RailsGoat](https://github.com/OWASP/railsgoat),
a deliberately vulnerable Ruby on Rails training app. The repo wraps the
upstream code in a full security pipeline (secrets, SAST, SCA, DAST, SBOM,
signed image) and keeps a dated register of every risk I chose to accept
rather than fix.

## What's in here

- Eight-job GitHub Actions pipeline that runs on every PR to `main`.
- Container image published to GHCR and signed with Cosign keyless (Sigstore OIDC, no key to manage).
- CycloneDX SBOM committed under `docs/scan-reports/` and regenerated on every CI run.
- `main` is branch-protected; all work happens on `dev` and lands via PR.
- Scan findings show up in the GitHub Security tab as SARIF.
- Whatever CI runs, `./scripts/scan-all.sh` runs locally with the same gates.

## Where to look

| File | What it is |
|---|---|
| [REPORT.md](REPORT.md) | The case study. Start here. |
| [SECURITY_EXCEPTIONS.md](SECURITY_EXCEPTIONS.md) | 28 formally accepted residual risks, each with a CVE/CWE, owner and review date |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Pipeline diagram, branch and PR flow |
| [docs/RUNBOOK.md](docs/RUNBOOK.md) | How to reproduce every scan locally |
| [docs/DEV_JOURNAL.md](docs/DEV_JOURNAL.md) | Dated decisions, obstacles, time actually spent |
| [docs/scan-reports/](docs/scan-reports/) | Baseline vs final scan outputs, side by side |
| [.github/workflows/security.yml](.github/workflows/security.yml) | CI pipeline, source of truth |

## Pull and verify the signed image

```bash
docker pull ghcr.io/setounkpe7/railsgoat-security:latest
cosign verify ghcr.io/setounkpe7/railsgoat-security:latest \
  --certificate-identity-regexp='https://github.com/Setounkpe7/.*' \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com
```

## Reproduce the pipeline locally

```bash
./scripts/scan-all.sh
```

Reports land in `docs/scan-reports/`. The script uses the same gating
thresholds as CI, so if it passes locally the CI run on your PR should pass too.

## Related work

- [find-one-devsecops-case-study](https://github.com/Setounkpe7/find-one-devsecops-case-study),
  my first DevSecOps case study (on the Find-One platform). Covers the
  non-container layers; this repo covers the container and DAST story.

## Credits

Built on [OWASP RailsGoat](https://github.com/OWASP/railsgoat) (MIT).
Attribution lives in [CREDITS.md](CREDITS.md) and [NOTICE.md](NOTICE.md).

I built this with AI assistance (Claude Code) to speed implementation.
The engineering calls — scope, tool choice, gating thresholds, what to
fix versus accept — are mine.

## License

MIT, see [LICENSE.md](LICENSE.md). The RailsGoat copyright stays intact
per the upstream MIT terms.
