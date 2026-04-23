#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p docs/scan-reports

FAIL=0

echo "== SAST: Brakeman =="
# Run Brakeman from its official image to avoid requiring Ruby locally.
docker run --rm -v "$PWD:/code" presidentbeef/brakeman:latest \
  --no-progress --no-pager \
  --format json --output /code/docs/scan-reports/brakeman.json \
  -w2 || true

# Brakeman exits non-zero when warnings are present; we gate on
# High-confidence count from the JSON instead.
if [ -f docs/scan-reports/brakeman.json ]; then
  HIGH=$(jq '[.warnings[]? | select(.confidence == "High")] | length' \
    docs/scan-reports/brakeman.json)
  TOTAL=$(jq '[.warnings[]?] | length' docs/scan-reports/brakeman.json)
  echo "Brakeman: $TOTAL warnings total, $HIGH High-confidence"
  if [ "$HIGH" -gt 0 ]; then
    echo "FAIL — Brakeman High-confidence findings present"
    FAIL=1
  fi

  # HTML report (best-effort, separate run for the rich format)
  docker run --rm -v "$PWD:/code" presidentbeef/brakeman:latest \
    --no-progress --no-pager \
    --format html --output /code/docs/scan-reports/brakeman.html \
    -w2 >/dev/null 2>&1 || true
else
  echo "FAIL — Brakeman did not produce a report"
  FAIL=1
fi

echo "== SAST: Semgrep =="
HOST_PWD="$PWD"
if command -v semgrep >/dev/null 2>&1; then
  semgrep scan --config=p/ruby --config=p/security-audit \
    --sarif --output docs/scan-reports/semgrep.sarif \
    --quiet || true
else
  docker run --rm -v "$HOST_PWD:/src" -w /src semgrep/semgrep:latest \
    semgrep scan --config=p/ruby --config=p/security-audit \
      --sarif --output /src/docs/scan-reports/semgrep.sarif \
      --quiet || true
fi

if [ -f docs/scan-reports/semgrep.sarif ]; then
  ERROR=$(jq '[.runs[0].results[]? | select(.level == "error")] | length' \
    docs/scan-reports/semgrep.sarif)
  TOTAL=$(jq '[.runs[0].results[]?] | length' docs/scan-reports/semgrep.sarif)
  echo "Semgrep: $TOTAL findings total, $ERROR ERROR-level"
  if [ "$ERROR" -gt 0 ]; then
    echo "FAIL — Semgrep ERROR-level findings present"
    FAIL=1
  fi
else
  echo "FAIL — Semgrep did not produce a SARIF report"
  FAIL=1
fi

[ "$FAIL" -eq 0 ] && echo "SAST OK" || { echo "SAST FAIL"; exit 1; }
