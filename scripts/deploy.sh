#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DIRTY=0
COMMIT_MSG=""
COLMENA_ARGS=()

# Parse arguments to extract -d / --dirty and -m / --message
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dirty)
      DIRTY=1
      shift
      ;;
    -m|--message)
      COMMIT_MSG="$2"
      shift 2
      ;;
    *)
      COLMENA_ARGS+=("$1")
      shift
      ;;
  esac
done

if [ "$DIRTY" -eq 1 ]; then
  echo "⚠️  [DIRTY MODE] Deploying uncommitted/unpushed local changes (--dirty enabled)."
  echo "⚠️  Note: If system.autoUpgrade runs on the host, unpushed changes may be overwritten."
else
  # Check for uncommitted or untracked changes
  CHANGES=$(git status --porcelain)
  if [ -n "$CHANGES" ]; then
    echo "=== [1/3] Changes detected. Verifying secrets before auto-commit ==="
    "$REPO_ROOT/scripts/check-secrets-encrypted.sh"

    echo "=== [2/3] Auto-committing changes to Git ==="
    git add -A

    if [ -z "$COMMIT_MSG" ]; then
      COMMIT_MSG="deploy: auto-commit $(date +'%Y-%m-%d %H:%M:%S')"
    fi
    git commit -m "$COMMIT_MSG"

    echo "=== [3/3] Pushing changes to GitHub ==="
    CURRENT_BRANCH=$(git branch --show-current)
    if [ -n "$CURRENT_BRANCH" ]; then
      git push origin "$CURRENT_BRANCH"
      echo "✓ Pushed cleanly to origin/$CURRENT_BRANCH (local and GitHub in sync)"
    fi
  else
    # Check if local commits are ahead of remote
    AHEAD=$(git status -sb | grep -o 'ahead [0-9]*' || true)
    if [ -n "$AHEAD" ]; then
      echo "=== Local branch ahead of GitHub. Pushing to stay in sync ==="
      CURRENT_BRANCH=$(git branch --show-current)
      git push origin "$CURRENT_BRANCH"
      echo "✓ Pushed cleanly to origin/$CURRENT_BRANCH"
    else
      echo "✓ Working tree is clean and in sync with GitHub."
    fi
  fi
fi

echo "=== Executing Colmena Deployment ==="
colmena apply "${COLMENA_ARGS[@]}"
