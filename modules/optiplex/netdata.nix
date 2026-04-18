{ pkgs, domain, ... }: {
  services.netdata.enable = true;

  # NixOS packages Netdata's web assets under the store path; without this
  # the daemon serves 404 for every request.
  services.netdata.config.web."web files dir" =
    "${pkgs.netdata}/share/netdata";

  services.caddy.virtualHosts."monitor.${domain}".extraConfig = ''
    import cloudflare_tls
    reverse_proxy localhost:19999
  '';
}
