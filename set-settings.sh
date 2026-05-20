#!/usr/bin/env bash
set -euo pipefail

# Ensure the common directory exists
mkdir -p common

SETTINGS_FILE="common/settings.nix"

# Helper to read existing values from settings.nix if it exists
get_existing_value() {
    local key=$1
    if [[ -f "$SETTINGS_FILE" ]]; then
        # Use awk to find the exact line and extract the value between quotes
        # This is more robust than sed for multiline or repeated matches
        awk -F'"' "/^[[:space:]]*$key[[:space:]]*=[[:space:]]*\"/ {print \$2}" "$SETTINGS_FILE" | head -n 1
    else
        echo ""
    fi
}

echo "===================================================="
echo " NixOS Public-Safe Settings Generator"
echo "===================================================="

# 1. Prompt for Username
echo "Step 1: Enter your Username"
echo "----------------------------------------------------"
EXISTING_USER=$(get_existing_value "username")
if [[ -n "$EXISTING_USER" ]]; then
    read -p "Existing username found: '$EXISTING_USER'. Overwrite? (y/N): " OVERWRITE_USER
    if [[ "$OVERWRITE_USER" =~ ^[Yy]$ ]]; then
        read -p "Enter new username: " NEW_USER
        USERNAME=${NEW_USER:-$EXISTING_USER}
    else
        USERNAME=$EXISTING_USER
    fi
else
    read -p "Enter username: " USERNAME
fi
echo -e "\n✓ Username set to: $USERNAME"
echo "----------------------------------------------------"

# 2. Prompt for Public SSH Key
echo "Step 2: Enter your Public SSH Key"
echo "----------------------------------------------------"
EXISTING_PUBKEY=$(get_existing_value "sshPublicKey")
if [[ -n "$EXISTING_PUBKEY" ]]; then
    echo "Existing SSH Public Key found: '${EXISTING_PUBKEY:0:20}...'"
    read -p "Overwrite? (y/N): " OVERWRITE_PUBKEY
    if [[ "$OVERWRITE_PUBKEY" =~ ^[Yy]$ ]]; then
        read -p "Paste your laptop's public key: " NEW_PUBKEY
        USER_PUBKEY=${NEW_PUBKEY:-$EXISTING_PUBKEY}
    else
        USER_PUBKEY=$EXISTING_PUBKEY
    fi
else
    read -p "Paste your laptop's public key (e.g., ssh-ed25519 AAA...): " USER_PUBKEY
fi

# Basic validation
if [[ ! "$USER_PUBKEY" =~ ^ssh- ]]; then
  echo "❌ Error: That doesn't look like a valid SSH public key string."
  exit 1
fi

echo -e "\n✓ Key captured successfully."
echo "----------------------------------------------------"

# 3. Prompt for Password Hash
echo "Step 3: Generate Secure Password Hash"
echo "----------------------------------------------------"
EXISTING_HASH=$(get_existing_value "hashedUserPassword")
if [[ -n "$EXISTING_HASH" ]]; then
    read -p "Existing password hash found. Generate a new one? (y/N): " OVERWRITE_PASS
    if [[ "$OVERWRITE_PASS" =~ ^[Yy]$ ]]; then
        echo "Please type the new password you want for your user account."
        HASHED_PASSWORD=$(openssl passwd -6)
    else
        HASHED_PASSWORD=$EXISTING_HASH
    fi
else
    echo "Please type the password you want for your user account."
    HASHED_PASSWORD=$(openssl passwd -6)
fi
echo -e "\n✓ Password hash handled."
echo "----------------------------------------------------"

# 4. Prompt for Signing Key
echo "Step 4: Enter your Cache Signing Key (Optional)"
echo "----------------------------------------------------"
EXISTING_SIGNING_KEY=$(get_existing_value "signingKey")
if [[ -n "$EXISTING_SIGNING_KEY" ]]; then
    echo "Existing Signing Key found: '$EXISTING_SIGNING_KEY'"
    read -p "Overwrite? (y/N): " OVERWRITE_SIGNING
    if [[ "$OVERWRITE_SIGNING" =~ ^[Yy]$ ]]; then
        read -p "Enter new signing key (leave empty to skip): " SIGNING_KEY
    else
        SIGNING_KEY=$EXISTING_SIGNING_KEY
    fi
else
    read -p "Enter signing key (optional, e.g. cache:key...): " SIGNING_KEY
fi
echo -e "\n✓ Signing key handled."
echo "----------------------------------------------------"

echo "Generating $SETTINGS_FILE..."

# 5. Write out the clean Nix configuration structure
cat <<EOF >"$SETTINGS_FILE"
{
  username = "$USERNAME";
  sshPublicKey = "$USER_PUBKEY";
EOF

if [[ -n "$SIGNING_KEY" ]]; then
    echo "  signingKey = \"$SIGNING_KEY\";" >> "$SETTINGS_FILE"
fi

cat <<EOF >>"$SETTINGS_FILE"
  hashedUserPassword = "$HASHED_PASSWORD";
}
EOF

echo "===================================================="
echo "✓ Successfully created/updated $SETTINGS_FILE!"
echo "===================================================="
