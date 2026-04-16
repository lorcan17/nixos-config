{ ... }:
{
  # agenix secret declarations for the OptiPlex.
  # Secrets are decrypted at activation using the host's SSH key.
  # Encrypted .age files live in secrets/ — never commit plaintext.
  #
  # Workflow: edit secrets/secrets.nix to add public keys, then:
  #   cd ~/nix-config/secrets && agenix -e secret-name.age

  age.secrets = {
    fmp-api-key = {
      file = ../secrets/fmp-api-key.age;
      mode = "0400";
    };
  };
}
