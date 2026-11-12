# The NAS's hardware (a Minisforum N5 Pro: AMD, NVMe system disk, SATA
# bays). TODO(2026-11-15): compare with what `nixos-generate-config
# --show-hardware-config` prints on the machine, and take its kernel
# modules if they differ. The file systems are by label, as the install
# makes them (tinytrader-ops' docs/nas-migration-2026-11-15.md, step 1):
# the NVMe's EFI partition labelled `boot`, its root `nixos` (ext4). The
# data disks are ZFS (nixos/nas-pools.nix), never the system disk.
{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "thunderbolt"
    "ahci"
    "usbhid"
    "usb_storage"
    "uas"
    "sd_mod"
  ];
  boot.kernelModules = [ "kvm-amd" ];
  hardware.cpu.amd.updateMicrocode = true;
  hardware.enableRedistributableFirmware = true;

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/boot";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };
}
