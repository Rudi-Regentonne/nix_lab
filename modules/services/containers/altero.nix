{ config, ... }:

{
  virtualisation.oci-containers.containers.altero = {
    image = "ghcr.io/eseifert/altero:1.0.0-beta.8";
    autoStart = true;
    environment = {
      ALTERO_DATABASE_URL = "postgresql+asyncpg://altero@127.0.0.1:5432/altero";
      ALTERO_PUBLIC_URL = "https://altero.rudiregentonne.de";
      ALTERO_STORAGE_PATH = "/data/storage";
      ALTERO_HOST = "127.0.0.1";
      ALTERO_PORT = "8000";
      ALTERO_FORWARDED_ALLOW_IPS = "127.0.0.1";
      ALTERO_OPEN_REGISTRATION = "false";
    };
    environmentFiles = [ config.sops.templates."altero.env".path ];
    extraOptions = [ "--network=host" ];
    volumes = [ "/var/lib/altero/storage:/data/storage" ];
  };

  systemd.tmpfiles.rules = [ "d /var/lib/altero/storage 0750 10001 10001 - -" ];

  systemd.services.podman-altero = {
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
  };
}
