{ config, ... }:

let
  computeSecrets = ../../secrets/compute.yaml;
in
{
  sops = {
    secrets = {
      "authentik-secret-key".sopsFile = computeSecrets;
      "authentik-bootstrap-password".sopsFile = computeSecrets;
      "altero-oidc-client-secret".sopsFile = computeSecrets;
      "webdav-host".sopsFile = computeSecrets;
      "webdav-user".sopsFile = computeSecrets;
      "webdav-password".sopsFile = computeSecrets;
      "restic-password".sopsFile = computeSecrets;
      "smtp-host".sopsFile = computeSecrets;
      "smtp-port".sopsFile = computeSecrets;
      "smtp-username".sopsFile = computeSecrets;
      "smtp-password".sopsFile = computeSecrets;
      "smtp-from".sopsFile = computeSecrets;
      "altero-smtp-url".sopsFile = computeSecrets;
      "shrek-public-ip".sopsFile = computeSecrets;
      "wireguard-ingress-private" = {
        sopsFile = computeSecrets;
        mode = "0400";
      };
    };

    templates."authentik.env" = {
      content = ''
        AUTHENTIK_SECRET_KEY=${config.sops.placeholder."authentik-secret-key"}
        AUTHENTIK_BOOTSTRAP_PASSWORD=${config.sops.placeholder."authentik-bootstrap-password"}
        ALTERO_OIDC_CLIENT_SECRET=${config.sops.placeholder."altero-oidc-client-secret"}
        AUTHENTIK_EMAIL__HOST=${config.sops.placeholder."smtp-host"}
        AUTHENTIK_EMAIL__PORT=${config.sops.placeholder."smtp-port"}
        AUTHENTIK_EMAIL__USERNAME=${config.sops.placeholder."smtp-username"}
        AUTHENTIK_EMAIL__PASSWORD=${config.sops.placeholder."smtp-password"}
        AUTHENTIK_EMAIL__FROM=${config.sops.placeholder."smtp-from"}
        AUTHENTIK_EMAIL__USE_TLS=false
        AUTHENTIK_EMAIL__USE_SSL=true
      '';
      owner = "root";
      group = "root";
      mode = "0400";
      restartUnits = [
        "podman-authentik-server.service"
        "podman-authentik-worker.service"
      ];
    };

    templates."altero.env" = {
      content = ''
        ALTERO_SMTP_URL=${config.sops.placeholder."altero-smtp-url"}
        ALTERO_MAIL_FROM=${config.sops.placeholder."smtp-from"}
      '';
      owner = "root";
      group = "root";
      mode = "0400";
      restartUnits = [ "podman-altero.service" ];
    };
  };
}
