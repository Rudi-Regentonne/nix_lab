#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_FILE="${REPO_ROOT}/secrets/secrets.yaml"

KEY_NAME="${1:-user-password-hash}"

echo "======================================================"
echo " Update Encrypted Password: ${KEY_NAME}"
echo "======================================================"

if [ ! -f "${SECRETS_FILE}" ]; then
  echo "❌ Error: Secrets file not found at ${SECRETS_FILE}"
  exit 1
fi

# Prompt for password without echoing
read -s -p "Enter new password: " PASS1
echo
read -s -p "Confirm new password: " PASS2
echo

if [ -z "$PASS1" ]; then
  echo "❌ Error: Password cannot be empty."
  exit 1
fi

if [ "$PASS1" != "$PASS2" ]; then
  echo "❌ Error: Passwords do not match."
  exit 1
fi

echo "Hashing password using SHA-512 crypt..."
HASH=$(mkpasswd -m sha-512 "$PASS1")

export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
sops set "${SECRETS_FILE}" "[\"${KEY_NAME}\"]" "\"${HASH}\""

echo "✓ Successfully hashed and encrypted '${KEY_NAME}' in ${SECRETS_FILE}"
echo "Deploy changes when ready using: deploy [--on <host>]"
