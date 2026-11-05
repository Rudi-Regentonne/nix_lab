{
  description = "Homelab Infrastructure: ISO Build, Colmena Provisioning, and SOPS Secrets";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    colmena.url = "github:zhaofengli/colmena";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    devenv = {
      url = "github:cachix/devenv";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko, colmena, sops-nix, devenv }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      devShells.${system}.default = devenv.lib.mkShell {
        inherit inputs pkgs;
        modules = [ ./devenv.nix ];
      };

      nixosConfigurations.headless-bootstick = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          ({ pkgs, ... }: {
            services.openssh.enable = true;
            users.users.qajus = {
              isNormalUser = true;
              extraGroups = [ "wheel" ];
              openssh.authorizedKeys.keys = [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK9XpFuOrdxXr5X2xxLDfcrvw6dKPM1fdjfnpkxrP4iU qajus@Frank"
              ];
            };
            security.sudo.wheelNeedsPassword = false;
            services.getty.autologinUser = pkgs.lib.mkForce "qajus";
            nix.settings = {
              experimental-features = [ "nix-command" "flakes" ];
              trusted-users = [ "root" "qajus" ];
            };
          })
        ];
      };

      nixosConfigurations.router = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          sops-nix.nixosModules.sops
          ./hosts/router
        ];
      };

      nixosConfigurations.k8s-node = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          sops-nix.nixosModules.sops
          ./hosts/k8s-node.nix
        ];
      };

      colmenaHive = colmena.lib.makeHive (import ./deployment/deployment.nix { inherit inputs; });
    };
}
