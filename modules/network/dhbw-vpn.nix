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

  dnsmasqHostsFile = "/run/dhbw-vpn/hosts";

  vpncScript = pkgs.writeShellScript "dhbw-vpn-vpnc" ''
    set -euo pipefail

    PATH="${
      makeBinPath [
        pkgs.iproute2
        pkgs.dnsutils
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.gawk
        pkgs.procps
        pkgs.systemd
      ]
    }:$PATH"

    TABLE="${toString cfg.routingTable}"
    PRIORITY="${toString cfg.rulePriority}"
    HOSTS="${hostsFile}"
    DNS_HOSTS="${dnsmasqHostsFile}"

    reload_dnsmasq() {
      if systemctl is-active --quiet dnsmasq.service 2>/dev/null; then
        systemctl reload dnsmasq.service 2>/dev/null || systemctl kill -s HUP dnsmasq.service 2>/dev/null || true
      elif pgrep -x dnsmasq >/dev/null 2>&1; then
        pkill -HUP -x dnsmasq 2>/dev/null || true
      fi
    }

    flush_split_routes() {
      ip rule show | awk -v table="$TABLE" '
        $0 ~ ("lookup " table "$") {
          for (i = 1; i <= NF; i++) if ($i == "to") { ip = $(i + 1); break }
          if (ip != "") system("ip rule del to " ip " table " table " 2>/dev/null || true")
        }
      '
      ip route flush table "$TABLE" 2>/dev/null || true

      mkdir -p "$(dirname "$DNS_HOSTS")"
      : > "$DNS_HOSTS"
      reload_dnsmasq
    }

    apply_split_routes() {
      flush_split_routes

      BIND=""
      if [ -n "''${INTERNAL_IP4_ADDRESS:-}" ]; then
        BIND="-b $INTERNAL_IP4_ADDRESS"
      fi

      # Send DNS queries through the tun, not WAN/shrek.
      DNS_SERVERS=""
      if [ -n "''${INTERNAL_IP4_DNS:-}" ]; then
        DNS_SERVERS="$INTERNAL_IP4_DNS"
        for dns in $DNS_SERVERS; do
          ip route replace "$dns/32" dev "$TUNDEV" 2>/dev/null || true
        done
      fi
      echo "dhbw-vpn: VPN DNS=''${INTERNAL_IP4_DNS:-none} bind=''${INTERNAL_IP4_ADDRESS:-none}"

      resolve_host() {
        local host="$1"
        local ips=""
        local dns
        for dns in $DNS_SERVERS; do
          ips="$(dig +short +time=2 +tries=2 $BIND "$host" A @"$dns" 2>/dev/null | grep -E '^[0-9.]+$' || true)"
          [ -n "$ips" ] && break
        done
        if [ -z "$ips" ] && [ -n "$BIND" ]; then
          ips="$(dig +short +time=2 +tries=2 $BIND "$host" A 2>/dev/null | grep -E '^[0-9.]+$' || true)"
        fi
        echo "$ips"
      }

      TMP_DNS="$(mktemp)"
      chmod 0644 "$TMP_DNS"

      while IFS= read -r host || [ -n "$host" ]; do
        host="$(echo "$host" | tr -d ' \t\r')"
        [ -z "$host" ] && continue

        ips=""
        attempt=1
        while [ "$attempt" -le 3 ]; do
          ips="$(resolve_host "$host")"
          [ -n "$ips" ] && break
          sleep 1
          attempt=$((attempt + 1))
        done

        if [ -z "$ips" ]; then
          echo "dhbw-vpn: could not resolve $host via VPN DNS" >&2
          continue
        fi

        for ip in $ips; do
          ip route replace "$ip/32" dev "$TUNDEV" table "$TABLE"
          ip rule del to "$ip" table "$TABLE" 2>/dev/null || true
          ip rule add to "$ip" table "$TABLE" priority "$PRIORITY"
          echo "dhbw-vpn: $host -> $ip via $TUNDEV (table $TABLE)"
          echo "$ip $host" >> "$TMP_DNS"
        done
      done < "$HOSTS"

      mkdir -p "$(dirname "$DNS_HOSTS")"
      mv -f "$TMP_DNS" "$DNS_HOSTS"
      reload_dnsmasq
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
        Everything else keeps using the normal internet exit (shrek WAN).
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
      "dhbw-vpn-username".sopsFile = ../../secrets/vpn-shared.yaml;
      "dhbw-vpn-password".sopsFile = ../../secrets/vpn-shared.yaml;
      "dhbw-vpn-2fa-secret".sopsFile = ../../secrets/vpn-shared.yaml;
    };

    systemd.tmpfiles.rules = [
      "d /run/dhbw-vpn 0755 root root -"
      "f /run/dhbw-vpn/hosts 0644 root root -"
    ];

    services.dnsmasq.settings."addn-hosts" = dnsmasqHostsFile;

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
        ExecStartPre = pkgs.writeShellScript "dhbw-vpn-pre" ''
          set -euo pipefail
          mkdir -p "$(dirname "${dnsmasqHostsFile}")"
          : > "${dnsmasqHostsFile}"
          if ${pkgs.systemd}/bin/systemctl is-active --quiet dnsmasq.service 2>/dev/null; then
            ${pkgs.systemd}/bin/systemctl reload dnsmasq.service 2>/dev/null || true
          fi
        '';
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
      iptables -A FORWARD -i ${network.wireguard.interface} -o ${cfg.interface} -j ACCEPT
      iptables -A FORWARD -i ${cfg.interface} -o ${network.wireguard.interface} -m state --state ESTABLISHED,RELATED -j ACCEPT
      iptables -t nat -A POSTROUTING -o ${cfg.interface} -j MASQUERADE
      iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -o ${cfg.interface} -j TCPMSS --clamp-mss-to-pmtu
    '';
  };
}
