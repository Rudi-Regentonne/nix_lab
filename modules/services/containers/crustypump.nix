{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.lab.crustypump;
  databaseUrl = "postgres://crustypump@127.0.0.1:5432/crustypump";
in
{
  options.lab.crustypump = {
    enable = mkEnableOption "CrustyPump heatpump logger and dashboard";

    autoStart = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to auto-start CrustyPump containers on boot";
    };

    heatpumpIp = mkOption {
      type = types.str;
      default = "192.168.189.3";
      description = "Heat pump web UI IP/host:port";
    };

    dashboardPort = mkOption {
      type = types.port;
      default = 8050;
      description = "Localhost port for the CrustyPump dashboard";
    };

    cronExpression = mkOption {
      type = types.str;
      default = "0 * * * * *";
      description = "Six-field cron expression (with seconds) for polling the heat pump";
    };

    dataLocation = mkOption {
      type = types.str;
      default = "/Paul/services/crustypump";
      description = "Host path (ZFS dataset) for CrustyPump dashboard config/data";
    };
  };

  config = mkIf cfg.enable {
    virtualisation.oci-containers.containers = {
      crustypump = {
        image = "ghcr.io/rudi-regentonne/crustypump:0.1.3";
        autoStart = cfg.autoStart;
        environment = {
          HEATPUMP_IP = cfg.heatpumpIp;
          DATABASE_URL = databaseUrl;
          CRON_EXPRESSION = cfg.cronExpression;
          TZ = config.time.timeZone;
        };
        environmentFiles = [ config.sops.templates."crustypump.env".path ];
        extraOptions = [ "--network=host" ];
      };

      crustypump-dashboard = {
        image = "ghcr.io/rudi-regentonne/crustypump-dashboard:0.1.3";
        autoStart = cfg.autoStart;
        environment = {
          DATABASE_URL = databaseUrl;
          DASHBOARD_CONFIG = "/data/layout.json";
          PORT = toString cfg.dashboardPort;
          TZ = config.time.timeZone;
        };
        extraOptions = [ "--network=host" ];
        volumes = [
          "${cfg.dataLocation}/dashboard:/data"
        ];
      };
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataLocation} 0755 root root - -"
      "d ${cfg.dataLocation}/dashboard 0755 root root - -"
    ];

    systemd.services.podman-crustypump = {
      after = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
    };

    systemd.services.podman-crustypump-dashboard = {
      after = [
        "postgresql.service"
        "zfs-mount.service"
      ];
      requires = [ "postgresql.service" ];
      unitConfig.RequiresMountsFor = cfg.dataLocation;
    };
  };
}
