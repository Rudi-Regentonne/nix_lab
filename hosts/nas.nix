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
    ../common
    ../modules/services/storage/nas.nix
  ];

  networking = {
    hostName = network.hosts.nas.hostName;
    useDHCP = false;

    # Configure interface and IP matching network.hosts.nas.ip (192.168.10.20)
    # interfaces.<lanInterface>.ipv4.addresses = [
    #   {
    #     address = network.hosts.nas.ip;
    #     prefixLength = 24;
    #   }
    # ];
  };

  # Central NAS service configuration
  lab.nas = {
    enable = true;
    # Generate unique hostId for the dedicated NAS: cut -c1-8 /etc/machine-id
    # hostId = "12345678";
    poolName = "Paul";
    arcMaxGiB = 4; # 4 for 8GB RAM host, 8 for 16GB RAM host
    autoImport = true;

    samba = {
      enable = true;
      shares = {
        data = {
          path = "/Paul/data";
          browseable = "yes";
          "read only" = "no";
          "guest ok" = "no";
          "create mask" = "0644";
          "directory mask" = "0755";
        };
      };
    };
  };
}
