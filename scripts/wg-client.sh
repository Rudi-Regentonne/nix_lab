#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
SECRETS_FILE="$REPO_ROOT/secrets/secrets.yaml"
NETWORK_FILE="$REPO_ROOT/common/network.nix"

if [ ! -f "$SECRETS_FILE" ]; then
  echo "❌ Error: secrets/secrets.yaml not found at $SECRETS_FILE"
  exit 1
fi

ACTION="${1:-}"

# Helper to run wg command
run_wg() {
  if command -v wg >/dev/null 2>&1; then
    wg "$@"
  else
    nix shell nixpkgs#wireguard-tools -c wg "$@"
  fi
}

# Subcommand: list clients or show usage if no arguments provided
if [ -z "$ACTION" ] || [ "$ACTION" = "list" ] || [ "$ACTION" = "-l" ] || [ "$ACTION" = "--help" ] || [ "$ACTION" = "-h" ]; then
  echo "======================================================"
  echo " WireGuard Client Profiles"
  echo "======================================================"
  echo "Available clients:"
  nix eval --impure --json --expr 'builtins.mapAttrs (_: c: c.address) (import ./common/network.nix).wireguard.clients' 2>/dev/null |
    jq -r 'to_entries[] | "  • \(.key)\t(\(.value))"' || echo "  (none configured)"
  echo
  echo "Usage:"
  echo "  wg-client <name>        Display profile and QR code for an existing client"
  echo "  wg-client add [name]    Create and register a new WireGuard client"
  echo "  wg-client list          List all registered WireGuard clients"
  exit 0
fi

