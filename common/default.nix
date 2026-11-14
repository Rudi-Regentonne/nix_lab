{ config, pkgs, ... }:

{
  imports = [
    ../modules/security/sops.nix
    ../modules/core/auto-upgrade.nix
    ../modules/services/monitoring/beszel.nix
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
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      "qajus"
    ];
  };

  # Monitoring agent across all hosts. Paste the hub public key from
  # http://beszel.home ("Add System") to start the agents.
  lab.beszel.agent = {
    enable = true;
    key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGlu0jVpPa1S4s10pjkdULOJ/uW5yOShIn2dZSVo+tVp";
  };

  system.stateVersion = "25.11";
}
