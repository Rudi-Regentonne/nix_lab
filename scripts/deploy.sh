#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [ -n "$(git status --porcelain)" ]; then
  echo "⚠️  Working tree has uncommitted changes (autoUpgrade on hosts pulls from GitHub)."
fi

echo "=== Executing Colmena Deployment ==="
colmena apply "$@"
