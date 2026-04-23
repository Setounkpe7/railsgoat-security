#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p docs/scan-reports

FAIL=0
IMAGE="${IMAGE:-railsgoat-security:local}"

echo "== Image: build $IMAGE =="
docker build -t "$IMAGE" . > /tmp/scan-image-build.log 2>&1 || {
  tail -20 /tmp/scan-image-build.log
  echo "FAIL — image build failed"
  exit 1
}

echo "== Image: Hadolint =="
docker run --rm -i -v "$PWD/.hadolint.yaml:/.hadolint.yaml" \
  hadolint/hadolint hadolint --config /.hadolint.yaml - \
  < Dockerfile > docs/scan-reports/hadolint.txt 2>&1 || {
    cat docs/scan-reports/hadolint.txt
    echo "FAIL — Hadolint reports error-level issues"
    FAIL=1
  }
[ -s docs/scan-reports/hadolint.txt ] && cat docs/scan-reports/hadolint.txt
echo "Hadolint OK"

echo "== Image: Trivy config =="
docker run --rm -v "$PWD:/src" -w /src aquasec/trivy:latest \
  config --severity CRITICAL --format json \
         --output docs/scan-reports/trivy-config.json /src || true
if [ -f docs/scan-reports/trivy-config.json ]; then
  CRIT=$(jq '[.Results[]?.Misconfigurations[]? | select(.Severity == "CRITICAL")] | length' \
    docs/scan-reports/trivy-config.json)
  echo "Trivy config: $CRIT CRITICAL misconfigurations"
  [ "$CRIT" -gt 0 ] && FAIL=1
fi

echo "== Image: Trivy image (OS packages) =="
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD:/src" aquasec/trivy:latest \
  image --severity CRITICAL --pkg-types os \
        --format json --output /src/docs/scan-reports/trivy-image-os.json \
        "$IMAGE" || true
if [ -f docs/scan-reports/trivy-image-os.json ]; then
  CRIT=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL")] | length' \
    docs/scan-reports/trivy-image-os.json)
  echo "Trivy image OS: $CRIT CRITICAL"
  [ "$CRIT" -gt 0 ] && FAIL=1
fi

echo "== Image: Trivy image (application libs) =="
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD:/src" aquasec/trivy:latest \
  image --severity HIGH,CRITICAL --pkg-types library \
        --format json --output /src/docs/scan-reports/trivy-image-lib.json \
        "$IMAGE" || true
if [ -f docs/scan-reports/trivy-image-lib.json ]; then
  HC=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL" or .Severity == "HIGH")] | length' \
    docs/scan-reports/trivy-image-lib.json)
  echo "Trivy image libs: $HC HIGH+CRITICAL"
  [ "$HC" -gt 0 ] && FAIL=1
fi

[ "$FAIL" -eq 0 ] && echo "Image scan OK" || { echo "Image scan FAIL"; exit 1; }
