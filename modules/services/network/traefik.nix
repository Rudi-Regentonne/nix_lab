{ ... }:

let
  network = import ../../../common/network.nix;
  authHost = "auth.${network.publicDomain}";
  alteroHost = "altero.${network.publicDomain}";
  hassPublicHost = "hass.${network.publicDomain}";
  immichPublicHost = "immich.${network.publicDomain}";
  immichHost = "immich.${network.domain}";
  hassHost = "hass.${network.domain}";
  z2mHost = "z2m.${network.domain}";
  mealieHost = "mealie.${network.domain}";
  mealiePublicHost = "mealie.${network.publicDomain}";
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
          rule = "Host(`${immichHost}`) || Host(`${immichPublicHost}`)";
          entryPoints = [
            "lan"
            "internal"
          ];
          service = "immich";
        };
        homeassistant = {
          rule = "Host(`${hassHost}`) || Host(`${hassPublicHost}`)";
          entryPoints = [
            "lan"
            "internal"
          ];
          service = "homeassistant";
        };
        zigbee2mqtt = {
          rule = "Host(`${z2mHost}`)";
          entryPoints = [ "lan" ];
          service = "zigbee2mqtt";
        };
        mealie = {
          rule = "Host(`${mealieHost}`) || Host(`${mealiePublicHost}`)";
          entryPoints = [
            "lan"
            "internal"
          ];
          service = "mealie";
        };
      };
      services = {
        authentik.loadBalancer.servers = [ { url = "http://127.0.0.1:9000"; } ];
        altero.loadBalancer.servers = [ { url = "http://127.0.0.1:8000"; } ];
        immich.loadBalancer.servers = [ { url = "http://127.0.0.1:2283"; } ];
        homeassistant.loadBalancer.servers = [ { url = "http://127.0.0.1:8123"; } ];
        zigbee2mqtt.loadBalancer.servers = [ { url = "http://127.0.0.1:8080"; } ];
        mealie.loadBalancer.servers = [ { url = "http://127.0.0.1:9002"; } ];
      };
    };
  };
}
