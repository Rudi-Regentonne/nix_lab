{ ... }:

let
  network = import ../../../common/network.nix;
  authHost = "auth.${network.publicDomain}";
  alteroHost = "altero.${network.publicDomain}";
  immichHost = "immich.${network.domain}";
in
{
  services.traefik = {
    enable = true;
    staticConfigOptions = {
      accessLog = {
        format = "json";
        fields = {
          defaultMode = "keep";
          headers = {
            defaultMode = "drop";
            names.User-Agent = "keep";
          };
          queryParameters.defaultMode = "drop";
        };
      };
      entryPoints = {
        internal = {
          address = "${network.ingressWireguard.compute.address}:8080";
          forwardedHeaders = {
            insecure = false;
            trustedIPs = [ "${network.ingressWireguard.shrek.address}/32" ];
          };
        };
        lan = {
          address = "${network.hosts.compute.ip}:80";
        };
      };
    };

    dynamicConfigOptions.http = {
      routers = {
        authentik = {
          rule = "Host(`${authHost}`)";
          entryPoints = [ "internal" ];
          service = "authentik";
        };
        altero = {
          rule = "Host(`${alteroHost}`)";
          entryPoints = [ "internal" ];
          service = "altero";
        };
        immich = {
          rule = "Host(`${immichHost}`)";
          entryPoints = [ "lan" ];
          service = "immich";
        };
      };
      services = {
        authentik.loadBalancer.servers = [ { url = "http://127.0.0.1:9000"; } ];
        altero.loadBalancer.servers = [ { url = "http://127.0.0.1:8000"; } ];
        immich.loadBalancer.servers = [ { url = "http://127.0.0.1:2283"; } ];
      };
    };
  };
}
