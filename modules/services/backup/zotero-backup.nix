{
  config,
  pkgs,
  ...
}:

{
  systemd.tmpfiles.rules = [ "d /var/backup/altero 0700 root root - -" ];

  systemd.services.altero-backup = {
    description = "Back up Altero to WebDAV";
    after = [
      "network-online.target"
      "postgresql.service"
    ];
    wants = [ "network-online.target" ];
    path = with pkgs; [
      coreutils
      postgresql_17
      rclone
      restic
      systemd
      util-linux
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      RuntimeDirectory = "altero-backup";
      RuntimeDirectoryMode = "0700";
    };
    script = ''
      set -euo pipefail

      runtime=/run/altero-backup
      staging=/var/backup/altero
      rclone_config="$runtime/rclone.conf"

      webdav_password_obscured="$(rclone obscure "$(cat ${config.sops.secrets."webdav-password".path})")"
      cat > "$rclone_config" <<EOF
      [webdav]
      type = webdav
      url = $(cat ${config.sops.secrets."webdav-host".path})
      vendor = other
      user = $(cat ${config.sops.secrets."webdav-user".path})
      pass = $webdav_password_obscured
      EOF
      chmod 600 "$rclone_config"

      was_running=0
      if systemctl is-active --quiet podman-altero.service; then
        was_running=1
        systemctl stop podman-altero.service
      fi
      restore_service() {
        if [ "$was_running" -eq 1 ]; then
          systemctl start podman-altero.service
        fi
      }
      trap restore_service EXIT

      runuser -u postgres -- pg_dump --format=custom altero > "$staging/altero.dump"

      export RCLONE_CONFIG="$rclone_config"
      export RESTIC_PASSWORD_FILE=${config.sops.secrets."restic-password".path}
      repository="rclone:webdav:altero-restic"

      if ! restic -r "$repository" snapshots >/dev/null 2>&1; then
        restic -r "$repository" init
      fi

      restic -r "$repository" backup \
        "$staging" \
        /var/lib/altero/storage \
        --tag altero

      restic -r "$repository" forget --prune \
        --keep-daily 7 \
        --keep-weekly 4 \
        --keep-monthly 6 \
        --tag altero
    '';
  };

  systemd.timers.altero-backup = {
    description = "Nightly Altero WebDAV backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "03:30";
      Persistent = true;
      RandomizedDelaySec = "15m";
      Unit = "altero-backup.service";
    };
  };
}
