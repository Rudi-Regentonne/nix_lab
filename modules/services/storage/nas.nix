{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.lab.nas;
in
{
  options.lab.nas = {
    enable = mkEnableOption "NAS storage, ZFS pool management, and file sharing";

    hostId = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "32-bit hexadecimal host ID for ZFS splat protection (e.g. first 8 chars of /etc/machine-id)";
    };

    poolName = mkOption {
      type = types.str;
      default = "Paul";
      description = "Primary ZFS pool name to manage";
    };

    autoImport = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically import the primary pool on boot via boot.zfs.extraPools";
    };

    arcMaxGiB = mkOption {
      type = types.nullOr types.int;
      default = null;
      description = "Maximum ZFS ARC memory size in GiB (e.g., 16 on 64GB compute host, 4-8 on dedicated NAS)";
    };

    autoScrub = mkOption {
      type = types.bool;
      default = true;
      description = "Enable periodic automatic scrub of the managed pool";
    };

    autoTrim = mkOption {
      type = types.bool;
      default = true;
      description = "Enable periodic TRIM for SSD vdevs in the pool";
    };

    smartd = mkOption {
      type = types.bool;
      default = true;
      description = "Enable SMART daemon for drive health monitoring";
    };

    samba = {
      enable = mkEnableOption "Samba SMB file sharing";

      workgroup = mkOption {
        type = types.str;
        default = "WORKGROUP";
        description = "Samba workgroup name";
      };

      serverString = mkOption {
        type = types.str;
        default = "${cfg.poolName} NAS";
        description = "Samba server description string";
      };

      netbiosName = mkOption {
        type = types.str;
        default = "${cfg.poolName}-NAS";
        description = "Samba NetBIOS name";
      };

      wsdd = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Web Services Dynamic Discovery (WSDD) for Windows/macOS network browsing";
      };

      shares = mkOption {
        type = types.attrsOf (types.attrsOf types.anything);
        default = { };
        example = literalExpression ''
          {
            data = {
              path = "/Paul/data";
              browseable = "yes";
              "read only" = "no";
              "guest ok" = "no";
              "create mask" = "0644";
              "directory mask" = "0755";
            };
          }
        '';
        description = "Samba share definitions";
      };
    };

    nfs = {
      enable = mkEnableOption "NFS kernel server file exports";

      exports = mkOption {
        type = types.lines;
        default = "";
        example = ''
          /Paul/data 192.168.10.0/24(rw,sync,no_subtree_check)
        '';
        description = "Contents of /etc/exports";
      };
    };
  };

  config = mkIf cfg.enable {
    # 1. ZFS kernel and userland support
    boot.supportedFilesystems = [ "zfs" ];
    boot.zfs.forceImportRoot = mkDefault false;

    networking.hostId = mkIf (cfg.hostId != null) (mkDefault cfg.hostId);

    boot.zfs.extraPools = mkIf cfg.autoImport [ cfg.poolName ];

    boot.extraModprobeConfig = optionalString (cfg.arcMaxGiB != null) ''
      options zfs zfs_arc_max=${toString (cfg.arcMaxGiB * 1024 * 1024 * 1024)}
    '';

    # 2. Automated storage maintenance
    services.zfs.autoScrub = mkIf cfg.autoScrub {
      enable = true;
      interval = "monthly";
      pools = [ cfg.poolName ];
    };

    services.zfs.trim = mkIf cfg.autoTrim {
      enable = true;
      interval = "weekly";
    };

    # 3. Disk health diagnostics and monitoring
    services.smartd = mkIf cfg.smartd {
      enable = true;
    };

    environment.systemPackages = [
      pkgs.smartmontools
      pkgs.zfs
    ];

    # 4. Samba (SMB) sharing and discovery
    services.samba = mkIf cfg.samba.enable {
      enable = true;
      openFirewall = true;
      settings = {
        global = {
          "workgroup" = cfg.samba.workgroup;
          "server string" = cfg.samba.serverString;
          "netbios name" = cfg.samba.netbiosName;
          "security" = "user";
          "ea support" = "yes";
          "vfs objects" = "acl_xattr fruit streams_xattr";
        };
      }
      // cfg.samba.shares;
    };

    services.samba-wsdd = mkIf (cfg.samba.enable && cfg.samba.wsdd) {
      enable = true;
      openFirewall = true;
    };

    # 5. NFS sharing
    services.nfs.server = mkIf cfg.nfs.enable {
      enable = true;
      exports = cfg.nfs.exports;
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.nfs.enable [ 2049 ];
    networking.firewall.allowedUDPPorts = mkIf cfg.nfs.enable [ 2049 ];
  };
}
