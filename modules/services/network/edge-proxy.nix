{ lib, pkgs, ... }:

let
  network = import ../../../common/network.nix;
  backend = "http://${network.ingressWireguard.compute.address}:8080";

  proxyLocation =
    {
      rateZone ? null,
      burst ? 100,
      connectionLimit ? null,
    }:
    {
      proxyPass = backend;
      proxyWebsockets = true;
      recommendedProxySettings = false;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Port 443;
        proxy_set_header Forwarded "";

        proxy_connect_timeout 3s;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_intercept_errors on;
        error_page 502 504 =503 @backend_unavailable;

        ${lib.optionalString (
          rateZone != null
        ) "limit_req zone=${rateZone} burst=${toString burst} nodelay;"}
        ${lib.optionalString (
          connectionLimit != null
        ) "limit_conn public_per_ip ${toString connectionLimit};"}
        client_max_body_size 1024m;

        access_log /var/log/nginx/access.log crowdsec;
        access_log /var/log/nginx/access-json.log json_combined;
      '';
    };

  unavailableLocation = {
    extraConfig = ''
      internal;
      default_type text/html;
      add_header Retry-After 60 always;
      return 503 '<!doctype html><html><head><title>Service unavailable</title></head><body><h1>Service temporarily unavailable</h1><p>GRRRRR</p></body></html>';
    '';
  };
in
{
  security.acme = {
    acceptTerms = true;
    defaults.email = network.acmeEmail;
  };

  services.nginx = {
    enable = true;
    package = pkgs.nginxStable;
    recommendedTlsSettings = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = false;

    commonHttpConfig = ''
      log_format crowdsec '$remote_addr - $remote_user [$time_local] "$request_method $uri $server_protocol" $status $body_bytes_sent "$http_referer" "$http_user_agent"';
      log_format json_combined escape=json '{'
        '"time":"$time_iso8601",'
        '"remote_addr":"$remote_addr",'
        '"host":"$host",'
        '"method":"$request_method",'
        '"uri":"$uri",'
        '"status":$status,'
        '"bytes_sent":$body_bytes_sent,'
        '"request_time":$request_time,'
        '"user_agent":"$http_user_agent"'
      '}';

      limit_conn_zone $binary_remote_addr zone=public_per_ip:10m;
      limit_req_status 429;
      limit_conn_status 429;
    '';

    virtualHosts = {
      "_" = {
        default = true;
        rejectSSL = true;
        locations."/".return = "444";
      };

      "auth.${network.publicDomain}" = {
        enableACME = true;
        forceSSL = true;
        locations = {
          # Authentik's SPA requests hundreds of hashed chunks in parallel.
          # CrowdSec and Authentik's own throttles protect these endpoints;
          # nginx only caps concurrent connections here.
          "^~ /static/" = proxyLocation {
            connectionLimit = 200;
          };
          "/" = proxyLocation {
            connectionLimit = 200;
          };
          "@backend_unavailable" = unavailableLocation;
        };
      };

      "altero.${network.publicDomain}" = {
        enableACME = true;
        forceSSL = true;
        locations = {
          # Zotero sync, file transfers, long polling, WebSockets, and the web
          # UI share this endpoint. Generic edge limits break valid clients;
          # CrowdSec remains responsible for blocking abusive addresses.
          "/" = proxyLocation { };
          "@backend_unavailable" = unavailableLocation;
        };
      };
    };
  };
}
