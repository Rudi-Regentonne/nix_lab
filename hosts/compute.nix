{
  config,
  pkgs,
  lib,
  ...
}:
let
  network = import ../common/network.nix;
in
{
  imports = [
    ../disko.nix
    ../common
    ../modules/security/sops-compute.nix
    ../modules/services/databases/postgres.nix
    ../modules/services/databases/valkey.nix
    ../modules/services/network/traefik.nix
    ../modules/services/containers/authentik.nix
    ../modules/services/containers/altero.nix
    ../modules/services/containers/rustdesk-server.nix
    ../modules/services/backup/zotero-backup.nix
    ../modules/services/storage/nas.nix
    ../modules/services/containers/immich.nix
  ];

  networking = {
    hostName = network.hosts.compute.hostName;
    useDHCP = false;

    interfaces.${network.hosts.compute.lanInterface}.ipv4.addresses = [
      {
        address = network.hosts.compute.ip;
        prefixLength = 24;
      }
    ];

    defaultGateway = {
      address = network.gateway;
      interface = network.hosts.compute.lanInterface;
    };

    nameservers = [ network.gateway ];

    firewall = {
      enable = true;
      interfaces.${network.ingressWireguard.interface} = {
        allowedTCPPorts = [ 8080 ] ++ network.rustdesk.tcpPorts;
        allowedUDPPorts = network.rustdesk.udpPorts;
      };
      # Immich is reachable only through the LAN Traefik entrypoint.
      interfaces.${network.hosts.compute.lanInterface}.allowedTCPPorts = [ 80 ];
      checkReversePath = "loose";
    };

    wireguard.interfaces.${network.ingressWireguard.interface} = {
      ips = [ "${network.ingressWireguard.compute.address}/24" ];
      privateKeyFile = config.sops.secrets."wireguard-ingress-private".path;
      mtu = 1420;
      peers = [
        {
          name = "shrek-ingress";
          publicKey = network.ingressWireguard.shrek.publicKey;
          allowedIPs = [ "${network.ingressWireguard.shrek.address}/32" ];
          persistentKeepalive = 25;
        }
      ];
      postSetup = ''
        ENDPOINT=$(cat ${config.sops.secrets."shrek-public-ip".path})
        ${pkgs.wireguard-tools}/bin/wg set ${network.ingressWireguard.interface} \
          peer ${network.ingressWireguard.shrek.publicKey} \
          endpoint "$ENDPOINT:${toString network.ingressWireguard.port}" \
          persistent-keepalive 25
      '';
    };
  };

  disko.devices.disk.main.device = "/dev/sda";

  # NAS and ZFS storage management
  lab.nas = {
    enable = true;
    hostId = "50faf9e4";
    poolName = "Paul";
    arcMaxGiB = 16;
    autoImport = false; # Set to true once drive checks are complete
  };

  # Immich photo and video management (LAN only)
  lab.immich = {
    enable = true;
    autoStart = false; # Set to true once data and DB restore is verified
    acceleration = "nvidia";
  };

  # Container Runtime: Podman with Docker CLI compatibility (like Dominik)
  virtualisation = {
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
    oci-containers.backend = "podman";
  };

  # Unprivileged ports starting at 80 for rootless containers
  boot.kernel.sysctl = {
    "net.ipv4.ip_unprivileged_port_start" = 80;
  };

  # Automatic daily upgrade from GitHub
  lab.autoUpgrade.enable = true;

  environment.systemPackages = with pkgs; [
    podman-compose
    pciutils
    usbutils
    htop
  ];
}
