{
  config,
  pkgs,
  lib,
  ...
}:
let
  network = import ../common/network.nix;
  wg = network.wireguard;
in
{
  imports = [
    ../disko.nix
    ../common
    ../modules/network/dhbw-vpn.nix
  ];

  networking.hostName = network.hosts.shrek.hostName;

  # Disk configuration from network inventory (/dev/vda)
  disko.devices.disk.main.device = network.hosts.shrek.disk;

  # Cloud VPS kernel modules
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_scsi"
    "virtio_blk"
    "virtio_net"
    "xen_blkfront"
    "vmw_pvscsi"
    "hv_storvsc"
    "sd_mod"
    "sr_mod"
    "ahci"
    "ata_piix"
    "uhci_hcd"
  ];

  # Enable IP forwarding
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = true;
    "net.ipv4.conf.all.forwarding" = true;
    "net.ipv6.conf.all.forwarding" = true;
  };

  # SOPS secrets for Shrek
  sops.secrets."wireguard/shrek-private" = { };

  services.dhbw-vpn = {
    enable = true;
    redirectHosts = [
      "juris.de"
      "www.juris.de"
      "katalog.bibliothek.kit.edu"
      "db1.inf.dh-karlsruhe.de"
      "db2.inf.dh-karlsruhe.de"
    ];
  };

  networking = {
    useDHCP = true;
    usePredictableInterfaceNames = true;

    firewall = {
      enable = true;
      allowedUDPPorts = [
        wg.port
        wg.clientPort
      ];
      allowedTCPPorts = [ 22 ];
      trustedInterfaces = [ wg.interface ];
      checkReversePath = "loose";

      extraCommands = ''
        # Allow forwarding between wireguard peers (e.g. road-warrior to home LAN)
        iptables -A FORWARD -i ${wg.interface} -o ${wg.interface} -j ACCEPT
        ip6tables -A FORWARD -i ${wg.interface} -o ${wg.interface} -j ACCEPT

        # Road-warrior clients dial UDP ${toString wg.clientPort}; hub still listens on ${toString wg.port}
        iptables -t nat -A PREROUTING -p udp --dport ${toString wg.clientPort} -j REDIRECT --to-ports ${toString wg.port}
        ip6tables -t nat -A PREROUTING -p udp --dport ${toString wg.clientPort} -j REDIRECT --to-ports ${toString wg.port}

        # Clamp MSS to PMTU
        iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -o ${network.hosts.shrek.wanInterface} -j TCPMSS --clamp-mss-to-pmtu
        ip6tables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -o ${network.hosts.shrek.wanInterface} -j TCPMSS --clamp-mss-to-pmtu
      '';
    };

    # NAT: masquerade outgoing traffic from WireGuard out the public WAN interface
    nat = {
      enable = true;
      enableIPv6 = true;
      externalInterface = network.hosts.shrek.wanInterface;
      internalInterfaces = [ wg.interface ];
    };

    wireguard.interfaces.${wg.interface} = {
      ips = [
        "${wg.shrek.address}/24"
        "${wg.shrek.address6}/64"
      ];
      listenPort = wg.port;
      privateKeyFile = config.sops.secrets."wireguard/shrek-private".path;
      mtu = 1420;

      peers = [
        {
          name = "renate";
          publicKey = wg.renate.publicKey;
          allowedIPs = [
            "${wg.renate.address}/32"
            "${wg.renate.address6}/128"
            network.subnet # Route 192.168.10.0/24 to Renate
          ];
        }
      ]
      ++ (lib.mapAttrsToList (name: client: {
        inherit name;
        publicKey = client.publicKey;
        allowedIPs = [
          "${client.address}/32"
          "${client.address6}/128"
        ];
      }) wg.clients);
    };
  };

  systemd.services."wireguard-${wg.interface}".after = [ "sops-nix.service" ];

  # DNS resolver on Shrek
  services.dnsmasq = {
    enable = true;
    settings = {
      interface = wg.interface;
      listen-address = wg.shrek.address;
      bind-interfaces = true;
      # Forward home domain queries to Renate, all others to 1.1.1.1 / 8.8.8.8
      server = [
        "/${network.domain}/${network.hosts.router.ip}"
        "1.1.1.1"
        "8.8.8.8"
      ];
    };
  };

  # Automatic daily upgrade from GitHub
  lab.autoUpgrade.enable = true;

  # SSH hardening against connection spam and brute force
  services.openssh.settings = {
    MaxStartups = "10:30:60"; # Start dropping when >10 unauthenticated connections
    MaxAuthTries = 3;
    LoginGraceTime = 20; # Terminate connection if not authenticated within 20s
  };

  # Fail2ban daemon for automatic SSH bans
  services.fail2ban = {
    enable = true;
    maxretry = 3;
    bantime = "1h";
    bantime-increment.enable = true; # Exponential backoff for repeat bot offenders
    ignoreIP = [
      "127.0.0.1/8"
      network.wireguard.subnet
      network.wireguard.subnet6
      network.subnet
    ];
  };

  environment.systemPackages = with pkgs; [
    wireguard-tools
    tcpdump
    htop
    iftop
  ];
}
