#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Usage: bootstrap-node <hostname> <ip> [mac]"
  echo "Example: bootstrap-node k8s-node 192.168.10.16"
  exit 1
fi

HOSTNAME="$1"
IP="$2"
MAC="${3:-}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

BOOTSTRAP_DIR="${REPO_ROOT}/.bootstrap/${HOSTNAME}"
KEY_DIR="${BOOTSTRAP_DIR}/etc/ssh"
KEY_FILE="${KEY_DIR}/ssh_host_ed25519_key"

echo "======================================================"
echo " Bootstrapping Node: ${HOSTNAME} (${IP})"
echo "======================================================"

echo "=== [1/4] Ensuring SSH Host Keypair ==="
mkdir -p "${KEY_DIR}"
if [ ! -f "${KEY_FILE}" ]; then
  ssh-keygen -t ed25519 -N "" -C "root@${HOSTNAME}" -f "${KEY_FILE}"
  chmod 600 "${KEY_FILE}"
  chmod 644 "${KEY_FILE}.pub"
  echo "✓ Generated new host key at ${KEY_FILE}"
else
  echo "✓ Found existing host key at ${KEY_FILE}"
fi

echo "=== [2/4] Deriving Age Recipient Key ==="
HOST_PUBKEY=$(cat "${KEY_FILE}.pub")
HOST_AGE_KEY=$(echo "${HOST_PUBKEY}" | ssh-to-age)
echo "✓ Age recipient: ${HOST_AGE_KEY}"

echo "=== [3/4] Updating .sops.yaml & Re-encrypting Secrets ==="
if ! grep -q "&${HOSTNAME} " .sops.yaml; then
  # Append host key under keys:
  awk -v host="${HOSTNAME}" -v age="${HOST_AGE_KEY}" '
    /# Hosts/ { print; print "  - &" host " " age; next }
    /key_groups:/ { in_kg=1; print; next }
    in_kg && /- \*/ { print; print "          - *" host; in_kg=0; next }
    { print }
  ' .sops.yaml >.sops.yaml.tmp && mv .sops.yaml.tmp .sops.yaml
  echo "✓ Added ${HOSTNAME} to .sops.yaml"
else
  echo "✓ ${HOSTNAME} already exists in .sops.yaml"
fi

export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
sops updatekeys -y secrets/secrets.yaml
echo "✓ Secrets successfully re-encrypted with new host key"

echo "=== [4/4] Provisioning with nixos-anywhere ==="
echo "Target host: qajus@${IP}"
echo "Flake target: .#${HOSTNAME}"
read -p "Execute nixos-anywhere deployment now? (y/N): " -r CONFIRM
if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
  nixos-anywhere \
    --extra-files "${BOOTSTRAP_DIR}" \
    --flake ".#${HOSTNAME}" \
    "qajus@${IP}"
  echo "✓ Provisioning complete! Future updates can be deployed with: colmena apply --on ${HOSTNAME}"
else
  echo "Skipped live install. Host keys and SOPS encryption are ready."
fi
