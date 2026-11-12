{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.lab.homeassistant;

  # Default Zigbee2MQTT configuration.yaml
  z2mConfigFile = pkgs.writeText "z2m-configuration.yaml" ''
    homeassistant: true
    permit_join: false
    mqtt:
      base_topic: zigbee2mqtt
      server: mqtt://127.0.0.1:${toString cfg.mqtt.port}
    serial:
      port: ${cfg.zigbee2mqtt.serialPort}
      adapter: ember
    frontend:
      port: ${toString cfg.zigbee2mqtt.port}
      host: 127.0.0.1
    advanced:
      log_level: info
      log_output:
        - console
  '';
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

    image = mkOption {
      type = types.str;
      default = "ghcr.io/home-assistant/home-assistant:stable";
      description = "OCI image for Home Assistant";
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

    zigbee2mqtt = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Zigbee2MQTT container";
      };

      port = mkOption {
        type = types.port;
        default = 8080;
        description = "Frontend port for Zigbee2MQTT web interface";
      };

      dataLocation = mkOption {
        type = types.str;
        default = "/Paul/services/zigbee2mqtt/data";
        description = "Path on host to Zigbee2MQTT data and configuration";
      };

      serialPort = mkOption {
        type = types.str;
        default = "/dev/serial/by-id/usb-Itead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_V2_307d53971174ef11a37be41e313510fd-if00-port0";
        description = "Persistent /dev/serial/by-id path to USB Zigbee adapter (can be moved across USB ports without breaking)";
      };

      image = mkOption {
        type = types.str;
        default = "docker.io/koenkk/zigbee2mqtt:latest";
        description = "OCI image for Zigbee2MQTT";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      # 1. Home Assistant container
      virtualisation.oci-containers.containers.homeassistant = {
        image = cfg.image;
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

    # 3. Zigbee2MQTT container
    (mkIf cfg.zigbee2mqtt.enable {
      virtualisation.oci-containers.containers.zigbee2mqtt = {
        image = cfg.zigbee2mqtt.image;
        autoStart = cfg.autoStart;
        environment = {
          TZ = config.time.timeZone;
        };
        extraOptions = [
          "--network=host"
          "--device=${cfg.zigbee2mqtt.serialPort}:/dev/ttyUSB0"
        ];
        volumes = [
          "${cfg.zigbee2mqtt.dataLocation}:/app/data"
          "/run/udev:/run/udev:ro"
        ];
      };

      systemd.tmpfiles.rules = [
        "d ${cfg.zigbee2mqtt.dataLocation} 0755 root root - -"
      ];

      systemd.services.podman-zigbee2mqtt = {
        after = [
          "zfs-mount.service"
        ]
        ++ optionals cfg.mqtt.enable [ "mosquitto.service" ];
        requires = optionals cfg.mqtt.enable [ "mosquitto.service" ];
        unitConfig = {
          RequiresMountsFor = cfg.zigbee2mqtt.dataLocation;
        };
        preStart = ''
          if [ ! -f "${cfg.zigbee2mqtt.dataLocation}/configuration.yaml" ]; then
            cp "${z2mConfigFile}" "${cfg.zigbee2mqtt.dataLocation}/configuration.yaml"
            chmod 0644 "${cfg.zigbee2mqtt.dataLocation}/configuration.yaml"
          fi
        '';
      };
    })
  ]);
}
