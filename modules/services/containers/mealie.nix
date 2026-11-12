{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.lab.mealie;
in
{
  options.lab.mealie = {
    enable = mkEnableOption "Mealie recipe management and meal planning solution";

    autoStart = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to auto-start Mealie container on boot";
    };

    port = mkOption {
      type = types.port;
      default = 9002;
      description = "Internal port on localhost for Mealie";
    };

    dataLocation = mkOption {
      type = types.str;
      default = "/Paul/services/mealie/data";
      description = "Path on host (e.g. ZFS dataset) to Mealie recipe files, database, and storage";
    };

    image = mkOption {
      type = types.str;
      default = "ghcr.io/mealie-recipes/mealie:latest";
      description = "OCI image for Mealie";
    };
  };

  config = mkIf cfg.enable {
    virtualisation.oci-containers.containers.mealie = {
      image = cfg.image;
      autoStart = cfg.autoStart;
      environment = {
        ALLOW_SIGNUP = "false";
        PUID = "1000";
        PGID = "1000";
        TZ = config.time.timeZone;
        BASE_URL = "https://mealie.rudiregentonne.de";
        API_PORT = toString cfg.port;
        APP_PORT = toString cfg.port;
        PORT = toString cfg.port;
      };
      extraOptions = [ "--network=host" ];
      volumes = [
        "${cfg.dataLocation}:/app/data"
      ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataLocation} 0755 1000 1000 - -"
    ];

    systemd.services.podman-mealie = {
      after = [ "zfs-mount.service" ];
      unitConfig = {
        RequiresMountsFor = cfg.dataLocation;
      };
    };
  };
}
