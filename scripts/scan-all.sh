#!/usr/bin/env bash
# Run the full local DevSecOps pipeline. Mirrors .github/workflows/security.yml.
# Continues on individual scanner failures so the operator gets a full report
# in docs/scan-reports/, then exits non-zero at the end if any layer failed.
set -uo pipefail
cd "$(dirname "$0")/.."

OVERALL=0
FAILED=()

run_layer() {
  local label="$1"; shift
  echo
  echo "=========================================="
  echo " $label"
  echo "=========================================="
  if "$@"; then
    echo "[OK]  $label"
  else
    echo "[FAIL] $label"
    OVERALL=1
    FAILED+=("$label")
  fi
}

run_layer "[1/6] Secrets"          ./scripts/scan-secrets.sh
run_layer "[2/6] SAST"             ./scripts/scan-sast.sh
run_layer "[3/6] SCA"              ./scripts/scan-sca.sh
run_layer "[4/6] Image build+scan" ./scripts/scan-image.sh
run_layer "[5/6] DAST"             ./scripts/scan-dast.sh
run_layer "[6/6] SBOM"             ./scripts/generate-sbom.sh

echo
echo "=========================================="
if [ "$OVERALL" -eq 0 ]; then
  echo " All scans passed. Reports in docs/scan-reports/"
else
  echo " ${#FAILED[@]} layer(s) failed: ${FAILED[*]}"
  echo " Reports written to docs/scan-reports/ for triage"
fi
echo "=========================================="

exit "$OVERALL"
