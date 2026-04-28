{ pkgs, config, domain, ... }:
{
  # Paperless-ngx — document management / OCR inbox.
  # Used as the trigger for the Foundry finance pipeline (statements) and
  # general household paperwork (receipts, contracts, etc).
  #
  # Auto-classification of finance documents is handled by the post-consume
  # hook declared in foundry.nix — Paperless's own matching rules are not used
  # for finance docs because joint accounts confuse OCR-regex classifiers.

  services.paperless = {
    enable      = true;
    address     = "127.0.0.1";
    port        = 28981;
    consumptionDir  = "/var/lib/paperless/consume";
    mediaDir    = "/var/lib/paperless/media";
    dataDir     = "/var/lib/paperless/data";

    # Initial admin password — change after first login. Stored in agenix.
    # passwordFile = config.age.secrets.paperless-admin-password.path;

    settings = {
      PAPERLESS_URL              = "https://paperless.${domain}";
      PAPERLESS_OCR_LANGUAGE     = "eng";
      PAPERLESS_TIME_ZONE        = "America/Vancouver";
      PAPERLESS_CONSUMER_RECURSIVE = true;
      PAPERLESS_CONSUMER_SUBDIRS_AS_TAGS = false;

      # Files re-file automatically when correspondent / custom_fields change.
      # Layout matches statement-extract's archive.py:
      #   originals/<owner>/<correspondent>/<last4>/<created> <title>.pdf
      # Non-finance docs fall back to _unowned / _nolast4 buckets.
      PAPERLESS_FILENAME_FORMAT  = "{custom_fields[owner]:-_unowned}/{{ correspondent }}/{custom_fields[last4]:-_nolast4}/{{ created }} {{ title }}";
      PAPERLESS_FILENAME_FORMAT_REMOVE_NONE = true;

      # Hook script written to /etc by foundry.nix.
      PAPERLESS_POST_CONSUME_SCRIPT = "/etc/paperless/post-consume.sh";
    };
  };

  # Caddy vhost
  services.caddy.virtualHosts."paperless.${domain}".extraConfig = ''
    import cloudflare_tls
    reverse_proxy 127.0.0.1:28981
  '';

  # Uptime Kuma HTTP monitor target — add via UI after first run.
}
