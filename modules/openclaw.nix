{ ... }:
{
  # REPLACE: add the OpenClaw container config once you have the details.
  # Example structure:
  #
  # virtualisation.oci-containers.containers.openclaw = {
  #   image   = "openclaw/gateway:latest";
  #   ports   = [ "8080:8080" ];
  #   volumes = [
  #     "/home/lorcan/openclaw:/data"
  #     "/home/lorcan/obsidian:/obsidian:ro"  # read-only vault access
  #   ];
  #   environment    = { OLLAMA_URL = "http://host.docker.internal:11434"; };
  #   extraOptions   = [ "--add-host=host.docker.internal:host-gateway" ];
  # };
  #
  # networking.firewall.allowedTCPPorts = [ 8080 ];
}
