{
  description = "Homelab Infrastructure: ISO Build and Colmena Provisioning";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    colmena.url = "github:zhaofengli/colmena";
  };

  outputs = { self, nixpkgs, disko, colmena }@inputs: {
    nixosConfigurations.headless-bootstick = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
        ({ pkgs, ... }: 
        let
          settings = import ./common/settings.nix;
        in {
          services.openssh.enable = true;
          users.users."${settings.username}" = {
            isNormalUser = true;
            extraGroups = [ "wheel" ];
            openssh.authorizedKeys.keys = [
              settings.sshPublicKey
            ];
            hashedPassword = settings.hashedUserPassword;
          };
          security.sudo.extraRules = [{
            users = [ settings.username ];
            commands = [{
              command = "ALL";
              options = [ "NOPASSWD" ];
            }];
          }];
          services.getty.autologinUser = pkgs.lib.mkForce settings.username;
          nix.settings = {
            trusted-users = [ "root" settings.username ];
            trusted-public-keys = [ settings.signingKey ];
          };
        })
      ];
    };

    nixosConfigurations.k8s-node = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./hosts/k8s-node.nix
      ];
    };

    colmenaHive = colmena.lib.makeHive (import ./deployment/deployment.nix { inherit inputs; });
  };
}
