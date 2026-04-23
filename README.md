# railsgoat-security

DevSecOps hardening of [OWASP RailsGoat](https://github.com/OWASP/railsgoat) —
a deliberately vulnerable Ruby on Rails training application — with a full
security pipeline (secrets, SAST, SCA, DAST, SBOM, signed container image)
and a documented register of accepted residual risks.

## At a glance

- Eight-layer GitHub Actions security pipeline on every PR to `main`
- Signed Docker image on GHCR, Cosign keyless via Sigstore
- CycloneDX SBOM committed and re-published on every CI run
- Branch-protected `main`, working branch `dev` with auto-PR
- Findings visible in the GitHub Security tab via SARIF uploads
- Local `scripts/scan-all.sh` mirrors the CI gates exactly

## Repository navigation

| File | Purpose |
|---|---|
| [REPORT.md](REPORT.md) | Full case study — start here |
| [SECURITY_EXCEPTIONS.md](SECURITY_EXCEPTIONS.md) | Formally accepted residual risks (28 entries) |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Pipeline diagram and branch / PR flow |
| [docs/RUNBOOK.md](docs/RUNBOOK.md) | How to reproduce every scan locally |
| [docs/DEV_JOURNAL.md](docs/DEV_JOURNAL.md) | Dated decisions, obstacles, time spent |
| [docs/scan-reports/](docs/scan-reports/) | Baseline + final scan outputs, side by side |
| [.github/workflows/security.yml](.github/workflows/security.yml) | CI pipeline source of truth |

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

Outputs land in `docs/scan-reports/`. Same gating thresholds as CI — green
locally guarantees green in CI.

## Related work

- [find-one-devsecops-case-study](https://github.com/Setounkpe7/find-one-devsecops-case-study) —
  my first DevSecOps case study (Find-One platform).

## Credits

Built on [OWASP RailsGoat](https://github.com/OWASP/railsgoat) (MIT). See
[CREDITS.md](CREDITS.md) and [NOTICE.md](NOTICE.md) for full attribution.

This project was built with AI assistance (Claude Code) to speed
implementation; the engineering decisions are mine.

## License

MIT — see [LICENSE.md](LICENSE.md). RailsGoat copyright preserved per the
upstream MIT terms.
