{ ... }:

let
  network = import ../../../common/network.nix;
  authHost = "auth.${network.publicDomain}";
  alteroHost = "altero.${network.publicDomain}";
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
      entryPoints.internal = {
        address = "${network.ingressWireguard.compute.address}:8080";
        forwardedHeaders = {
          insecure = false;
          trustedIPs = [ "${network.ingressWireguard.shrek.address}/32" ];
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
      };
      services = {
        authentik.loadBalancer.servers = [ { url = "http://127.0.0.1:9000"; } ];
        altero.loadBalancer.servers = [ { url = "http://127.0.0.1:8000"; } ];
      };
    };
  };
}
