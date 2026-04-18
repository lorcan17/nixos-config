{ domain, ... }: {
  services.overseerr.enable = true; # port 5055

  services.caddy.virtualHosts."overseerr.${domain}".extraConfig = ''
    import cloudflare_tls
    reverse_proxy localhost:5055
  '';
}
