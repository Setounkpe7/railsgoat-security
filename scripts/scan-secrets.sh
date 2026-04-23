#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p docs/scan-reports

echo "== Secrets: detect-secrets =="
# Pinned to detect-secrets==1.5.0 to match the CI workflow exactly (PyPI's
# latest release; some local installs ship a non-PyPI 1.5.47 build with a
# different plugin set, which would produce a divergent baseline).
# Exclude .brakeman.ignore — its sha256 fingerprints trip the
# Hex High Entropy String detector as a false positive (same exclusion
# as in .pre-commit-config.yaml).

# Compute the file list on the host (python:3.12-slim has no git) and
# pass it positionally into the container.
mapfile -t FILES < <(git ls-files | grep -v -E '^\.brakeman\.ignore$')

docker run --rm -v "$PWD:/src" -w /src python:3.12-slim sh -c \
  'apt-get update -qq >/dev/null 2>&1 && apt-get install -y -q --no-install-recommends git >/dev/null 2>&1 &&
   pip install --quiet detect-secrets==1.5.0 >/dev/null 2>&1 &&
   git config --global --add safe.directory /src &&
   detect-secrets-hook --baseline .secrets.baseline "$@"' \
  -- "${FILES[@]}" \
  > docs/scan-reports/detect-secrets.txt 2>&1 || {
    echo "FAIL — new secrets detected. See docs/scan-reports/detect-secrets.txt"
    cat docs/scan-reports/detect-secrets.txt
    exit 1
  }

echo "Secrets scan OK — no new findings vs baseline"
