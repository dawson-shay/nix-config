# The NAS's disks (nixos/nas.nix): one ZFS pool per disk, each holding the
# store's volumes as datasets. Adding a disk is one entry in local.nas.pools:
#
#   local.nas.pools.tt05 = {
#     enable = true;
#     disks = [ "/dev/disk/by-id/ata-ST24000NT002-..._SERIAL" ];
#     volumes.tt05.id = "tt05-2027-01-02-1a2b3c4d";
#   };
#
# Each pool is a single-disk vdev (or, with two disks, a mirror), ZFS
# checksums on, scrubbed monthly and snapshotted (nixos/nas.nix). Redundancy
# across disks is the store's: at least 2 verified copies on different
# pools, 3 for irreplaceable data (tinytrader decision 0039, S7), not RAID.
#
# A volume `<v>` on pool `<p>` is the dataset `<p>/store/<v>`, mounted at
# /srv/store/<v> (mountpoint=legacy, so systemd knows the mount and the
# store's unit can require it), and becomes the store's volume `<v>` with
# its id (tinytrader-deploy.nas.volumes). Its id file,
# /srv/store/<v>/.tinytrader-volume-id, must hold that id or the store
# refuses to start.
#
# NixOS imports the pools and mounts the datasets; it never creates a pool.
# `nas-pools` (on the NAS) prints the zpool and zfs commands that make
# them from this list, to read and run by hand: it changes nothing itself.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption mkEnableOption types;
  cfg = config.local.nas;
  enabled = lib.filterAttrs (_: p: p.enable) cfg.pools;
  # Every volume of the enabled pools: { name, pool, id, path }.
  volumesOf =
    pools:
    lib.concatLists (
      lib.mapAttrsToList (
        pool: p:
        lib.mapAttrsToList (name: v: {
          inherit name pool;
          inherit (v) id;
          path = "${cfg.storeRoot}/${name}";
        }) p.volumes
      ) pools
    );
  volumes = volumesOf enabled;
  allVolumes = volumesOf cfg.pools;
  placeholder = s: lib.hasInfix "TODO" s;

  # What `nas-pools` prints: the commands that make each pool and its
  # datasets. ashift=12 (4K sectors); the pool's root unmounted; each
  # volume's dataset with 1M records (the store's files are large and
  # written once), lz4, no atime, and auto-snapshots on.
  createCommands = lib.concatStrings (
    lib.mapAttrsToList (
      pool: p:
      let
        vdev = if lib.length p.disks == 2 then "mirror " else "";
      in
      ''
        # ${pool}${lib.optionalString (!p.enable) " (not enabled yet)"}: ${p.description}
        zpool create -o ashift=12 -o autotrim=off \
          -O checksum=on -O compression=lz4 -O atime=off -O xattr=sa \
          -O acltype=posixacl -O mountpoint=none -O canmount=off \
          ${pool} ${vdev}${lib.concatStringsSep " " p.disks}
        zfs create -o mountpoint=none -o canmount=off ${pool}/store
      ''
      + lib.concatStrings (
        lib.mapAttrsToList (name: v: ''
          zfs create -o mountpoint=legacy -o recordsize=1M -o com.sun:auto-snapshot=true ${pool}/store/${name}
          #   then, once mounted at ${cfg.storeRoot}/${name}:
          #   printf '%s\n' ${v.id} > ${cfg.storeRoot}/${name}/.tinytrader-volume-id
          #   chmod 444 ${cfg.storeRoot}/${name}/.tinytrader-volume-id
          #   chown -R tinytrader-store:tinytrader-store ${cfg.storeRoot}/${name}
        '') p.volumes
      )
      + "\n"
    ) cfg.pools
  );
  nasPools = pkgs.writeShellScriptBin "nas-pools" ''
    # Prints the commands that make the pools in local.nas.pools
    # (nix-config nixos/nas-pools.nix). Prints only: read them, check each
    # disk's by-id path (ls -l /dev/disk/by-id), then run them by hand.
    # zpool create wipes the disks it is given.
    cat <<'EOF'
    ${createCommands}
    EOF
  '';
in
{
  options.local.nas = {
    storeRoot = mkOption {
      type = types.str;
      default = "/srv/store";
      description = "Where the store's volumes are mounted, one directory each.";
    };
    pools = mkOption {
      default = { };
      description = "The ZFS pools, one per disk (or a mirror of two), and the store's volumes on each.";
      type = types.attrsOf (
        types.submodule {
          options = {
            enable = mkEnableOption "importing this pool and mounting its volumes (once it exists)";
            description = mkOption {
              type = types.str;
              default = "";
              description = "What the disk is.";
            };
            disks = mkOption {
              type = types.listOf types.str;
              description = ''
                The disk, by its /dev/disk/by-id path; two disks make a
                mirror (a pool of both, one copy per disk only if tt-fsck can
                see both members: tinytrader decision 0039, S7).
              '';
            };
            volumes = mkOption {
              description = "The store's volumes on this pool, name → id.";
              type = types.attrsOf (
                types.submodule {
                  options.id = mkOption {
                    type = types.str;
                    description = "The volume's id: what its .tinytrader-volume-id holds.";
                  };
                }
              );
            };
          };
        }
      );
    };
  };

  config = {
    assertions =
      lib.concatLists (
        lib.mapAttrsToList (pool: p: [
          {
            assertion = lib.elem (lib.length p.disks) [
              1
              2
            ];
            message = "local.nas.pools.${pool}: one disk (a single-disk pool) or two (a mirror)";
          }
          {
            assertion = lib.all (d: lib.hasPrefix "/dev/disk/by-id/" d) p.disks;
            message = "local.nas.pools.${pool}: name its disks by /dev/disk/by-id, not /dev/sdX";
          }
          {
            assertion = !p.enable || !(lib.any placeholder (p.disks ++ lib.mapAttrsToList (_: v: v.id) p.volumes));
            message = "local.nas.pools.${pool}: enabled with a TODO disk or volume id";
          }
        ]) cfg.pools
      )
      ++ [
        {
          assertion =
            let
              names = map (v: v.name) allVolumes;
            in
            lib.length names == lib.length (lib.unique names);
          message = "local.nas.pools: a volume name is on two pools";
        }
      ];

    boot.zfs.extraPools = lib.attrNames enabled;

    # Each volume's dataset, mounted by systemd. nofail: a missing disk
    # doesn't stop the boot; the store, which requires every mount, stays
    # stopped instead (tinytrader-deploy's modules/nas.nix).
    fileSystems = lib.listToAttrs (
      map (
        v:
        lib.nameValuePair v.path {
          device = "${v.pool}/store/${v.name}";
          fsType = "zfs";
          options = [
            "nofail"
            "noatime"
          ];
        }
      ) volumes
    );

    # The store's volumes, for its role.
    tinytrader-deploy.nas.volumes = lib.listToAttrs (
      map (v: lib.nameValuePair v.name { inherit (v) path id; }) volumes
    );

    environment.systemPackages = [ nasPools ];
  };
}
