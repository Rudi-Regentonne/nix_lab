{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.lab.beszel;
  agentReady = cfg.agent.enable && (cfg.agent.key != null || cfg.agent.environmentFile != null);
in
{
  options.lab.beszel = {
    hub = {
      enable = mkEnableOption "Beszel monitoring hub";

      port = mkOption {
        type = types.port;
        default = 8090;
        description = "Localhost port for Beszel hub";
      };
    };

    agent = {
      enable = mkEnableOption "Beszel monitoring agent";

      port = mkOption {
        type = types.port;
        default = 45876;
        description = "Listen port for Beszel agent";
      };

      key = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Hub SSH public key (copied from the Beszel UI when adding a system).";
      };

      environmentFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Optional EnvironmentFile containing Beszel agent variables such as KEY or TOKEN.";
      };

      smartmon = mkOption {
        type = types.bool;
        default = false;
        description = "Enable SMART disk health monitoring in the Beszel agent.";
      };
    };
  };

  config = mkMerge [
    (mkIf cfg.hub.enable {
      services.beszel.hub = {
        enable = true;
        host = "127.0.0.1";
        port = cfg.hub.port;
      };
    })

    (mkIf cfg.agent.enable {
      # Expose rootful Podman API socket when Podman is enabled so Beszel can
      # inspect container metrics and logs.
      virtualisation.podman.dockerSocket.enable = mkIf config.virtualisation.podman.enable true;

      services.beszel.agent = {
        enable = agentReady;
        openFirewall = false;
        smartmon.enable = cfg.agent.smartmon;
        environmentFile = cfg.agent.environmentFile;
        environment = {
          LISTEN = toString cfg.agent.port;
        }
        // optionalAttrs (cfg.agent.key != null) {
          KEY = cfg.agent.key;
        }
        // optionalAttrs config.virtualisation.podman.enable {
          DOCKER_HOST = "unix:///run/podman/podman.sock";
        };
      };
    })
  ];
}
