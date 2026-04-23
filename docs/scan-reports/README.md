# Committed scan reports

Two snapshots are kept here for every tool:

- `*-baseline.*` — first full pass before any remediation (Phase 3 output).
- `*-final.*` — last pass after Phase 4 remediation (added in Phase 4).
- Files without `-baseline` / `-final` suffix are the most recent local
  run (overwritten on every `./scripts/scan-all.sh` invocation).

`TRIAGE.md` lists every baseline finding with its disposition
(fix vs accept) and is the source of truth for the Phase 4 work plan.

## Tool → file map

| File | Tool | Format |
|---|---|---|
| `brakeman-*.{html,json}` | Brakeman | rich HTML + machine JSON |
| `semgrep-*.sarif` | Semgrep | SARIF |
| `bundler-audit-*.txt` | bundler-audit | text |
| `trivy-fs-*.json` | Trivy filesystem | JSON |
| `trivy-image-os-*.json` | Trivy image, OS packages | JSON |
| `trivy-image-lib-*.json` | Trivy image, application libs | JSON |
| `trivy-config-*.json` | Trivy config / IaC | JSON |
| `hadolint-*.txt` | Hadolint | text |
| `zap-baseline-*.{html,json}` | OWASP ZAP baseline | HTML + JSON |
| `sbom.cdx-*.json` | Syft → CycloneDX | JSON |
| `sbom.spdx-*.json` | Syft → SPDX | JSON |
| `grype-*.json` | Grype on the SBOM | JSON |
| `detect-secrets-*.txt` | detect-secrets-hook | text (empty if no new finding) |
