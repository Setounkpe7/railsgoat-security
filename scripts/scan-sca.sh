#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p docs/scan-reports

FAIL=0

echo "== SCA: bundler-audit =="
# bundler-audit isn't in the production image (development gem only).
# Run it through a one-off ruby container and install the gem inline.
docker run --rm -v "$PWD:/app" -w /app ruby:3.4.1-slim sh -c \
  "gem install bundler-audit --no-document --silent && \
   bundle-audit check --update" \
  > docs/scan-reports/bundler-audit.txt 2>&1 || true

cat docs/scan-reports/bundler-audit.txt
if grep -qE "^Criticality: Critical$" docs/scan-reports/bundler-audit.txt; then
  echo "FAIL — bundler-audit reports Critical CVE"
  FAIL=1
fi

echo "== SCA: Trivy filesystem =="
docker run --rm -v "$PWD:/src" -w /src aquasec/trivy:latest \
  fs --severity CRITICAL \
     --ignorefile /src/.trivyignore \
     --format json --output docs/scan-reports/trivy-fs.json \
     /src || true

if [ -f docs/scan-reports/trivy-fs.json ]; then
  CRIT=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL")] | length' \
    docs/scan-reports/trivy-fs.json)
  echo "Trivy fs: $CRIT CRITICAL"
  if [ "$CRIT" -gt 0 ]; then
    echo "FAIL — Trivy fs reports CRITICAL"
    FAIL=1
  fi
fi

[ "$FAIL" -eq 0 ] && echo "SCA OK" || { echo "SCA FAIL"; exit 1; }
