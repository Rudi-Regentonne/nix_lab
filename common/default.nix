{ config, pkgs, ... }:

{
  imports = [
    ../modules/security/sops.nix
    ../modules/core/auto-upgrade.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";

  environment.systemPackages = with pkgs; [
    git
    btop
    curl
    wget
    tmux
    lf
    neovim
    age
    sops
  ];

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  # Declarative user management with passwords from SOPS
  users.mutableUsers = false;

  users.users.qajus = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    hashedPasswordFile = config.sops.secrets."user-password-hash".path;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK9XpFuOrdxXr5X2xxLDfcrvw6dKPM1fdjfnpkxrP4iU qajus@Frank"
    ];
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK9XpFuOrdxXr5X2xxLDfcrvw6dKPM1fdjfnpkxrP4iU qajus@Frank"
  ];

  security.sudo.wheelNeedsPassword = false;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "qajus" ];
  };

  system.stateVersion = "25.11";
}
