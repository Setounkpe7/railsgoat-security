#!/usr/bin/env bash
set -euo pipefail

# Applies branch protection on main with all 8 security.yml jobs as
# required status checks. Idempotent — safe to re-run.
# Run from repo root. Requires `gh` authenticated with repo-admin scope.
#
# The check names below MUST match the `name:` of each job in
# .github/workflows/security.yml exactly.

OWNER="Setounkpe7"
REPO="railsgoat-security"

gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "/repos/${OWNER}/${REPO}/branches/main/protection" \
  --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "Secrets (detect-secrets)",
      "SAST (Brakeman + Semgrep)",
      "SCA (bundler-audit + Trivy fs)",
      "Docker build + lint",
      "Image scan (Trivy)",
      "DAST (ZAP baseline)",
      "SBOM (Syft + Grype)",
      "Sign + push (GHCR)"
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 0
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true,
  "lock_branch": false,
  "allow_fork_syncing": false
}
EOF

echo "Branch protection (with required checks) applied on main."
