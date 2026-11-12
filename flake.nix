{
  description = "My machines: Home Manager everywhere, nix-darwin for the Macs, NixOS for Linux";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The tinytrader deployment (private): the roles machines play in it.
    # Building a host that imports one needs GitHub access to that repo.
    tinytrader-ops = {
      url = "git+https://github.com/dawson-shay/tinytrader-ops?ref=main";
      inputs.nix-darwin.follows = "nix-darwin";
    };

    # Secrets for the machines, decrypted on them at activation.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # My secrets (private): sops files, encrypted to age keys (its README).
    # Like tinytrader-ops, building a host that uses it needs GitHub access.
    nix-secrets.url = "git+https://github.com/dawson-shay/nix-secrets?ref=main";
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      nix-darwin,
      tinytrader-ops,
      sops-nix,
      nix-secrets,
      ...
    }:
    let
      mkHome =
        {
          system,
          username,
          homeDirectory,
          hostModule,
        }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};

          modules = [
            ./home.nix
            hostModule

            {
              home.username = username;
              home.homeDirectory = homeDirectory;
            }
          ];
        };
    in
    {
      homeConfigurations = {
        "daws@x200s" = mkHome {
          system = "x86_64-linux";
          username = "daws";
          homeDirectory = "/home/daws";
          hostModule = ./hosts/x200s.nix;
        };

        # Any Mac whose account is daws: the M2 (darwinConfigurations.m2), the
        # laptop. Change to x86_64-darwin later if a Mac is Intel.
        "daws@mac" = mkHome {
          system = "aarch64-darwin";
          username = "daws";
          homeDirectory = "/Users/daws";
          hostModule = ./hosts/mac.nix;
        };

        # The Mac mini M4. Its account is still dawsonshay; once it's renamed
        # to daws, this can go and `daws@mac` applies.
        "dawsonshay@mini" = mkHome {
          system = "aarch64-darwin";
          username = "dawsonshay";
          homeDirectory = "/Users/dawsonshay";
          hostModule = {
            imports = [
              ./hosts/mac.nix
              ./hosts/mini.nix
            ];
          };
        };
      };

      # The local AI endpoint (darwin/ai-proxy.nix runs it on mini), to run
      # or try by hand: nix run .#ai-proxy, nix run .#cliproxyapi.
      packages = nixpkgs.lib.genAttrs [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ] (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        rec {
          cliproxyapi = pkgs.callPackage ./pkgs/cliproxyapi.nix { };
          ai-proxy = pkgs.callPackage ./pkgs/ai-proxy.nix { inherit cliproxyapi; };
        }
      );

      # Machine-level configuration for Macs (nix-darwin). User settings stay
      # in homeConfigurations above.
      darwinConfigurations = {
        # The Mac mini M4.
        mini = nix-darwin.lib.darwinSystem {
          specialArgs = { inherit nix-secrets; };
          modules = [
            sops-nix.darwinModules.sops
            ./darwin/mini.nix
            # Its part in tinytrader: what of it runs here natively.
            tinytrader-ops.darwinModules.mini
          ];
        };

        # The Mac mini M2 (the NAS and job runner until the real NAS).
        m2 = nix-darwin.lib.darwinSystem {
          specialArgs = { inherit nix-secrets; };
          modules = [
            sops-nix.darwinModules.sops
            ./darwin/m2.nix
            # Its part in tinytrader: the store, alpaca-history, the monitor,
            # node_exporter, the backups.
            tinytrader-ops.darwinModules.mac-mini-m2
          ];
        };

        # The MacBook Air: a client, with no part in tinytrader.
        laptop = nix-darwin.lib.darwinSystem {
          specialArgs = { inherit nix-secrets; };
          modules = [
            sops-nix.darwinModules.sops
            ./darwin/laptop.nix
          ];
        };
      };

      # Machine-level configuration for Linux (NixOS), sharing system/common.nix
      # with the Macs. The X200s's is still /etc/nixos/configuration.nix.
      nixosConfigurations = {
        # Not a machine: proof that nixos/common.nix evaluates (a VM's
        # hardware). nix flake check evaluates it.
        example = nixpkgs.lib.nixosSystem {
          modules = [
            sops-nix.nixosModules.sops
            ./nixos/example.nix
          ];
        };

        # The NAS (a Minisforum N5 Pro): the store's disks and the data
        # services. Its part in tinytrader, imported unchanged, brings
        # sops-nix's NixOS module itself (the role decrypts tinytrader-ops'
        # secrets with this machine's host key), so it isn't listed again.
        # It is built on tinytrader's NixOS release (tinytrader-ops' nixpkgs,
        # nixos-26.05, the one its service module is written for), not this
        # flake's nixos-unstable: a server on a stable release, moving when
        # tinytrader's pin does.
        nas = tinytrader-ops.inputs.nixpkgs.lib.nixosSystem {
          specialArgs = { inherit nix-secrets; };
          modules = [
            ./nixos/nas.nix
            tinytrader-ops.nixosModules.nas
          ];
        };
      };
    };
}