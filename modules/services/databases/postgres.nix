{ pkgs, ... }:

{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;
    dataDir = "/Paul/services/postgresql/17";
    extensions =
      ps: with ps; [
        vectorchord
        pgvector
        timescaledb
      ];
    enableTCPIP = true;
    ensureDatabases = [
      "authentik"
      "altero"
      "immich"
      "crustypump"
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
      {
        name = "crustypump";
        ensureDBOwnership = true;
      }
    ];

    # Containers use host networking, but PostgreSQL remains inaccessible from
    # the LAN. Passwordless trust is therefore limited to this machine.
    settings = {
      listen_addresses = pkgs.lib.mkForce "127.0.0.1,::1";
      shared_preload_libraries = "vchord.so,timescaledb";
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
      "crustypump"
    ];
    location = "/var/backup/postgresql";
    startAt = "*-*-* 03:00:00";
  };

  systemd.services.postgresql = {
    after = [ "zfs-mount.service" ];
    unitConfig = {
      ConditionPathIsMountPoint = "/Paul/services/postgresql";
    };
  };

  systemd.services.postgresql-crustypump-init = {
    description = "Ensure TimescaleDB extension is enabled in crustypump database";
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
    wantedBy = [ "multi-user.target" ];
    before = [
      "podman-crustypump.service"
      "podman-crustypump-dashboard.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      ExecStart = pkgs.writeShellScript "postgresql-crustypump-init" ''
        set -euo pipefail
        ${pkgs.postgresql_17}/bin/psql -X -d crustypump -c "ALTER EXTENSION timescaledb UPDATE;" 2>/dev/null \
          || ${pkgs.postgresql_17}/bin/psql -X -d crustypump -c "CREATE EXTENSION IF NOT EXISTS timescaledb;"
      '';
    };
  };
}
