{ pkgs, domain, ... }: {
  virtualisation.oci-containers.containers.audiobookrequest = {
    image  = "markbeep/audiobookrequest:1";
    ports  = [ "127.0.0.1:8001:8000" ];
    volumes = [ "/var/lib/audiobookrequest:/config" ];
    environment = {
      TZ = "America/Vancouver";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/audiobookrequest 0750 root root - -"
  ];

  services.caddy.virtualHosts."books.${domain}".extraConfig = ''
    import cloudflare_tls
    reverse_proxy localhost:8001
  '';
}
