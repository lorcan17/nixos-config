{ ... }:
{
  # Open WebUI as a Docker container alongside Ollama.
  # Accessible at http://optiplex:3080 — Grace can use this for local LLM chat.
  virtualisation.oci-containers.containers.open-webui = {
    image   = "ghcr.io/open-webui/open-webui:main";
    ports   = [ "3080:8080" ];
    volumes = [ "open-webui:/app/backend/data" ];
    environment   = { OLLAMA_BASE_URL = "http://host.docker.internal:11434"; };
    extraOptions  = [ "--add-host=host.docker.internal:host-gateway" ];
  };

  networking.firewall.allowedTCPPorts = [ 3080 ];
}
