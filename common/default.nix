{ pkgs, ... }: 
let
  settings = import ./settings.nix;
in {
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.useDHCP = true;

  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  environment.systemPackages = with pkgs; [
    git btop curl wget tmux lf neovim 
  ];

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  users.users."${settings.username}" = {
    isNormalUser = true;
    extraGroups = [ "wheel" ]; 
    hashedPassword = settings.hashedUserPassword;
    openssh.authorizedKeys.keys = [ settings.sshPublicKey ];
  };

  security.sudo.extraRules = [{
    users = [ settings.username ];
    commands = [{
      command = "ALL";
      options = [ "NOPASSWD" ];
    }];
  }];

  # Ensure root can be managed using your trusted laptop key too
  users.users.root.openssh.authorizedKeys.keys = [ settings.sshPublicKey ];

  nix.settings = {
    trusted-users = [ "root" settings.username ];
    trusted-public-keys = [ settings.signingKey ];
  };

  system.stateVersion = "25.11";
}
