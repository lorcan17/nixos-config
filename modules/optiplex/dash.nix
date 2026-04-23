{ domain, ... }:
{
  # Dash. — a modern, web-based system dashboard.
  # Available at https://dash.blue-apricots.com

  virtualisation.oci-containers.containers.dashdot = {
    image = "mauricenino/dashdot:latest";
    ports = [ "3002:3001" ]; # Host 3002 -> Container 3001
    volumes = [
      "/:/mnt/host:ro"
    ];
    environment = {
      DASHDOT_ENABLE_CPU_CUSTOM_BURN = "true";
      DASHDOT_SHOW_HOST = "true";
    };
    extraOptions = [
      "--privileged" # Required to read some host hardware stats
    ];
  };

  services.caddy.virtualHosts."dash.${domain}".extraConfig = ''
    import cloudflare_tls
    reverse_proxy localhost:3002
  '';
}
