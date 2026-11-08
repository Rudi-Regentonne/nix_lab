{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.dhbw-vpn;
  network = import ../../common/network.nix;

  hostFromSpec =
    spec:
    let
      noProto = removePrefix "http://" (removePrefix "https://" spec);
    in
    head (splitString "/" noProto);

  redirectHosts = unique (map hostFromSpec cfg.redirectHosts);

  hostsFile = pkgs.writeText "dhbw-vpn-hosts" (concatStringsSep "\n" redirectHosts);

  vpncScript = pkgs.writeShellScript "dhbw-vpn-vpnc" ''
    set -euo pipefail

    PATH="${
      makeBinPath [
        pkgs.iproute2
        pkgs.dnsutils
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.gawk
      ]
    }:$PATH"

    TABLE="${toString cfg.routingTable}"
    PRIORITY="${toString cfg.rulePriority}"
    HOSTS="${hostsFile}"

    flush_split_routes() {
      ip rule show | awk -v table="$TABLE" '
        $0 ~ ("lookup " table "$") {
          for (i = 1; i <= NF; i++) if ($i == "to") { ip = $(i + 1); break }
          if (ip != "") system("ip rule del to " ip " table " table " 2>/dev/null || true")
        }
      '
      ip route flush table "$TABLE" 2>/dev/null || true
    }

    apply_split_routes() {
      flush_split_routes

      DNS=""
      if [ -n "''${INTERNAL_IP4_DNS:-}" ]; then
        DNS="$(echo "$INTERNAL_IP4_DNS" | awk '{print $1}')"
      fi

      while IFS= read -r host || [ -n "$host" ]; do
        host="$(echo "$host" | tr -d ' \t\r')"
        [ -z "$host" ] && continue

        ips=""
        if [ -n "$DNS" ]; then
          ips="$(dig +short "$host" A @"$DNS" | grep -E '^[0-9.]+$' || true)"
        fi
        if [ -z "$ips" ]; then
          ips="$(getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | sort -u || true)"
        fi
        if [ -z "$ips" ]; then
          echo "dhbw-vpn: could not resolve $host" >&2
          continue
        fi

        for ip in $ips; do
          ip route replace "$ip/32" dev "$TUNDEV" table "$TABLE"
          ip rule del to "$ip" table "$TABLE" 2>/dev/null || true
          ip rule add to "$ip" table "$TABLE" priority "$PRIORITY"
          echo "dhbw-vpn: $host -> $ip via $TUNDEV (table $TABLE)"
        done
      done < "$HOSTS"
    }

    case "''${reason:-}" in
      connect)
        ip link set dev "$TUNDEV" up
        if [ -n "''${INTERNAL_IP4_ADDRESS:-}" ]; then
          plen="''${INTERNAL_IP4_NETMASKLEN:-32}"
          ip addr replace "$INTERNAL_IP4_ADDRESS/$plen" dev "$TUNDEV"
        fi
        apply_split_routes
        ;;
      disconnect)
        flush_split_routes
        ;;
    esac
  '';

  vpnScript = pkgs.writeShellScript "dhbw-vpn-start" ''
    set -euo pipefail

    USER_FILE="${config.sops.secrets."dhbw-vpn-username".path}"
    PASS_FILE="${config.sops.secrets."dhbw-vpn-password".path}"
    TOTP_FILE="${config.sops.secrets."dhbw-vpn-2fa-secret".path}"

    if [[ ! -f "$USER_FILE" || ! -f "$PASS_FILE" || ! -f "$TOTP_FILE" ]]; then
      echo "DHBW VPN secrets not found." >&2
      exit 1
    fi

    USERNAME=$(tr -d '\r\n' < "$USER_FILE")
    PASSWORD=$(tr -d '\r\n' < "$PASS_FILE")
    TOTP_SECRET=$(tr -d ' \t\r\n' < "$TOTP_FILE" | tr '[:lower:]' '[:upper:]')

    if [[ -z "$USERNAME" || -z "$PASSWORD" || -z "$TOTP_SECRET" ]]; then
      echo "DHBW VPN credentials in SOPS are empty." >&2
      exit 1
    fi

    if [[ "$USERNAME" != *"@"* ]]; then
      USERNAME="''${USERNAME}@dh-karlsruhe.de"
    fi

    OTP=$(${pkgs.oath-toolkit}/bin/oathtool --totp -b "$TOTP_SECRET")
    FULL_PASS="''${PASSWORD}''${OTP}"

    echo "Connecting to ${cfg.gateway} as $USERNAME (split-tunnel ${toString (length redirectHosts)} hosts)..."

    exec ${pkgs.openconnect}/bin/openconnect \
      --protocol=anyconnect \
      --non-inter \
      --interface=${cfg.interface} \
      --script="${vpncScript}" \
      --user="$USERNAME" \
      --passwd-on-stdin \
      "${cfg.gateway}" <<< "$FULL_PASS"
  '';
