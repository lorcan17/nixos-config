{ ... }: {
  # radarr/sonarr join transmission group to read /var/lib/transmission/Downloads
  users.users.radarr.extraGroups = [ "transmission" ];
  users.users.sonarr.extraGroups = [ "transmission" ];

  systemd.tmpfiles.rules = [
    "d /var/lib/media/movies                      0755 radarr      radarr      - -"
    "d /var/lib/media/tv                          0755 sonarr      sonarr      - -"
    "d /var/lib/transmission/Downloads/radarr     0755 transmission transmission - -"
    "d /var/lib/transmission/Downloads/sonarr     0755 transmission transmission - -"
  ];
}
