{ config, pkgs, inputs, ... }: {
  imports = [
    inputs.disko.nixosModules.disko
    ../disko.nix
    ../common
  ];
  environment.systemPackages = with pkgs; [
    sl 
  ];
}
