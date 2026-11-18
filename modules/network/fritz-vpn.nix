{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.fritz-vpn;
  network = import ../../common/network.nix;

  vpncScript = pkgs.writeShellScript "fritz-vpn-vpnc" ''
    set -euo pipefail

    PATH="${
      makeBinPath [
        pkgs.iproute2
        pkgs.coreutils
      ]
    }:$PATH"

    case "''${reason:-}" in
      connect)
        ip link set dev "$TUNDEV" up
        if [ -n "''${INTERNAL_IP4_ADDRESS:-}" ]; then
          plen="''${INTERNAL_IP4_NETMASKLEN:-32}"
          ip addr replace "$INTERNAL_IP4_ADDRESS/$plen" dev "$TUNDEV"
        fi
        ip route replace "${cfg.subnet}" dev "$TUNDEV"
        ;;
      disconnect)
        ip route del "${cfg.subnet}" dev "$TUNDEV" 2>/dev/null || true
        ;;
    esac
  '';
in
{
  options.services.fritz-vpn = {
    enable = mkEnableOption "FritzBox IPsec/Xauth split-tunnel VPN via vpnc";

    interface = mkOption {
      type = types.str;
      default = "fritz0";
      description = "Tunnel interface name.";
    };

    subnet = mkOption {
      type = types.str;
      default = "192.168.178.0/24";
      description = "Remote FritzBox LAN subnet routed through this tunnel.";
    };
  };

  config = mkIf cfg.enable {
    boot.kernelModules = [ "tun" ];

    sops.secrets = {
      "fritz-vpn-gateway".sopsFile = ../../secrets/vpn-shared.yaml;
      "fritz-vpn-id".sopsFile = ../../secrets/vpn-shared.yaml;
      "fritz-vpn-secret".sopsFile = ../../secrets/vpn-shared.yaml;
      "fritz-vpn-username".sopsFile = ../../secrets/vpn-shared.yaml;
      "fritz-vpn-password".sopsFile = ../../secrets/vpn-shared.yaml;
    };

    sops.templates."fritz-vpn.conf" = {
      content = ''
        IPSec gateway ${config.sops.placeholder."fritz-vpn-gateway"}
        IPSec ID ${config.sops.placeholder."fritz-vpn-id"}
        IPSec secret ${config.sops.placeholder."fritz-vpn-secret"}
        Xauth username ${config.sops.placeholder."fritz-vpn-username"}
        Xauth password ${config.sops.placeholder."fritz-vpn-password"}
        IKE Authmode psk
        DPD idle timeout (our side) 60
      '';
      owner = "root";
      group = "root";
      mode = "0400";
      restartUnits = [ "fritz-vpn.service" ];
    };

    systemd.services.fritz-vpn = {
      description = "FritzBox IPsec/Xauth split-tunnel VPN (vpnc)";
      after = [
        "network-online.target"
        "sops-nix.service"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.vpnc}/bin/vpnc --no-detach --local-port 0 --ifname ${cfg.interface} --script ${vpncScript} ${
          config.sops.templates."fritz-vpn.conf".path
        }";
        Restart = "always";
        RestartSec = "15s";
        PrivateTmp = true;
        AmbientCapabilities = "CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE";
        CapabilityBoundingSet = "CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE";
      };
    };

    networking.firewall.trustedInterfaces = [ cfg.interface ];

    networking.firewall.extraCommands = ''
      iptables -A FORWARD -i ${network.wireguard.interface} -o ${cfg.interface} -d ${cfg.subnet} -j ACCEPT
      iptables -A FORWARD -i ${cfg.interface} -o ${network.wireguard.interface} -s ${cfg.subnet} -m state --state ESTABLISHED,RELATED -j ACCEPT
      iptables -t nat -A POSTROUTING -o ${cfg.interface} -d ${cfg.subnet} -j MASQUERADE
      iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -o ${cfg.interface} -j TCPMSS --clamp-mss-to-pmtu
    '';
  };
}
