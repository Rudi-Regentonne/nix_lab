#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FAILED=0
for f in $(find "$REPO_ROOT/secrets" -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.env" \) 2>/dev/null); do
  STATUS=$(sops filestatus "$f" 2>/dev/null || echo '{"encrypted":false}')
  if ! echo "$STATUS" | grep -q '"encrypted":true'; then
    echo "❌ SECURITY ALERT: $f is NOT encrypted with SOPS!"
    FAILED=1
  fi
done

if [ "$FAILED" -ne 0 ]; then
  echo "Commit rejected to protect plaintext secrets from leaking."
  exit 1
fi
