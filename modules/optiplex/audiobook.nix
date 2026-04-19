{ pkgs, ... }:
let
  otelPkgs = ps: with ps; [
    opentelemetry-api
    opentelemetry-sdk
    opentelemetry-exporter-otlp-proto-grpc
  ];

  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    requests
    beautifulsoup4
    lxml
    readability-lxml
  ] ++ otelPkgs ps);

  # Wrap the script as a proper bin so it lands on $PATH with dependencies baked in.
  makeAudiobook = pkgs.writeShellScriptBin "make-audiobook" ''
    exec ${pythonEnv}/bin/python3 ${./audiobook.py} "$@"
  '';
in {
  environment.systemPackages = [
    makeAudiobook
    pkgs.ffmpeg  # provides both ffmpeg and ffprobe
  ];
}
