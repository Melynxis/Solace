#!/usr/bin/env bash
# push_to_github.sh — Auto-add, commit, and push all changes (Solace repo)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

# Use deploy SSH key if configured
export GIT_SSH_COMMAND="ssh -i ~/.ssh/solace_deploy_key -o IdentitiesOnly=yes"

# Add all changes (including untracked files)
git add -A

# Commit with timestamp if nothing provided
COMMIT_MSG="Auto-push: $(date +'%Y-%m-%d %H:%M:%S')"

# Only commit if there are staged changes
if git diff --cached --quiet; then
  echo "No changes to commit."
else
  git commit -m "$COMMIT_MSG"
  echo "Committed: $COMMIT_MSG"
fi

# Push to origin/main
git push origin main

echo "✅ All changes pushed to GitHub."
