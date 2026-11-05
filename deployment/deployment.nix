{ inputs, ... }:
let
  network = import ../common/network.nix;
in
{
  meta = {
    nixpkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
    specialArgs = { inherit inputs; };
  };

  router = { ... }: {
    deployment.targetHost = network.hosts.router.ip;
    deployment.targetUser = "qajus";
    imports = [
      inputs.sops-nix.nixosModules.sops
      ../hosts/router
    ];
  };

  k8s-node = { ... }: {
    networking.hostName = network.hosts.k8s-node.hostName;
    disko.devices.disk.main.device = "/dev/sda";
    deployment.targetHost = network.hosts.k8s-node.ip;
    deployment.targetUser = "qajus";
    imports = [
      inputs.sops-nix.nixosModules.sops
      ../hosts/k8s-node.nix
    ];
  };
}
