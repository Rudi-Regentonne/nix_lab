{ config, lib, pkgs, ... }:

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

  # Networking & NAT
  networking = {
    hostName = network.hosts.router.hostName;
    useDHCP = false;

    # WAN Interface
    interfaces.${network.hosts.router.wanInterface}.useDHCP = true;

    # LAN Interface
    interfaces.${network.hosts.router.lanInterface} = {
      ipv4.addresses = [{
        address = network.hosts.router.ip;
        prefixLength = 24;
      }];
    };

    # Network Address Translation (NAT)
    nat = {
      enable = true;
      externalInterface = network.hosts.router.wanInterface;
      internalInterfaces = [ network.hosts.router.lanInterface ];
    };

    # Firewall Settings
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 80 8082 ];
      trustedInterfaces = [ network.hosts.router.lanInterface ];

      extraCommands = ''
        iptables -D FORWARD -i ${network.hosts.router.lanInterface} -o ${network.hosts.router.wanInterface} -j ACCEPT 2>/dev/null || true
        iptables -D FORWARD -i ${network.hosts.router.wanInterface} -o ${network.hosts.router.lanInterface} -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true

        iptables -A FORWARD -i ${network.hosts.router.lanInterface} -o ${network.hosts.router.wanInterface} -j ACCEPT
        iptables -A FORWARD -i ${network.hosts.router.wanInterface} -o ${network.hosts.router.lanInterface} -m state --state ESTABLISHED,RELATED -j ACCEPT
      '';
    };
  };

  # DNS via Dnsmasq - dynamically populated from network.hosts
  services.dnsmasq = {
    enable = true;
    settings = {
      interface = network.hosts.router.lanInterface;
      listen-address = network.hosts.router.ip;
      bind-interfaces = true;
      server = [ "1.1.1.1" "8.8.8.8" ];

      # Automatically generate DNS records for all hosts in the network inventory
      address = [
        "/router.${network.domain}/${network.hosts.router.ip}"
      ] ++ (lib.mapAttrsToList (_: host:
        "/${host.hostName}.${network.domain}/${host.ip}"
      ) network.hosts);
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
          reservations = lib.filter (x: x != null) (lib.mapAttrsToList (_: host:
            if host ? mac then {
              hw-address = host.mac;
              ip-address = host.ip;
              hostname = host.hostName;
            } else null
          ) network.hosts);
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
    listenPort = 80;
    services = [
      {
        "Network Infrastructure" = [
          {
            "Renate Router" = {
              icon = "nixos.png";
              href = "http://router.${network.domain}";
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

  system.stateVersion = "25.11";
}
