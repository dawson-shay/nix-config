# nix-config

My machines, with Git as the source of truth: Home Manager for the user
setup on every machine, nix-darwin for the Macs' machine level, and NixOS
(`/etc/nixos/configuration.nix`, outside this repo) on the ThinkPad.

| Machine | User config | Machine config |
|---|---|---|
| ThinkPad X200s | `homeConfigurations."daws@x200s"` | `/etc/nixos/configuration.nix` |
| Mac mini M4 (`mini`) | `homeConfigurations."dawsonshay@mini"` | `darwinConfigurations.mini` (`darwin/mini.nix`) plus tinytrader-ops' role |
| Mac mini M2 (`m2`) | `homeConfigurations."daws@mac"` | `darwinConfigurations.m2` (`darwin/m2.nix`) plus tinytrader-ops' role |
| MacBook Air (`laptop`) | `homeConfigurations."daws@mac"` | `darwinConfigurations.laptop` (`darwin/laptop.nix`) |
| NAS, Minisforum N5 Pro (`nas`), from 2026-11-15 | none yet | `nixosConfigurations.nas` (`nixos/nas.nix`) plus tinytrader-ops' role |

Day-to-day use (Emacs, Claude Code sessions, notebooks, switching each
Mac): [docs/guide.md](docs/guide.md).

## Layout

```text
/etc/nixos/configuration.nix   the X200s's machine config (not in this repo)
~/repos/nix-config/
├── flake.nix          composes everything below into homeConfigurations, darwinConfigurations and nixosConfigurations
├── flake.lock         pins nixpkgs, Home Manager, nix-darwin, sops-nix, tinytrader-ops and nix-secrets
├── home.nix           user config shared by every machine
├── hosts/
│   ├── x200s.nix      user config for the X200s, including launching EXWM
│   ├── mac.nix        macOS user settings (Home Manager owns zsh)
│   └── mini.nix       the M4's own: JupyterLab for research, on the tailnet
├── system/
│   └── common.nix     what every machine's machine config shares, Mac or Linux
├── darwin/
│   ├── common.nix     what every Mac's machine config shares (nix-darwin)
│   ├── mini.nix       the Mac mini M4's machine config
│   ├── m2.nix         the Mac mini M2's machine config
│   ├── server.nix     what the always-on Macs add (Colima, never sleeping)
│   ├── laptop.nix     the MacBook Air's machine config
│   └── ai-proxy.nix   the local AI endpoint, a daemon on mini
├── nixos/
│   ├── common.nix     what every Linux machine's machine config shares (NixOS)
│   ├── example.nix    nixosConfigurations.example: a stub host, so nix flake check evaluates nixos/common.nix
│   ├── nas.nix        nixosConfigurations.nas: the NAS's machine config (ZFS, chrony, node_exporter, auto-deploy)
│   ├── nas-pools.nix  its disks: one ZFS pool per disk (local.nas.pools), the store's volumes on them
│   └── nas-hardware.nix  its hardware (by label, as installed)
├── pkgs/
│   ├── ai-proxy.nix   the endpoint: CLIProxyAPI in front of OpenRouter (packages.<system>.ai-proxy)
│   └── cliproxyapi.nix  CLIProxyAPI's release binary, pinned by checksum
├── scripts/
│   ├── switch         apply a Mac's nix-darwin config
│   ├── switch-home    apply a Mac's Home Manager config (m4, m2, laptop)
│   ├── flake-update-pr  the monthly input-update PR (run by the M4)
│   ├── host-identity  keep a Mac's SSH host keys across a wipe (in nix-secrets)
│   ├── ai-login       sign the AI endpoint in to a subscription
│   ├── ai-key         set its keys (in nix-secrets)
│   └── ai-client-key  print the key its clients send
├── ssh/config         ~/.ssh/config
├── docs/guide.md      day-to-day use
└── emacs/
    ├── init.el
    └── early-init.el
```

The machine level is in three layers. `system/common.nix` holds what is the
same on a Mac and on Linux, with option names both nix-darwin and NixOS
have (and a `pkgs.stdenv.hostPlatform.isDarwin` guard where they spell one
differently, as with sshd's settings): the system tools, Tailscale, SSH by key
only, sops-nix's key, and the timezone (set on NixOS only; the Macs keep
System Settings'). `darwin/common.nix` and `nixos/common.nix` each import it
and add what differs by platform: launchd or systemd services, `/etc/paths.d`
on the Mac, power management, and containers (Colima's VM on a Mac, the Docker
engine natively on Linux). A host's own file (`darwin/mini.nix`,
`nixos/example.nix`) imports its platform's `common.nix` and adds its name,
users, authorized keys and what it alone runs.

