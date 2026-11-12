# The NAS (NixOS): a Minisforum N5 Pro, the store's disks and the data
# services, from 2026-11-15. nixosConfigurations.nas in flake.nix.
#
# What of tinytrader runs here is tinytrader-ops' role
# (nixosModules.nas: the store, alpaca-history, databento-jobs, the
# recorders and the store's batch jobs, as systemd units, wherever its
# placement map puts them), not this file. This file is the machine: ZFS
# and its pools (nixos/nas-pools.nix), Tailscale and SSH by key only
# (system/common.nix), sops-nix with the host key, chrony, node_exporter,
# auto-deploy, and no desktop.
#
#   nixos-rebuild switch --flake ~/repos/nix-config#nas --sudo
#     (on the NAS, as daws: builds as you, so the private tinytrader-ops and
#     nix-secrets inputs are fetched with your GitHub login, then activates
#     as root; as scripts/switch does on a Mac)
#
# Installing it: tinytrader-ops' docs/nas-migration-2026-11-15.md.
{ config, pkgs, ... }:
{
  imports = [
    # Nix with flakes, Docker, never sleeping (nixos/common.nix); tools,
    # Tailscale, SSH by key only, sops-nix's host key, the timezone
    # (system/common.nix).
    ./common.nix
    ./nas-hardware.nix
    ./nas-pools.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";

  # Its tailnet name follows the hostname.
  networking.hostName = "nas";
  # ZFS refuses to import a pool last used by another host id: this
  # machine's, fixed here (random, made once; never change it).
  networking.hostId = "0688d4cc";

  # ZFS for the data disks; the system disk is ext4 (nixos/nas-hardware.nix).
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;
  # Checksums are verified on every read; a scrub reads everything, monthly.
  services.zfs.autoScrub = {
    enable = true;
    interval = "monthly";
  };
  # Snapshots of every dataset with com.sun:auto-snapshot=true (each volume:
  # nixos/nas-pools.nix): against a deletion or overwrite, not a disk's loss.
  # The store's objects are written once, so these cost little beyond what
  # the store deletes (kept until the last snapshot naming it expires).
  services.zfs.autoSnapshot = {
    enable = true;
    flags = "-k -p --utc";
    frequent = 4;
    hourly = 24;
    daily = 7;
    weekly = 4;
    monthly = 6;
  };

  # The disks: one pool each (nixos/nas-pools.nix). TODO(2026-11-15): each
  # disk's /dev/disk/by-id path (`ls -l /dev/disk/by-id` on the NAS), each
  # volume's id (made when its dataset is: tinytrader-ops'
  # docs/nas-migration-2026-11-15.md), then enable = true as each pool is
  # made. Until then none is imported and the store has no volumes.
  local.nas.pools = {
    # The new 20-24 TB drive: the first copy of everything. Until the store
    # can migrate to its content-addressed layout (tinytrader decision 0035,
    # `store migrate-cas`), each old drive's tree is copied as it is, to a
    # volume of its own; with it, this pool holds one volume, tt04.
    tt04 = {
      enable = false;
      description = "the 20-24 TB drive (new)";
      disks = [ "/dev/disk/by-id/TODO-the-20-24TB-drive" ];
      volumes = {
        tt04-data.id = "TODO-tt04-data";
        tt04-tt03.id = "TODO-tt04-tt03";
        tt04-newdrive.id = "TODO-tt04-newdrive";
      };
    };
    # The M2's drives, re-made as ZFS only once tt-fsck (or, until it
    # exists, the copy's verification) passes on their copies on tt04:
    # second copies of everything (tt03), third copies of irreplaceable data
    # (data, newdrive).
    tt03 = {
      enable = false;
      description = "Seagate IronWolf 8 TB (tt03)";
      disks = [ "/dev/disk/by-id/TODO-ata-ST8000VN004-tt03" ];
      volumes.tt03.id = "TODO-tt03";
    };
    data = {
      enable = false;
      description = "the 1 TB Data drive, the original archive";
      disks = [ "/dev/disk/by-id/TODO-data-1TB" ];
      volumes.data.id = "TODO-data";
    };
    newdrive = {
      enable = false;
      description = "the 1 TB NewDrive";
      disks = [ "/dev/disk/by-id/TODO-newdrive-1TB" ];
      volumes.newdrive.id = "TODO-newdrive";
    };
    # The mirrored alternative, if a matching drive is bought: two disks in
    # one entry make a mirror (zpool create tt04 mirror A B). It survives one
    # disk's loss without the store, but is one pool: the store counts it as
    # two copies only if tt-fsck can see both members (decision 0039, S7).
    #   tt04.disks = [ "/dev/disk/by-id/...-A" "/dev/disk/by-id/...-B" ];
  };

  # The migration (2026-11-15): reading the M2's drives, read-only. The
  # Data drive is APFS (macOS); APFS by the linux-apfs-rw kernel module
  # (mounted -o ro only; apfs-fuse as a fallback), HFS+ by the kernel's own
  # hfsplus, exFAT natively. Drop this once the old drives are re-made as
  # ZFS.
  boot.extraModulePackages = [ config.boot.kernelPackages.apfs ];
  environment.systemPackages = with pkgs; [
    apfs-fuse
    hfsprogs
    exfatprogs
    rsync
    pv
    smartmontools
    hdparm
    lsof
  ];

  # Time, against several sources (tinytrader decision 0040: every
  # recording host runs chrony, and records its offset). Replaces
  # systemd-timesyncd.
  services.chrony = {
    enable = true;
    servers = [
      "0.nixos.pool.ntp.org"
      "1.nixos.pool.ntp.org"
      "2.nixos.pool.ntp.org"
      "time.cloudflare.com"
    ];
  };

  # The machine's CPU, memory, disks and ZFS for the console's Hosts view,
  # on loopback (tinytrader's role forwards it to the tailnet as it does the
  # Macs').
  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9100;
    enabledCollectors = [ "systemd" ];
  };

  # A server: no X, no desktop, no fonts.
  services.xserver.enable = false;
  fonts.fontconfig.enable = false;
  xdg.mime.enable = false;
  xdg.icons.enable = false;
  xdg.sounds.enable = false;
  xdg.autostart.enable = false;

  users.users.daws = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "docker"
    ];
    # The keys allowed in (public keys only), as on the M2.
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKAL6Lsp876QwJzwyhOxt4vutaFD0gL8y2q6QiysuNnP daws@macbook-air"
      # The mini's (dawsonshay's ~/.ssh/id_ed25519).
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN8g+NEcHo3csMXIOGGQ220By77YvHC/2sJ9wH/R45eG claude@dawsons-mac-mini-1"
    ];
  };

  # Its part in tinytrader (tinytrader-ops' nixosModules.nas). TODO(2026-11-15):
  # true once the NAS's host key is a recipient of tinytrader-ops' secrets
  # (its sops-nix decrypts them at activation; until then it can't) and the
  # pools are made.
  tinytrader-deploy.nas.enable = false;

  # Deploy what merges to tinytrader and tinytrader-ops main, every 5 minutes
  # outside market hours, as on the mini (tinytrader-ops decision 0011): it
  # keeps the deploy checkouts under ~daws/.local/share/tinytrader/deploy
  # current. The systemd services themselves change only with a rebuild
  # (above). Pause: touch ~/.config/tinytrader/auto-deploy.off
  tinytrader-deploy.autoDeploy = {
    enable = true;
    user = "daws";
  };

  # The release this host was first installed with; never change it after.
  system.stateVersion = "26.05";
}
