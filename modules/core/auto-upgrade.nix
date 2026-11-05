{ config, lib, pkgs, ... }:

with lib;

{
  options.lab.autoUpgrade = {
    enable = mkEnableOption "Automatic daily NixOS system upgrade from GitHub";
    repo = mkOption {
      type = types.str;
      default = "github:Rudi-Regentonne/nix_lab";
      description = "GitHub repository flake URI";
    };
  };

  config = mkIf config.lab.autoUpgrade.enable {
    system.autoUpgrade = {
      enable = true;
      flake = "${config.lab.autoUpgrade.repo}#${config.networking.hostName}";
      dates = "04:00";
      flags = [ "-L" ];
      allowReboot = false;
    };

    system.activationScripts.logSystemDiff = {
      supportsDryActivation = true;
      text = ''
        if [ -e /run/current-system ] && [ -e "$systemConfig" ]; then
          echo "=== NixOS System Upgrade Diff ==="
          ${pkgs.nvd}/bin/nvd diff /run/current-system "$systemConfig" || true
        fi
      '';
    };
  };
}
