#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p docs/scan-reports

IMAGE="${IMAGE:-railsgoat-security:local}"
PORT="${PORT:-3000}"

echo "== DAST: ZAP baseline =="

SECRET_KEY_BASE=$(openssl rand -hex 64)
RAILSGOAT_KEY=$(openssl rand -hex 32)

docker rm -f rg-dast >/dev/null 2>&1 || true
docker run -d --name rg-dast -p "${PORT}:3000" \
  -e SECRET_KEY_BASE="$SECRET_KEY_BASE" \
  -e RAILSGOAT_KEY="$RAILSGOAT_KEY" \
  "$IMAGE" >/dev/null

cleanup() { docker rm -f rg-dast >/dev/null 2>&1 || true; }
trap cleanup EXIT

# Wait for the app to answer 200
for i in $(seq 1 45); do
  if curl -fsS "http://localhost:${PORT}/" >/dev/null 2>&1; then
    echo "App ready after ${i}s"
    break
  fi
  sleep 1
done

curl -fsS "http://localhost:${PORT}/" >/dev/null 2>&1 || {
  echo "FAIL — target never returned 200"
  docker logs rg-dast 2>&1 | tail -20
  exit 1
}

# Run ZAP baseline against the host port
docker run --rm --network=host \
  -v "$PWD/docs/scan-reports:/zap/wrk" \
  ghcr.io/zaproxy/zaproxy:stable \
  zap-baseline.py -t "http://localhost:${PORT}" \
    -r zap-baseline.html -J zap-baseline.json \
    -I || true

# Gate on High-risk alerts (riskcode == 3)
if [ -f docs/scan-reports/zap-baseline.json ]; then
  HIGH=$(jq '[.site[]?.alerts[]? | select(.riskcode == "3")] | length' \
    docs/scan-reports/zap-baseline.json)
  TOTAL=$(jq '[.site[]?.alerts[]?] | length' docs/scan-reports/zap-baseline.json)
  echo "ZAP: $TOTAL alerts total, $HIGH High"
  if [ "$HIGH" -gt 0 ]; then
    echo "FAIL — ZAP reports High-risk alerts"
    exit 1
  fi
else
  echo "FAIL — ZAP did not produce a JSON report"
  exit 1
fi

echo "DAST OK"
