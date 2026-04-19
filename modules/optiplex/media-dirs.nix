{ ... }: {
  # Shared group so transmission, radarr, sonarr, and jellyfin can all
  # read each other's directories without running as the same user.
  users.groups.media = {};

  users.users.transmission.extraGroups = [ "media" ];
  users.users.radarr.extraGroups       = [ "media" ];
  users.users.sonarr.extraGroups       = [ "media" ];
  users.users.jellyfin.extraGroups     = [ "media" ];

  # Persistent media directories — Radarr/Sonarr use these as root folders.
  # Transmission downloads to its own dir; *arr hardlinks into here on import.
  systemd.tmpfiles.rules = [
    "d /var/lib/media          0775 root  media - -"
    "d /var/lib/media/movies   0775 root  media - -"
    "d /var/lib/media/tv       0775 root  media - -"
    "d /var/lib/media/downloads 0775 root media - -"
  ];
}
