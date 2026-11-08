{ pkgs, ... }:

{
  devenv.root =
    let
      root = builtins.getEnv "PWD";
    in
    if root != "" then root else "/tmp";

  packages = with pkgs; [
    colmena
    sops
    age
    ssh-to-age
    nixos-anywhere
    mkpasswd
    git
    jq
    wireguard-tools
    qrencode
  ];

  scripts.bootstrap-node.exec = ''
    REPO_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    exec "$REPO_DIR/scripts/bootstrap-node.sh" "$@"
  '';

  scripts.edit-secrets.exec = ''
    REPO_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    export SOPS_AGE_KEY_FILE="''${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
    sops "$REPO_DIR/secrets/secrets.yaml"
  '';

  scripts.set-password.exec = ''
    REPO_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    exec "$REPO_DIR/scripts/set-password.sh" "$@"
  '';

  scripts.deploy.exec = ''
    REPO_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    exec "$REPO_DIR/scripts/deploy.sh" "$@"
  '';

  scripts.flash-bootstick.exec = ''
    REPO_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    exec "$REPO_DIR/scripts/flash-bootstick.sh" "$@"
  '';

  scripts.wg-client.exec = ''
    REPO_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    exec "$REPO_DIR/scripts/wg-client.sh" "$@"
  '';

  scripts.add-wg-client.exec = ''
    REPO_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    exec "$REPO_DIR/scripts/wg-client.sh" add "$@"
  '';

  scripts.fmt.exec = ''
    ${pkgs.nixfmt-tree}/bin/treefmt .
  '';
  enterShell = ''
    export SOPS_AGE_KEY_FILE="''${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
    export EDITOR="''${EDITOR:-nvim}"

    echo "❄️ nix_lab devenv loaded."
    echo "Available helper commands:"
    echo "  set-password [key]         - Interactively set & hash password in secrets.yaml"
    echo "  edit-secrets               - Edit secrets/secrets.yaml with $EDITOR"
    echo "  bootstrap-node <host> <ip> - Provision a fresh node via nixos-anywhere"
    echo "  deploy [-d|--dirty] [...]  - Auto-commit & push to Git, then colmena apply"
    echo "  flash-bootstick [device]   - Build and write headless ISO (e.g. /dev/sda)"
    echo "  wg-client [client]         - Display WireGuard profile & QR code (or list all)"
    echo "  add-wg-client [name]       - Create & encrypt a new WireGuard client"
    echo "  fmt "
  '';
}