in
{
  options.services.dhbw-vpn = {
    enable = mkEnableOption "DHBW Karlsruhe AnyConnect split-tunnel VPN";

    gateway = mkOption {
      type = types.str;
      default = "https://vpn.dh-karlsruhe.de";
      description = "AnyConnect gateway URL.";
    };

    interface = mkOption {
      type = types.str;
      default = "dhbw0";
      description = "Tunnel interface name.";
    };

    routingTable = mkOption {
      type = types.int;
      default = 1194;
      description = "Policy-routing table for split-tunnel hosts. Must beat WireGuard table 51820 (priority 1000).";
    };

    rulePriority = mkOption {
      type = types.int;
      default = 800;
      description = "ip-rule priority for DHBW destinations (lower than LAN-to-shrek's 1000).";
    };

    redirectHosts = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "https://db1.inf.dh-karlsruhe.de"
      ];
      description = ''
        Hosts or URLs whose traffic is sent through the DHBW VPN.
        Everything else from the LAN keeps using the WireGuard exit to shrek.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.rulePriority < 1000;
        message = "services.dhbw-vpn.rulePriority must be < 1000 so it wins over LAN-to-shrek (priority 1000).";
      }
    ];

    boot.kernelModules = [ "tun" ];

    sops.secrets = {
      "dhbw-vpn-username" = { };
      "dhbw-vpn-password" = { };
      "dhbw-vpn-2fa-secret" = { };
    };

    systemd.services.dhbw-vpn = {
      description = "DHBW Karlsruhe AnyConnect split-tunnel VPN";
      after = [
        "network-online.target"
        "sops-nix.service"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${vpnScript}";
        Restart = "always";
        RestartSec = "15s";
        PrivateTmp = true;
        AmbientCapabilities = "CAP_NET_ADMIN CAP_NET_RAW";
        CapabilityBoundingSet = "CAP_NET_ADMIN CAP_NET_RAW";
      };
    };

    systemd.services.dhbw-vpn-keepalive = {
      description = "Keep DHBW AnyConnect session alive via curl on ${cfg.interface}";
      after = [ "dhbw-vpn.service" ];
      bindsTo = [ "dhbw-vpn.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.curl}/bin/curl --interface ${cfg.interface} -fsS -o /dev/null --max-time 15 https://www.google.com/";
      };
    };

    systemd.timers.dhbw-vpn-keepalive = {
      wantedBy = [ "timers.target" ];
      after = [ "dhbw-vpn.service" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "10min";
        AccuracySec = "30s";
        Persistent = true;
      };
    };

    networking.firewall.trustedInterfaces = [ cfg.interface ];

    networking.firewall.extraCommands = ''
      iptables -A FORWARD -i ${network.hosts.router.lanInterface} -o ${cfg.interface} -j ACCEPT
      iptables -A FORWARD -i ${cfg.interface} -o ${network.hosts.router.lanInterface} -m state --state ESTABLISHED,RELATED -j ACCEPT
      iptables -t nat -A POSTROUTING -o ${cfg.interface} -j MASQUERADE
      iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -o ${cfg.interface} -j TCPMSS --clamp-mss-to-pmtu
    '';
  };
}
