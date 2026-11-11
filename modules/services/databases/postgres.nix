{ pkgs, ... }:

{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;
    extensions =
      ps: with ps; [
        vectorchord
        pgvector
      ];
    enableTCPIP = true;
    ensureDatabases = [
      "authentik"
      "altero"
      "immich"
    ];
    ensureUsers = [
      {
        name = "authentik";
        ensureDBOwnership = true;
      }
      {
        name = "altero";
        ensureDBOwnership = true;
      }
      {
        name = "immich";
        ensureDBOwnership = true;
        ensureClauses = {
          superuser = true;
          login = true;
          createdb = true;
        };
      }
    ];

    # Containers use host networking, but PostgreSQL remains inaccessible from
    # the LAN. Passwordless trust is therefore limited to this machine.
    settings = {
      listen_addresses = pkgs.lib.mkForce "127.0.0.1,::1";
      shared_preload_libraries = "vchord.so";
    };
    authentication = pkgs.lib.mkForce ''
      local all all trust
      host  all all 127.0.0.1/32 trust
      host  all all ::1/128      trust
    '';
  };

  services.postgresqlBackup = {
    enable = true;
    databases = [
      "authentik"
      "altero"
      "immich"
    ];
    location = "/var/backup/postgresql";
    startAt = "*-*-* 03:00:00";
  };
}