Responsibilities:

* `/etc/nixos/configuration.nix`: machine/system configuration on the X200s: kernel, bootloader, networking, Xorg, services, hardware.
* `home.nix`: user configuration shared across machines: CLI tools, Git/GitHub, Emacs and Emacs packages, SSH config, and `cargo` wrapped to build into one folder per repository (`~/.cache/cargo-target/<repo>/target`), shared by its worktrees, so they don't each leave a `target/` behind (tinytrader-deploy's decision 0016).
* `hosts/x200s.nix`, `hosts/mac.nix`: per-platform user settings.
* `system/common.nix`: the machine configuration every machine shares, Mac or Linux: system tools, Tailscale, SSH (keys only), sops-nix's key, the timezone.
* `darwin/common.nix`: the rest of what every Mac here shares (nix-darwin), the counterpart of `nixos/common.nix`: Determinate Nix, the shells left to Home Manager, Tailscale's resolver file, nix-darwin's tools on PATH.
* `darwin/server.nix`: what the always-on Macs (the M4, the M2) add: power (never sleeps, restarts after a power cut), the container tools, and Colima, which runs the Docker engine as a boot daemon (`org.nixos.colima`), so containers come back after a reboot without anyone logging in (each Mac sizes its VM with `local.colima`).
* `darwin/laptop.nix`: the MacBook Air's: a client, with the Tailscale app rather than nix-darwin's, Touch ID for sudo, and the M4's builds accepted (`extra-trusted-users`).
* `nixos/common.nix`: the rest of what every Linux machine shares (NixOS): Nix with flakes, Docker natively, never sleeping. `nixosConfigurations.example` and `.nas` use it; the X200s is still on `/etc/nixos/configuration.nix`.
* `darwin/mini.nix`: the Mac mini M4's: its name, user, SSH keys, Colima's size, and the local AI endpoint (`darwin/ai-proxy.nix`, below), whose secrets sops-nix decrypts.
* `darwin/m2.nix`: the Mac mini M2's (the NAS and job runner, account `daws`): its name, user, SSH keys and Colima's size. Its user config is `daws@mac`.
* `nixos/nas.nix`: the NAS's (account `daws`): ZFS (monthly scrubs, daily/weekly/monthly snapshots), chrony, node_exporter, no desktop, its SSH keys, auto-deploy, and tinytrader-ops' `nixosModules.nas` (`tinytrader-deploy.nas.enable`, off until its host key is a recipient of tinytrader-ops' secrets). Its disks are `local.nas.pools` in `nixos/nas-pools.nix`: one pool per disk (two disks make a mirror), each with the store's volumes as datasets mounted at `/srv/store/<volume>`; adding a disk is one entry, and `nas-pools` on the NAS prints the commands that make it. Install and migration: tinytrader-ops' `docs/nas-migration-2026-11-15.md`.
* `emacs/init.el`: portable Emacs behavior and package configuration.

*hosts/ will likely be refactored into something closer to platforms/{linux/, mac/} and then machine specific like x200s, mac-laptop, rapsberry-pi, etc. Similarly, right now, init.el holds macos specific adjustments. If that grows too much, we'll adjust.

## Switching

User config, on any machine:

```sh
home-manager switch --flake ~/repos/nix-config#daws@x200s       # the ThinkPad
home-manager switch --flake ~/repos/nix-config#dawsonshay@mini  # the M4
```

This works over ssh and from a Claude Code session too. Home Manager copies
its apps into `~/Applications/Home Manager Apps` (for Spotlight), and once a
*developer-signed* app has been launched, macOS's App Management protection
blocks changes to it from anything without that permission (over ssh,
nothing has it). So Ghostty, whose package is the developer's notarized
build, is re-signed ad-hoc in its Nix build, like the apps Nix builds itself
(`hosts/mac.nix`). Re-sign any other signed app the same way.

Machine config on a Mac:

```sh
~/repos/nix-config/scripts/switch          # this Mac (mini)
~/repos/nix-config/scripts/switch HOST     # another darwinConfigurations entry (the M2: m2)
```

`scripts/switch` builds the configuration as you, then activates it as root
(it asks for your password), after asking if the configuration is for a
Mac with another name. Don't use `sudo darwin-rebuild switch`: it
evaluates as root, which has no GitHub login, so it can't fetch the private
tinytrader-ops input (nor nix-secrets).

On the X200s, the machine config is `sudo nixos-rebuild switch`. On the
NAS, as you (so the private inputs are fetched with your GitHub login):
`nixos-rebuild switch --flake ~/repos/nix-config#nas --sudo`.

## The tinytrader-ops role

`darwinConfigurations.mini` imports `tinytrader-ops.darwinModules.mini`: what
of the tinytrader deployment runs natively on this Mac (its monitor and
node_exporter). `darwinConfigurations.m2` imports
`tinytrader-ops.darwinModules.mac-mini-m2` (the store, alpaca-history, the
monitor, node_exporter, the backups). What runs where, and everything else about the deployment,
is defined in tinytrader-ops, not here; this repo owns the machine (users,
Tailscale, Colima).

tinytrader-ops is private, so building `#mini` needs GitHub access as you (gh
logged in, with git using it as the credential helper, which Home Manager
sets up). The role is taken at the revision `flake.lock` pins. To take a
change from tinytrader-ops:

```sh
cd ~/repos/nix-config
nix flake update tinytrader-ops
git commit -am "Take tinytrader-ops <rev>: <why>"
scripts/switch
```

## Secrets: nix-secrets and sops-nix

Secrets live in a separate private repository,
[nix-secrets](https://github.com/dawson-shay/nix-secrets), as sops files
encrypted to age keys: the operator key (yours, in
`~/Library/Application Support/sops/age/keys.txt`), the offline recovery key,
and each machine's SSH host key (`ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub`).
Its README says how to add a secret or a machine. This repository takes it as
the `nix-secrets` flake input (pinned in `flake.lock`, private like
tinytrader-ops, so building `#mini` needs your GitHub login) and names the
files it uses; it never holds a secret, not even encrypted.

[sops-nix](https://github.com/Mic92/sops-nix)'s nix-darwin module decrypts
them on the machine as root, with the host key, so your key isn't needed: at
each activation (the end of `scripts/switch`) and at every boot (its
`org.nixos.sops-install-secrets` daemon, since `/run` is emptied at boot),
into `/run/secrets/<name>`, with the owner and mode `sops.secrets` sets.
Notes:

* It works with `nix.enable = false` (Determinate Nix manages Nix): the
  module doesn't touch `nix.*`; no workaround needed.
* `/run` is `/private/var/run` on the system disk (macOS has no ramfs, so
  `useTmpfs` is off): the decrypted files are on disk, readable by their
  owner and root, until the next boot or activation replaces them.
* `darwin/mini.nix` sets the key sources: the ed25519 host key as an age key,
  and no GPG keys (sops-nix would otherwise also import the RSA host key).
* Secrets are installed after launchd services are (re)loaded, so a daemon
  that reads one waits for it (as `darwin/ai-proxy.nix` does), and a daemon
  isn't restarted when only a secret changes: restart it by hand.

To take a change from nix-secrets: `nix flake update nix-secrets`, commit,
`scripts/switch`.

## The local AI endpoint (ai-proxy)

`darwin/ai-proxy.nix` runs `pkgs/ai-proxy.nix` on mini as a boot-time daemon
(`org.nixos.ai-proxy`) run as you: an OpenAI/Anthropic/Gemini-compatible
endpoint on `http://127.0.0.1:8317/v1` (loopback only), CLIProxyAPI in front
of OpenRouter's free models (the `free` and `free-pool` aliases) plus any
subscriptions signed in with `scripts/ai-login`. Its users are my own tools
(gptel, Pi, ...); nothing in tinytrader uses it.

* Keys: nix-secrets' `ai-proxy.env` (`OPENROUTER_API_KEY`, `AI_PROXY_KEY`),
  at `/run/secrets/ai-proxy.env`, readable only by you.
* State: `~/.local/state/ai-proxy` (mode 700): `config.yaml`, rendered at
  each start with the keys in it (mode 600), and `auth/`, the OAuth sign-ins.
  Not in any backup: if it's lost, sign in again.
* Logs: `~/Library/Logs/ai-proxy.{out,err}.log`.

```sh
scripts/ai-client-key            # the key clients send (as a Bearer token or x-api-key)
curl -s http://127.0.0.1:8317/v1/models -H "Authorization: Bearer $(scripts/ai-client-key)"
scripts/ai-login claude          # or chatgpt, chatgpt-code, gemini; picked up live
scripts/ai-key                   # new OpenRouter key and client key, into ~/repos/nix-secrets
sudo launchctl kickstart -k system/org.nixos.ai-proxy   # restart, e.g. after new keys
nix run .#ai-proxy               # by hand, anywhere (set its environment: pkgs/ai-proxy.nix)
```

It was tinytrader's `nix/ai-proxy.nix`, run as a container by tinytrader-ops,
until 2026-10.

## New Mac

Install nothing else by hand first: anything installed outside Nix (gh, Tailscale, etc.) will clash with what the switch manages. The repo is public and holds no secrets, so cloning needs no login.

```sh
# 1. Install Nix (once). Then open a new Terminal window.
curl -fsSL https://install.determinate.systems/nix | sh -s -- install

# 2. Clone this repo (git from Nix, so nothing else is installed).
nix run nixpkgs#git -- clone https://github.com/dawson-shay/nix-config.git ~/repos/nix-config

# 3. User config (Home Manager): Emacs, git, gh (and git using it for GitHub), shell.
nix run home-manager -- switch --flake ~/repos/nix-config#<user>@<host>

# 4. Open a new Terminal window, then log in with the Nix-managed gh. Step 5
#    needs it: #mini imports the private tinytrader-ops.
gh auth login

# 5. Machine config (nix-darwin): hostname, Tailscale, SSH, power, Colima,
#    and the tinytrader-ops role. Asks for your password.
~/repos/nix-config/scripts/switch

# 6. Open a new Terminal window (only new login shells pick up nix-darwin's
#    tools on PATH), then join the tailnet.
sudo tailscale up

```

A new machine needs its own entries in `flake.nix` (`homeConfigurations` and, for a Mac, `darwinConfigurations`), with its username and home directory. If a switch stops because a file already exists, add `-b backup` to move the old file aside.

Before step 3, move aside what would shadow or fight the managed config (to `~/.local/share/pre-nix-backup/`, not deleted): `~/.emacs.d` (Emacs ignores the managed `~/.config/emacs` while it exists, silently), and any hand-written `~/.zshrc` and `~/.ssh/config` (keep a copy of any host aliases worth adding to `ssh/config` here). Homebrew can stay, but `brew uninstall` what Nix now provides (gh, git, emacs) so only one is on PATH.

A Mac that runs part of the tinytrader deployment then needs the sops age key and the tinytrader checkouts: tinytrader-ops' `docs/operations.md`, "Rebuild a host from scratch".

### Rebuilding an existing host

Wiping a Mac that already has an entry here, and keeping its identity: the
same SSH host key (so every known_hosts entry and any sops recipient made
from it still hold, nothing to re-encrypt) and the same Tailscale name and
address. Everything but the steps at its keyboard runs from the Mac you
work at, which has the operator key and the nix-secrets checkout. Its
tailnet address and name are in tinytrader-ops' `inventory.nix`, not here;
the exact run for the M2 is tinytrader-ops' `docs/operations.md`, "Rebuild a
host from scratch".

1. **Save its identity**, while it still runs:
   `scripts/host-identity save HOST TARGET` (HOST as in `darwinConfigurations`,
   TARGET an ssh destination; asks for its sudo password). Its host keys go
   into nix-secrets `hosts/HOST/`, encrypted to the operator and recovery
   keys only, never to the host itself. Commit and push nix-secrets. Copy off
   anything not in git or a backup.
2. **Wipe it** (Erase All Content and Settings). In Setup Assistant make the
   same account (the short name matters) and turn on Remote Login.
3. **Restore its identity**, before anything else: `scripts/host-identity
   restore HOST USER@LAN-ADDRESS`. It shows the fingerprint the new install
   presents, to compare with `ssh-keygen -lf
   /etc/ssh/ssh_host_ed25519_key.pub` on its screen, then puts the saved keys
   in place (root, 600) and checks the host now presents the saved key and
   its age recipient. macOS starts sshd per connection: no restart. A host
   whose services decrypt with the operator key also needs it:
   `scripts/host-identity operator-key USER@LAN-ADDRESS`.
4. **Install Nix, clone, switch**, at its keyboard: steps 1 to 5 of New Mac
   above, with its own names (`daws@mac`, `scripts/switch HOST`).
5. **Join Tailscale and pin it**, from your Mac, with tinytrader-ops'
   scripts (they use its OAuth client): `scripts/tailscale-join
   USER@LAN-ADDRESS` (interactive: a Mac stays an untagged device of yours,
   which a key minted by an OAuth client can't make), then
   `scripts/tailscale-pin --apply --prune NAME ADDRESS`, which deletes the old,
   offline device and gives the new one its name and address back (without
   `--apply` it only lists them).
6. `scripts/host-identity check HOST HOST` once `ssh HOST` works again over
   the tailnet: the old known_hosts entry holds, with no warning.

### Spotlight (by hand)

Keep Spotlight on (turning it off breaks app launching and Finder and Mail search), but keep it out of folders that churn: its index reached 13 GB on the M2 from repos and caches. Its exclusion list is a root-only system file, so it isn't managed here. In System Settings → Spotlight → Search Privacy, add:

- `~/repos`, `~/.cache`, `~/.cargo`, `~/.rustup`, `~/.colima`
- `~/Library/Containers/com.docker.docker` (Docker Desktop, where installed)
- `/nix`

For market-data drives, turn indexing off on the drive itself, which survives unplugging better than a Search Privacy entry: `sudo mdutil -i off /Volumes/<drive>`. Note here whatever goes wrong next time Spotlight misbehaves, so the fix can target it.

## Package management

Do not install persistent workstation tools imperatively when they should be reproducible.

Shared user tools belong in `home.nix`:

```nix
home.packages = [
  pkgs.tree
  pkgs.somePackage
];
```

Machine-level packages and services belong in the machine config: `/etc/nixos/configuration.nix` on the X200s, `system/common.nix` for every machine, `darwin/common.nix` for every Mac, `nixos/common.nix` for every NixOS host, `darwin/mini.nix` or `darwin/m2.nix` for one.

Emacs packages are installed by Home Manager:

```nix
programs.emacs = {
  enable = true;

  extraPackages = epkgs: [
    epkgs.nix-mode
    epkgs.magit
    epkgs.exwm
  ];
};
```

Emacs Lisp configures those packages:

```elisp
(use-package magit
  :commands magit-status)
```

Do not use `package-install` or `use-package :ensure` for packages managed by Nix.

Temporary packages can be used without changing configuration:

```sh
nix shell nixpkgs#PACKAGE
```

## Emacs and EXWM

Home Manager deploys:

```text
~/repos/nix-config/emacs/
```

to:

```text
~/.config/emacs/
```

Edit the source files under `~/repos/nix-config/emacs/`, then run Home Manager to deploy them.

EXWM is installed through Home Manager (on Linux only) and launched on the X200s using:

```elisp
(exwm-wm-mode)
```

The X server itself is enabled at the NixOS system level. EXWM can currently be launched from a TTY with:

```sh
startx ~/.xsession
```

## Git workflow

This repository is backed by GitHub.

Typical change:

```text
edit
→ home-manager switch --flake '.#daws@x200s'   (or scripts/switch for a Mac's machine config)
→ test
→ stage
→ commit
→ push
```

Magit is the preferred Git interface inside Emacs.

GitHub authentication is handled by `gh`, with Git configured to use the `gh` credential helper.

## Cross-platform design

The shared Emacs configuration should remain ordinary portable Emacs Lisp.

Home Manager provides packages and files on both Linux and macOS. On macOS, nix-darwin (`darwin/mini.nix`) handles the machine level, as NixOS does on Linux; only developer/user configuration is intended to be portable.

Machine-specific behavior should remain outside shared `home.nix` whenever practical.

## Guiding rule

This repository is public: never commit secrets, tokens or keys to it, even encrypted, or private details (addresses, account identifiers, anything from tinytrader-ops beyond the role's name). Secrets live in private repos as sops files (nix-secrets for the machines, tinytrader-ops for the deployment) or outside git.

Treat the repository as the source of truth. Avoid manually mutating generated files such as:

```text
~/.config/emacs
~/.config/git/config
```

Edit their source configuration instead, apply the configuration, test it, then commit the result.
