#!/usr/bin/env bash
set -euo pipefail

# Define visual output format colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

SETTINGS_FILE="common/settings.nix"
SETUP_SCRIPT="./set-settings.sh"

# --- Pre-flight Check: Ensure Config Settings Exist ---
if [ ! -f "$SETTINGS_FILE" ]; then
  echo -e "${YELLOW}[!] Setup configuration file ($SETTINGS_FILE) not found!${NC}"

  if [ -f "$SETUP_SCRIPT" ]; then
    echo -e "${BLUE}[*] Launching $SETUP_SCRIPT to initialize parameters...${NC}\n"
    # Run the settings script inline so it can capture user keyboard interactions
    "$SETUP_SCRIPT"
  else
    echo "❌ Error: Configuration generator script ($SETUP_SCRIPT) is missing."
    echo "Please create $SETUP_SCRIPT first to populate public credentials cleanly."
    exit 1
  fi
fi

# --- Standard Nix Compilation Steps ---
echo -e "\n${BLUE}[1/3] Ensuring Nix flake dependencies are up to date...${NC}"
nix flake update

echo -e "${BLUE}[2/3] Compiling headless text-installer ISO image...${NC}"
# Compiles your standalone ISO target from the local flake configurations
nix build .#nixosConfigurations.headless-bootstick.config.system.build.isoImage

ISO_PATH=$(ls "$(pwd)/result/iso/"*.iso)

echo -e "${GREEN}[3/3] Build successful!${NC}"
echo "--------------------------------------------------------"
echo "Your ISO file is located here:"
echo "$ISO_PATH"
echo "--------------------------------------------------------"
echo "You can flash it to your USB stick using:"
echo "sudo dd if=\"$ISO_PATH\" of=/dev/sdX status=progress conv=fsync"
echo "--------------------------------------------------------"
