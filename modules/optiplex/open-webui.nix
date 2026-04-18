{ ... }: {
  services.open-webui = {
    enable = true;
    host   = "127.0.0.1";
    port   = 8080;
    environment = {
      OLLAMA_BASE_URL = "http://localhost:11434";
      # Disable auth — Tailscale is the perimeter
      WEBUI_AUTH = "False";
    };
  };

  services.caddy.virtualHosts."chat.{$DOMAIN}".extraConfig = ''
    tls {
      dns cloudflare {$CF_API_TOKEN}
    }
    reverse_proxy localhost:8080
  '';
}
