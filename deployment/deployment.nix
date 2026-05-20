{ inputs, ... }: {
  meta = {
    nixpkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
    specialArgs = { inherit inputs; };
  };

  k8s-node = { ... }: {
    networking.hostName = "node0";
    disko.devices.disk.main.device = "/dev/sda";
    deployment.targetHost = "192.168.10.16";
    deployment.targetUser = (import ../common/settings.nix).username;
    imports = [ ../hosts/k8s-node.nix ];
  };
}
