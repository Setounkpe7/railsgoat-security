#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p docs/scan-reports

echo "== Secrets: detect-secrets =="
# Uses installed detect-secrets if present, otherwise falls back to a
# pinned image (CI installs the pip package directly).
if command -v detect-secrets-hook >/dev/null 2>&1; then
  HOOK="detect-secrets-hook"
else
  HOOK="docker run --rm -v $PWD:/src -w /src ghcr.io/yelp/detect-secrets:1.5.47 detect-secrets-hook"
fi

# Exclude .brakeman.ignore — its sha256 fingerprints trip the
# Hex High Entropy String detector as a false positive (same exclusion
# as in .pre-commit-config.yaml).
# shellcheck disable=SC2046
$HOOK --baseline .secrets.baseline \
  $(git ls-files | grep -v -E '^\.brakeman\.ignore$') \
  > docs/scan-reports/detect-secrets.txt 2>&1 || {
    echo "FAIL — new secrets detected. See docs/scan-reports/detect-secrets.txt"
    cat docs/scan-reports/detect-secrets.txt
    exit 1
  }

echo "Secrets scan OK — no new findings vs baseline"
