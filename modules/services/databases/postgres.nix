{ pkgs, ... }:

{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;
    enableTCPIP = true;
    ensureDatabases = [
      "authentik"
      "altero"
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
    ];

    # Containers use host networking, but PostgreSQL remains inaccessible from
    # the LAN. Passwordless trust is therefore limited to this machine.
    settings.listen_addresses = pkgs.lib.mkForce "127.0.0.1,::1";
    authentication = pkgs.lib.mkForce ''
      local all all trust
      host  all all 127.0.0.1/32 trust
      host  all all ::1/128      trust
    '';
  };
}
