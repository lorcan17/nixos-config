{ ... }: {
  services.audiobookshelf = {
    enable = true;
    host   = "127.0.0.1";
    port   = 13378;
    # dataDir (app state/db) defaults to /var/lib/audiobookshelf
  };

  # Media lives separately from app state so it survives service reinstalls.
  # lorcan owns it so the make-audiobook script can write without sudo;
  # group audiobookshelf so the server can read.
  systemd.tmpfiles.rules = [
    "d /var/lib/audiobooks          0775 lorcan audiobookshelf -"
    "d /var/lib/audiobooks/books    0775 lorcan audiobookshelf -"
    "d /var/lib/audiobooks/podcasts 0775 lorcan audiobookshelf -"
  ];

  users.users.lorcan.extraGroups = [ "audiobookshelf" ];

  services.caddy.virtualHosts."abs.{$DOMAIN}".extraConfig = ''
    tls {
      dns cloudflare {$CF_API_TOKEN}
    }
    reverse_proxy localhost:13378
  '';
}
