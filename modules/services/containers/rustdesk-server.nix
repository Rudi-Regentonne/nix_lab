{ ... }:

let
  network = import ../../../common/network.nix;
  image = "docker.io/rustdesk/rustdesk-server:1.1.16@sha256:8ecdab65deb7c84652a626380e31d11a8f1fbafd97916d57f95c20628f943c00";
  dataDir = "/var/lib/rustdesk-server";
in
{
  virtualisation.oci-containers.containers = {
    rustdesk-hbbs = {
      inherit image;
      autoStart = true;
      cmd = [
        "hbbs"
        "-r"
        "${network.rustdesk.publicHost}:${toString network.rustdesk.relayPort}"
      ];
      extraOptions = [ "--network=host" ];
      volumes = [ "${dataDir}:/root" ];
    };

    rustdesk-hbbr = {
      inherit image;
      autoStart = true;
      cmd = [ "hbbr" ];
      extraOptions = [ "--network=host" ];
      volumes = [ "${dataDir}:/root" ];
    };
  };

  systemd.tmpfiles.rules = [ "d ${dataDir} 0700 root root - -" ];

  systemd.services.podman-rustdesk-hbbs = {
    after = [ "podman-rustdesk-hbbr.service" ];
    wants = [ "podman-rustdesk-hbbr.service" ];
  };
}