# Subcommand: add client
if [ "$ACTION" = "add" ]; then
  NAME="${2:-}"
  if [ -z "$NAME" ]; then
    read -r -p "Enter new client name (e.g. laptop, tablet, tv): " NAME
  fi

  # Validate name
  NAME=$(echo "$NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
  if [[ ! "$NAME" =~ ^[a-z0-9_-]+$ ]]; then
    echo "❌ Error: Client name must contain only lowercase alphanumeric characters, hyphens, or underscores."
    exit 1
  fi

  # Check if already exists in network.nix
  EXISTS=$(nix eval --impure --expr "(import ./common/network.nix).wireguard.clients ? ${NAME}" 2>/dev/null || echo "false")
  if [ "$EXISTS" = "true" ]; then
    echo "❌ Error: Client '${NAME}' already exists in common/network.nix."
    exit 1
  fi

  echo "=== Creating WireGuard Client: ${NAME} ==="

  # Calculate next available IP in 10.10.10.x
  NEXT_OCTET=$(nix eval --impure --expr '
    let
      clients = builtins.attrValues (import ./common/network.nix).wireguard.clients;
      octets = map (c:
        let
          parts = builtins.filter (x: builtins.isString x && x != "") (builtins.split "\\." c.address);
        in
          builtins.fromJSON (builtins.elemAt parts 3)
      ) clients;
      maxOctet = if octets == [] then 9 else builtins.foldl'\'' (a: b: if a > b then a else b) 9 octets;
    in
      maxOctet + 1
  ')

  CLIENT_IP="10.10.10.${NEXT_OCTET}"
  CLIENT_IP6="fd10:10:10::${NEXT_OCTET}"
  echo "✓ Assigned IP: ${CLIENT_IP} ${CLIENT_IP6}"

  # Generate WireGuard keypair
  PRIV=$(run_wg genkey)
  PUB=$(echo "$PRIV" | run_wg pubkey)
  echo "✓ Generated WireGuard keypair (Public: ${PUB})"

  # Store private key in sops
  echo "Encrypting private key into secrets/secrets.yaml..."
  sops set "$SECRETS_FILE" "[\"wireguard\"][\"${NAME}-private\"]" "\"$PRIV\""
  echo "✓ Private key encrypted under wireguard.${NAME}-private"

  # Append client to common/network.nix
  awk -v client="$NAME" -v ip="$CLIENT_IP" -v ip6="$CLIENT_IP6" -v pub="$PUB" '
    /clients = \{/ {
      print;
      print "      " client " = {";
      print "        address = \"" ip "\";";
      print "        address6 = \"" ip6 "\";";
      print "        publicKey = \"" pub "\";";
      print "      };";
      next;
    }
    { print }
  ' "$NETWORK_FILE" >"${NETWORK_FILE}.tmp" && mv "${NETWORK_FILE}.tmp" "$NETWORK_FILE"

  # Format network.nix
  nix fmt "$NETWORK_FILE" >/dev/null 2>&1 || true
  echo "✓ Registered client '${NAME}' in common/network.nix"

  echo
  echo "======================================================"
  echo "✓ Client '${NAME}' successfully created!"
  echo "======================================================"
  echo "Next steps:"
  echo "  1. Deploy new peer to VPS:  deploy --on shrek"
  echo "  2. View QR code / config:   wg-client ${NAME}"
  echo
  exit 0
fi

# Show existing client profile
CLIENT="$ACTION"

ENDPOINT=$(sops -d --extract '["shrek-public-ip"]' "$SECRETS_FILE" 2>/dev/null || true)
if [ -z "$ENDPOINT" ]; then
  echo "❌ Error: shrek-public-ip not found in secrets/secrets.yaml."
  exit 1
fi

PORT=$(nix eval --impure --expr '(import ./common/network.nix).wireguard.clientPort')
SHREK_PUB=$(nix eval --impure --raw --expr '(import ./common/network.nix).wireguard.shrek.publicKey')
CLIENT_ADDR=$(nix eval --impure --raw --expr "(import ./common/network.nix).wireguard.clients.${CLIENT}.address" 2>/dev/null || true)
CLIENT_ADDR6=$(nix eval --impure --raw --expr "(import ./common/network.nix).wireguard.clients.${CLIENT}.address6" 2>/dev/null || true)
LAN_DNS=$(nix eval --impure --raw --expr '(import ./common/network.nix).hosts.router.ip')
SHREK_DNS=$(nix eval --impure --raw --expr '(import ./common/network.nix).wireguard.shrek.address')

if [ -z "$CLIENT_ADDR" ]; then
  echo "❌ Error: Client '${CLIENT}' not found in common/network.nix wireguard.clients."
  echo
  echo "Available clients:"
  nix eval --impure --json --expr 'builtins.mapAttrs (_: c: c.address) (import ./common/network.nix).wireguard.clients' 2>/dev/null |
    jq -r 'to_entries[] | "  • \(.key)\t(\(.value))"' || true
  echo
  echo "To create it: wg-client add ${CLIENT}"
  exit 1
fi

PRIV=$(sops -d --extract "[\"wireguard\"][\"${CLIENT}-private\"]" "$SECRETS_FILE" 2>/dev/null || true)
if [ -z "$PRIV" ]; then
  echo "======================================================"
  cat <<EOF
[Interface]
PrivateKey = <private-key-from-${CLIENT}>
Address = ${CLIENT_ADDR}/32, ${CLIENT_ADDR6}/128
DNS = ${SHREK_DNS}, ${LAN_DNS}
MTU = 1280

[Peer]
PublicKey = ${SHREK_PUB}
Endpoint = ${ENDPOINT}:${PORT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
  echo "======================================================"
  exit 0
fi

CONF=$(mktemp --suffix=.conf)
trap 'rm -f "$CONF"' EXIT

cat >"$CONF" <<EOF
[Interface]
PrivateKey = ${PRIV}
Address = ${CLIENT_ADDR}/32, ${CLIENT_ADDR6}/128
DNS = ${SHREK_DNS}, ${LAN_DNS}
MTU = 1280

[Peer]
PublicKey = ${SHREK_PUB}
Endpoint = ${ENDPOINT}:${PORT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

echo "======================================================"
echo " WireGuard Client Profile: ${CLIENT}"
echo " Endpoint: ${ENDPOINT}:${PORT}"
echo " Address:  ${CLIENT_ADDR}/32, ${CLIENT_ADDR6}/128"
echo "======================================================"
echo
cat "$CONF"
echo "------------------------------------------------------"

if command -v qrencode >/dev/null 2>&1; then
  echo "Scan this QR code with the WireGuard mobile app:"
  echo
  qrencode -t ansiutf8 <"$CONF"
  echo
else
  echo "💡 Tip: Install qrencode to display a terminal QR code for phone scanning."
fi
