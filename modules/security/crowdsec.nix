{ lib, pkgs, ... }:

let
  network = import ../../common/network.nix;
  trustedNetworks = {
    name = "local/private-networks";
    description = "Never ban trusted LAN and WireGuard clients";
    whitelist = {
      reason = "Trusted private networks";
      ip = [
        "127.0.0.1"
        "::1"
      ];
      cidr = [
        network.subnet
        network.wireguard.subnet
        network.wireguard.subnet6
        network.ingressWireguard.subnet
      ];
    };
  };
in
{
  services.crowdsec = {
    enable = true;
    autoUpdateService = true;
    hub.collections = [
      "crowdsecurity/linux"
      "crowdsecurity/nginx"
      "crowdsecurity/sshd"
      "crowdsecurity/http-cve"
      "crowdsecurity/whitelist-good-actors"
    ];
    settings = {
      acquisitions = [
        {
          source = "file";
          filenames = [ "/var/log/nginx/access.log" ];
          labels.type = "nginx";
        }
        {
          source = "journalctl";
          journalctl_filter = [ "_SYSTEMD_UNIT=sshd.service" ];
          labels.type = "syslog";
        }
      ];

      parsers.s02Enrich = [ trustedNetworks ];
    };
  };

  services.crowdsec-firewall-bouncer = {
    enable = true;
    registerBouncer.enable = true;
    settings.mode = "iptables";
  };

  users.users.crowdsec = {
    isSystemUser = true;
    group = "crowdsec";
    extraGroups = [
      "nginx"
      "systemd-journal"
    ];
  };
  users.groups.crowdsec = { };

  systemd.services = {
    crowdsec.restartTriggers = [
      (pkgs.writeText "crowdsec-trusted-networks.json" (builtins.toJSON trustedNetworks))
    ];
    crowdsec.serviceConfig.DynamicUser = lib.mkForce false;
    crowdsec-setup.serviceConfig.DynamicUser = lib.mkForce false;
    crowdsec-update-hub.serviceConfig.DynamicUser = lib.mkForce false;
  };
}
