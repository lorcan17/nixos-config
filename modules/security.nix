{ ... }:
{
  services.fail2ban = {
    enable     = true;
    maxretry   = 5;
    bantime    = "1h";
    bantime-increment = {
      enable      = true;
      multipliers = "1 2 4 8 16 32 64";
      maxtime     = "168h"; # cap at 1 week
    };
  };

  boot.kernel.sysctl = {
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
  };
}
