{ ... }: {
  virtualisation.docker = {
    enable    = true;
    autoPrune.enable = true;
  };

  users.users.lorcan.extraGroups = [ "docker" ];
}
