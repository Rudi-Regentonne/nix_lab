{ pkgs, inputs, ... }:

{
  devenv.root =
    let
      root = builtins.getEnv "PWD";
    in
    if root != "" then root else "/tmp";

  packages = with pkgs; [
    inputs.colmena.packages.${pkgs.stdenv.hostPlatform.system}.colmena
    sops
    age
    ssh-to-age
    nixos-anywhere
    mkpasswd
    git
    jq
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

  scripts.check-secrets.exec = ''
    REPO_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    exec "$REPO_DIR/scripts/check-secrets-encrypted.sh"
  '';

  enterShell = ''
    export SOPS_AGE_KEY_FILE="''${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
    export EDITOR="''${EDITOR:-nvim}"

    # Install git pre-commit hook to prevent unencrypted secrets from leaking
    GIT_DIR="$(git rev-parse --git-dir 2>/dev/null || true)"
    if [ -n "$GIT_DIR" ] && [ -d "$GIT_DIR/hooks" ]; then
      cat <<'HOOK' > "$GIT_DIR/hooks/pre-commit"
#!/usr/bin/env bash
REPO_DIR="$(git rev-parse --show-toplevel)"
exec "$REPO_DIR/scripts/check-secrets-encrypted.sh"
HOOK
      chmod +x "$GIT_DIR/hooks/pre-commit"
    fi

    echo "❄️ nix_lab devenv loaded."
    echo "Available helper commands:"
    echo "  set-password [key]         - Interactively set & hash password in secrets.yaml"
    echo "  edit-secrets               - Edit secrets/secrets.yaml with $EDITOR"
    echo "  bootstrap-node <host> <ip> - Provision a fresh node via nixos-anywhere"
    echo "  deploy [-d|--dirty] [...]  - Auto-commit & push to Git, then colmena apply"
    echo "  check-secrets              - Verify all secrets are encrypted"
  '';
}
