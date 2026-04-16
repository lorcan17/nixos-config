{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.btop ];

  services.smartd = {
    enable     = true;
    autodetect = true;
  };

  services.journald.extraConfig = ''
    SystemMaxUse=500M
  '';
}
