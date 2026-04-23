#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p docs/scan-reports

IMAGE="${IMAGE:-railsgoat-security:local}"

echo "== SBOM: Syft (CycloneDX + SPDX) =="
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD/docs/scan-reports:/out" \
  anchore/syft:latest \
  "$IMAGE" -o cyclonedx-json=/out/sbom.cdx.json \
           -o spdx-json=/out/sbom.spdx.json

echo "== SBOM CVE scan: Grype =="
docker run --rm \
  -v "$PWD/docs/scan-reports:/out" \
  anchore/grype:latest \
  sbom:/out/sbom.cdx.json \
  --fail-on critical \
  -o json > docs/scan-reports/grype.json || {
    echo "FAIL — Grype reports Critical CVE"
    jq '[.matches[]? | select(.vulnerability.severity == "Critical")] | length' \
      docs/scan-reports/grype.json 2>/dev/null
    exit 1
  }

echo "SBOM OK"
