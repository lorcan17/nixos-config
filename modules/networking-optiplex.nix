{ ... }:
{
  networking = {
    hostName = "optiplex";

    # NetworkManager drives DHCP on the wired interface (enp1s0 on this OptiPlex).
    # TODO: switch to a static lease (from the MT6000) or a static IP here once picked.
    networkmanager.enable = true;

    firewall.enable = true;
  };
}
