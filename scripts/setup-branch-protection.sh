#!/usr/bin/env bash
set -euo pipefail

# Applies branch protection on main. Idempotent — safe to re-run.
# Run from repo root. Requires `gh` authenticated with repo-admin scope.

OWNER="Setounkpe7"
REPO="railsgoat-security"

# The status checks list will be populated once CI job names exist.
# For phase 1 we apply structural protections only; required checks
# are added in Task 5.7 after security.yml lands on main.

gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "/repos/${OWNER}/${REPO}/branches/main/protection" \
  --input - <<'EOF'
{
  "required_status_checks": null,
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

echo "Branch protection applied on main."
