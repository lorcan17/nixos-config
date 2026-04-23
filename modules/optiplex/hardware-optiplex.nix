{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  # Hardware detected by nixos-generate-config on the OptiPlex 3050 Micro (i7-6700T)
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "usb_storage" "usbhid" "sd_mod" ];
  boot.initrd.kernelModules          = [ ];
  boot.kernelModules                 = [ "kvm-intel" ];
  boot.extraModulePackages           = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/2b14e280-3a90-49f4-ba97-13b3a34b2995";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device  = "/dev/disk/by-uuid/F6CE-5BAD";
    fsType  = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };

  swapDevices = [ { device = "/var/lib/swapfile"; size = 4096; } ];

  nixpkgs.hostPlatform             = "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # UEFI bootloader — systemd-boot picks up kernel/initrd from /boot
  boot.loader.systemd-boot.enable      = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Timezone
  time.timeZone = "America/Vancouver";

  system.stateVersion = "25.05";
}
