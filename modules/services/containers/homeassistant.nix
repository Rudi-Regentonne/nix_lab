{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.lab.homeassistant;
in
{
  options.lab.homeassistant = {
    enable = mkEnableOption "Home Assistant container";

    autoStart = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to auto-start Home Assistant and related containers on boot";
    };

    port = mkOption {
      type = types.port;
      default = 8123;
      description = "Internal port on localhost for Home Assistant";
    };

    dataLocation = mkOption {
      type = types.str;
      default = "/Paul/services/homeassistant/data";
      description = "Path on host (e.g. ZFS dataset) to Home Assistant storage";
    };

    mqtt = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable native Mosquitto MQTT broker on localhost:1883";
      };

      port = mkOption {
        type = types.port;
        default = 1883;
        description = "Port for Mosquitto MQTT broker";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      # 1. Home Assistant container
      virtualisation.oci-containers.containers.homeassistant = {
        # Literal tag lets Renovate track and update Home Assistant releases.
        image = "ghcr.io/home-assistant/home-assistant:2026.11.2";
        autoStart = cfg.autoStart;
        environment = {
          TZ = config.time.timeZone;
        };
        extraOptions = [
          "--network=host"
          "--privileged"
        ];
        volumes = [
          "${cfg.dataLocation}:/config"
          "/etc/localtime:/etc/localtime:ro"
          "/run/dbus:/run/dbus:ro"
        ];
      };

      systemd.tmpfiles.rules = [
        "d ${cfg.dataLocation} 0755 root root - -"
      ];

      systemd.services.podman-homeassistant = {
        after = [ "zfs-mount.service" ];
        unitConfig = {
          RequiresMountsFor = cfg.dataLocation;
        };
        preStart = ''
                    CFG="${cfg.dataLocation}/configuration.yaml"
                    touch "${cfg.dataLocation}/automations.yaml" \
                          "${cfg.dataLocation}/scripts.yaml" \
                          "${cfg.dataLocation}/scenes.yaml"
                    if [ ! -f "$CFG" ]; then
                      cat <<'EOF' > "$CFG"
          # Loads default set of integrations. Do not remove.
          default_config:

          # Load frontend themes from the themes folder
          frontend:
            themes: !include_dir_merge_named themes

          automation: !include automations.yaml
          script: !include scripts.yaml
          scene: !include scenes.yaml
          EOF
                      chmod 0644 "$CFG"
                    fi
        '';
      };
    }

    # 2. Native Mosquitto MQTT broker
    (mkIf cfg.mqtt.enable {
      services.mosquitto = {
        enable = true;
        listeners = [
          {
            address = "127.0.0.1";
            port = cfg.mqtt.port;
            settings = {
              allow_anonymous = true;
            };
          }
        ];
      };
    })
  ]);
}
