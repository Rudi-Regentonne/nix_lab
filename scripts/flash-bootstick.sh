#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DEVICE="${1:-}"

echo "======================================================"
echo " NixOS Headless Bootstick Builder & Flasher"
echo "======================================================"

# If no device specified, display available drives to assist the user
if [ -z "$DEVICE" ]; then
  echo "Available block devices:"
  lsblk -d -o NAME,SIZE,TYPE,TRAN,MODEL,RM || true
  echo "------------------------------------------------------"
  read -p "Enter target device to write to (e.g. /dev/sda, or leave empty to just build): " INPUT_DEV
  DEVICE="$INPUT_DEV"
fi

if [ -n "$DEVICE" ]; then
  if [ ! -b "$DEVICE" ]; then
    echo "❌ Error: '$DEVICE' is not a valid block device."
    exit 1
  fi

  # Safety check: prevent overwriting currently mounted system partitions
  if mount | grep -E "^${DEVICE}[0-9p]* " | grep -E " on /(/boot|home)? " >/dev/null 2>&1; then
    echo "❌ SAFETY REFUSAL: '$DEVICE' has active system mounts (root, boot, or home)."
    exit 1
  fi

  echo "Target device details:"
  lsblk "$DEVICE"
  echo "------------------------------------------------------"
  echo "⚠️  WARNING: ALL DATA ON $DEVICE WILL BE PERMANENTLY ERASED!"
  read -p "Type 'YES' to confirm flashing to $DEVICE: " CONFIRM
  if [ "$CONFIRM" != "YES" ]; then
    echo "Flashing aborted."
    exit 0
  fi
fi

echo "=== [1/2] Building Headless Bootstick ISO ==="
nix build .#nixosConfigurations.headless-bootstick.config.system.build.isoImage --out-link result-iso

ISO_FILE=$(find result-iso/iso -name "*.iso" | head -n 1)

if [ -z "$ISO_FILE" ] || [ ! -f "$ISO_FILE" ]; then
  echo "❌ Error: ISO build completed but no .iso file was found."
  exit 1
fi

echo "✓ ISO successfully built: $ISO_FILE"

if [ -n "$DEVICE" ]; then
  echo "=== [2/2] Writing ISO to $DEVICE ==="
  echo "Unmounting any existing partitions on $DEVICE..."
  sudo umount "${DEVICE}"* 2>/dev/null || true

  echo "Flashing ISO to $DEVICE (requires sudo)..."
  sudo dd if="$ISO_FILE" of="$DEVICE" bs=4M status=progress conv=fsync oflag=direct
  sync

  echo "------------------------------------------------------"
  echo "✓ Successfully flashed Headless Bootstick to $DEVICE!"
  echo "You can now safely unplug the USB stick."
else
  echo "------------------------------------------------------"
  echo "✓ ISO ready at $ISO_FILE (not written to any drive)."
  echo "To write later: flash-bootstick /dev/sdX"
fi
