{ pkgs, ... }:

{
  # The NixOS Redis module can run the protocol-compatible Valkey package.
  services.redis = {
    package = pkgs.valkey;
    servers.authentik = {
      enable = true;
      bind = "127.0.0.1";
      port = 6379;
      openFirewall = false;
    };
  };
}
