{ inputs, ... }:
let
  network = import ../common/network.nix;
in
{
  meta = {
    nixpkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
    specialArgs = { inherit inputs; };
  };

  router =
    { ... }:
    {
      deployment.targetHost = network.hosts.router.ip;
      deployment.targetUser = "qajus";
      imports = [
        inputs.sops-nix.nixosModules.sops
        ../hosts/router
      ];
    };

  compute =
    { ... }:
    {
      networking.hostName = network.hosts.compute.hostName;
      disko.devices.disk.main.device = "/dev/sda";
      deployment.targetHost = network.hosts.compute.ip;
      deployment.targetUser = "qajus";
      imports = [
        inputs.disko.nixosModules.disko
        inputs.sops-nix.nixosModules.sops
        ../hosts/compute.nix
      ];
    };
}
