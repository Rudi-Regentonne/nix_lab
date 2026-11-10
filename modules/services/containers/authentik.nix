{ config, ... }:

let
  image = "ghcr.io/goauthentik/server:2026.8.5";
  commonEnvironment = {
    AUTHENTIK_REDIS__HOST = "127.0.0.1";
    AUTHENTIK_REDIS__PORT = "6379";
    AUTHENTIK_REDIS__DB = "1";
    AUTHENTIK_POSTGRESQL__HOST = "127.0.0.1";
    AUTHENTIK_POSTGRESQL__PORT = "5432";
    AUTHENTIK_POSTGRESQL__USER = "authentik";
    AUTHENTIK_POSTGRESQL__NAME = "authentik";
    AUTHENTIK_BOOTSTRAP_EMAIL = "admin@rudiregentonne.de";
  };
  commonOptions = [
    "--network=host"
    "--shm-size=512m"
  ];
  commonVolumes = [
    "/var/lib/authentik/media:/media"
    "${./blueprints/altero.yaml}:/blueprints/custom/altero.yaml:ro"
  ];
in
{
  virtualisation.oci-containers.containers = {
    authentik-server = {
      inherit image;
      autoStart = true;
      cmd = [ "server" ];
      environment = commonEnvironment // {
        AUTHENTIK_LISTEN__HTTP = "127.0.0.1:9000";
        AUTHENTIK_LISTEN__HTTPS = "127.0.0.1:9443";
        AUTHENTIK_LISTEN__METRICS = "127.0.0.1:9300";
        AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS = "127.0.0.1/32,::1/128";
      };
      environmentFiles = [ config.sops.templates."authentik.env".path ];
      extraOptions = commonOptions;
      volumes = commonVolumes;
    };

    authentik-worker = {
      inherit image;
      autoStart = true;
      cmd = [ "worker" ];
      environment = commonEnvironment // {
        AUTHENTIK_LISTEN__HTTP = "127.0.0.1:9003";
        AUTHENTIK_LISTEN__METRICS = "127.0.0.1:9302";
      };
      environmentFiles = [ config.sops.templates."authentik.env".path ];
      extraOptions = commonOptions;
      volumes = commonVolumes;
    };
  };

  systemd.tmpfiles.rules = [ "d /var/lib/authentik/media 0750 root root - -" ];

  systemd.services = {
    podman-authentik-server = {
      after = [
        "postgresql.service"
        "redis-authentik.service"
      ];
      requires = [
        "postgresql.service"
        "redis-authentik.service"
      ];
    };
    podman-authentik-worker = {
      after = [
        "postgresql.service"
        "redis-authentik.service"
      ];
      requires = [
        "postgresql.service"
        "redis-authentik.service"
      ];
    };
  };
}
