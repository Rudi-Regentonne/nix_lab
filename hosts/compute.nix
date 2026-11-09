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
  ];

  networking.hostName = network.hosts.compute.hostName;
  disko.devices.disk.main.device = "/dev/sda";
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
