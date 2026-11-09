{
  config,
  lib,
  pkgs,
  ...
}:

let
  network = import ../../common/network.nix;
in
{
  imports = [
    ./hardware-configuration.nix
    ../../common
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Core Kernel Routing
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = true;
    "net.ipv4.ip_forward" = true;
  };

  # SOPS secrets for WireGuard exit tunnel
  sops.secrets."wireguard/renate-private" = { };
  sops.secrets."shrek-public-ip" = { };

  # Networking & NAT
  networking = {
    hostName = network.hosts.router.hostName;
    useDHCP = false;

    # WAN Interface (physical upstream connection)
    interfaces.${network.hosts.router.wanInterface}.useDHCP = true;

    # LAN Interface
    interfaces.${network.hosts.router.lanInterface} = {
      ipv4.addresses = [
        {
          address = network.hosts.router.ip;
          prefixLength = 24;
        }
      ];
    };

    # WireGuard Exit Tunnel to Shrek (VPS)
    wireguard.interfaces.${network.wireguard.interface} = {
      ips = [
        "${network.wireguard.renate.address}/24"
        "${network.wireguard.renate.address6}/64"
      ];
      privateKeyFile = config.sops.secrets."wireguard/renate-private".path;
      allowedIPsAsRoutes = false; # Handled via custom policy routing table 51820
      mtu = 1420;

      peers = [
        {
          name = "shrek";
          publicKey = network.wireguard.shrek.publicKey;
          allowedIPs = [ "0.0.0.0/0" ];
          persistentKeepalive = 25;
        }
      ];

      postSetup = ''
        # Set dynamic endpoint from decrypted sops secret
        if [ -f "${config.sops.secrets."shrek-public-ip".path}" ]; then
          ENDPOINT=$(cat "${config.sops.secrets."shrek-public-ip".path}")
          if [ -n "$ENDPOINT" ]; then
            ${pkgs.wireguard-tools}/bin/wg set ${network.wireguard.interface} peer ${network.wireguard.shrek.publicKey} endpoint "$ENDPOINT:${toString network.wireguard.port}" persistent-keepalive 25
          fi
        fi

        # Route LAN traffic via Shrek over WireGuard in table 51820
        ip route replace default via ${network.wireguard.shrek.address} dev ${network.wireguard.interface} table 51820
        ip route replace unreachable default metric 1000 table 51820

        # Policy routing rules
        ip rule del table 51820 2>/dev/null || true
        ip rule del to ${network.subnet} table main 2>/dev/null || true
        ip rule del to ${network.wireguard.subnet} table main 2>/dev/null || true

        # Keep LAN-to-LAN and WireGuard subnet in table main
        ip rule add to ${network.subnet} table main priority 900
        ip rule add to ${network.wireguard.subnet} table main priority 901

        # Direct all home LAN traffic to the WireGuard exit table
        ip rule add from ${network.subnet} table 51820 priority 1000
      '';

      postShutdown = ''
        ip rule del table 51820 2>/dev/null || true
        ip rule del to ${network.subnet} table main 2>/dev/null || true
        ip rule del to ${network.wireguard.subnet} table main 2>/dev/null || true
        ip route flush table 51820 2>/dev/null || true
      '';
    };

    # Firewall Settings
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22
        8082
      ];
      trustedInterfaces = [
        network.hosts.router.lanInterface
        network.wireguard.interface
      ];
      checkReversePath = "loose";

      extraCommands = ''
        # Allow forwarding between home LAN and WireGuard exit tunnel
        iptables -A FORWARD -i ${network.hosts.router.lanInterface} -o ${network.wireguard.interface} -j ACCEPT
        iptables -A FORWARD -i ${network.wireguard.interface} -o ${network.hosts.router.lanInterface} -m state --state ESTABLISHED,RELATED -j ACCEPT

        # Allow remote road-warrior VPN clients on WireGuard to access home LAN
        iptables -A FORWARD -i ${network.wireguard.interface} -o ${network.hosts.router.lanInterface} -s ${network.wireguard.subnet} -d ${network.subnet} -j ACCEPT

        # Prevent un-tunneled internet leaks from LAN out physical WAN
        iptables -A FORWARD -i ${network.hosts.router.lanInterface} -o ${network.hosts.router.wanInterface} -j REJECT --reject-with icmp-net-unreachable

        # Clamp MSS to PMTU over WireGuard
        iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -o ${network.wireguard.interface} -j TCPMSS --clamp-mss-to-pmtu
      '';
    };
  };

  systemd.services."wireguard-${network.wireguard.interface}".after = [ "sops-nix.service" ];

  # DNS via Dnsmasq - dynamically populated from network.hosts
  services.dnsmasq = {
    enable = true;
    settings = {
      interface = network.hosts.router.lanInterface;
      listen-address = network.hosts.router.ip;
      bind-interfaces = true;
      # Prefer Shrek DNS over encrypted WireGuard tunnel, fallback to 1.1.1.1
      server = [
        network.wireguard.shrek.address
        "1.1.1.1"
      ];

      # Automatically generate DNS records for all hosts in the network inventory
      address = [
        "/router.${network.domain}/${network.hosts.router.ip}"
      ]
      ++ (lib.mapAttrsToList (_: host: "/${host.hostName}.${network.domain}/${host.ip}") network.hosts);
    };
  };

  # DHCP via Kea - automatically maps static MAC leases from network.hosts
  services.kea.dhcp4 = {
    enable = true;
    settings = {
      interfaces-config = {
        interfaces = [ network.hosts.router.lanInterface ];
      };
      lease-database = {
        type = "memfile";
        persist = true;
        name = "/var/lib/kea/dhcp4.leases";
      };
      subnet4 = [
        {
          id = 1;
          subnet = network.subnet;
          pools = [
            { pool = "192.168.10.100 - 192.168.10.250"; }
          ];
          option-data = [
            {
              name = "routers";
              data = network.hosts.router.ip;
            }
            {
              name = "domain-name-servers";
              data = network.hosts.router.ip;
            }
          ];
          # Automatically assign static IPs to any device that defines a MAC in network.hosts
          reservations = lib.filter (x: x != null) (
            lib.mapAttrsToList (
              _: host:
              if host ? mac then
                {
                  hw-address = host.mac;
                  ip-address = host.ip;
                  hostname = host.hostName;
                }
              else
                null
            ) network.hosts
          );
        }
      ];
    };
  };

  console = {
    font = "Lat2-Terminus16";
    keyMap = "de";
    useXkbConfig = false;
  };

  environment.systemPackages = with pkgs; [
    tcpdump
    nmap
    ethtool
  ];

  # Dashboard
  services.homepage-dashboard = {
    enable = true;
    listenPort = 8082;
    allowedHosts = "renate.${network.domain},renate.${network.domain}:8082,router.${network.domain},router.${network.domain}:8082,${network.hosts.router.ip},${network.hosts.router.ip}:8082,localhost:8082,127.0.0.1:8082";
    services = [
      {
        "Network Infrastructure" = [
          {
            "Renate Router" = {
              icon = "nixos.png";
              href = "http://router.${network.domain}:8082";
              description = "NixOS Core Router";
            };
          }
          {
            "Dell Core Switch" = {
              icon = "dell.png";
              href = "http://${network.hosts.switch.ip}";
              description = "PowerConnect 2724";
            };
          }
        ];
      }
    ];

    widgets = [
      {
        resources = {
          cpu = true;
          disk = "/";
          memory = true;
        };
      }
    ];
  };

  # Automatic daily upgrade from GitHub
  lab.autoUpgrade.enable = true;

  system.stateVersion = "25.11";
}
