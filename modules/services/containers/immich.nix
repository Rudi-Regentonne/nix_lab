{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.lab.immich;
  nvidiaEnabled = cfg.acceleration == "nvidia";
  nvidiaMachineLearningEnabled = nvidiaEnabled && cfg.nvidiaMachineLearning;
  gpuOptions = optionals nvidiaEnabled [ "--device=nvidia.com/gpu=all" ];
  machineLearningGpuOptions = optionals nvidiaMachineLearningEnabled [
    "--device=nvidia.com/gpu=all"
  ];
  hardenedOptions = [
    "--network=host"
    "--security-opt=no-new-privileges"
    "--cap-drop=NET_RAW"
  ];
in
{
  options.lab.immich = {
    enable = mkEnableOption "Immich self-hosted photo and video management solution";

    autoStart = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to auto-start Immich containers on boot (set true after database restore)";
    };

    port = mkOption {
      type = types.port;
      default = 2283;
      description = "Internal port on localhost for Immich server";
    };

    mediaLocation = mkOption {
      type = types.str;
      default = "/Paul/services/immich/data";
      description = "Path on host to Immich media files (mapped to /data inside container)";
    };

    acceleration = mkOption {
      type = types.enum [
        "cpu"
        "nvidia"
      ];
      default = "cpu";
      description = "Hardware acceleration backend exposed to the Immich server for transcoding";
    };

    nvidiaMachineLearning = mkOption {
      type = types.bool;
      default = true;
      description = "Use the CUDA machine-learning image when NVIDIA acceleration is enabled";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      virtualisation.oci-containers.containers = {
        immich-server = {
          # Literal tags let Renovate update both Immich images together.
          image = "ghcr.io/immich-app/immich-server:v3.4.1";
          autoStart = cfg.autoStart;
          user = "1000:1000";
          environment = {
            IMMICH_PORT = toString cfg.port;
            IMMICH_HOST = "127.0.0.1";
            DB_URL = "postgresql://immich@127.0.0.1:5432/immich";
            REDIS_HOSTNAME = "127.0.0.1";
            REDIS_PORT = "6379";
            REDIS_DBINDEX = "2";
            IMMICH_MACHINE_LEARNING_URL = "http://127.0.0.1:3003";
          };
          extraOptions = hardenedOptions ++ gpuOptions ++ [ "--shm-size=512m" ];
          volumes = [
            "${cfg.mediaLocation}:/data"
            "/etc/localtime:/etc/localtime:ro"
          ];
        };

        immich-machine-learning = {
          image =
            if nvidiaMachineLearningEnabled then
              "ghcr.io/immich-app/immich-machine-learning:v3.4.1-cuda"
            else
              "ghcr.io/immich-app/immich-machine-learning:v3.4.1";
          autoStart = cfg.autoStart;
          user = "1000:1000";
          environment = {
            IMMICH_PORT = "3003";
            IMMICH_HOST = "127.0.0.1";
            MACHINE_LEARNING_MODEL_REVISION = "v2";
          };
          extraOptions = hardenedOptions ++ machineLearningGpuOptions;
          volumes = [
            "/var/cache/immich-machine-learning:/cache"
          ];
        };
      };

      systemd.tmpfiles.rules = [
        # The media path is deliberately not created here: it must be a mounted
        # ZFS dataset, never an accidental directory on the system disk.
        "d /var/cache/immich-machine-learning 0750 1000 1000 - -"
      ];

      systemd.services.podman-immich-server = {
        after = [
          "postgresql.service"
          "redis-authentik.service"
          "zfs-mount.service"
        ];
        requires = [
          "postgresql.service"
          "redis-authentik.service"
        ];
        unitConfig = {
          RequiresMountsFor = cfg.mediaLocation;
          ConditionPathIsMountPoint = cfg.mediaLocation;
        };
      };
    }

    (mkIf nvidiaEnabled {
      nixpkgs.config.allowUnfree = true;
      services.xserver.videoDrivers = [ "nvidia" ];
      hardware.graphics.enable = true;
      hardware.nvidia = {
        modesetting.enable = true;
        open = false;
        nvidiaSettings = false;
        package = config.boot.kernelPackages.nvidiaPackages.stable;
      };
      hardware.nvidia-container-toolkit.enable = true;
    })
  ]);
}
