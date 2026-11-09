# The Mac mini M4 (nix-darwin): the machine-level configuration. Your user
# setup (git, gh, Emacs, SSH config) stays in Home Manager (home.nix and
# hosts/mac.nix), applied as on every machine.
#
# It's the main desktop and runs research and training jobs, and is becoming
# the primary tinytrader host (containers via Colima, darwin/common.nix). What
# tinytrader runs here is defined in tinytrader-ops, not in this file.
#
#   scripts/switch   (builds as you, so the private tinytrader-ops input can be
#                    fetched with your GitHub login, then activates as root)
{ ... }:
{
  imports = [
    # Hostname-independent machine settings every Mac here shares: Tailscale,
    # SSH by key only, tools on PATH, sops-nix's key (with what Linux shares
    # too, from system/common.nix); and the always-on Macs' Colima and never
    # sleeping.
    ./common.nix
    ./server.nix
    # The local AI endpoint, a daemon run as you on 127.0.0.1:8317.
    ./ai-proxy.nix
  ];

  # This Mac's account is still dawsonshay; change to daws after the rename.
  system.primaryUser = "dawsonshay";

  networking.computerName = "mini";
  networking.hostName = "mini";
  networking.localHostName = "mini";

  # Colima's VM: the containers (the trading services, after the cutover).
  # FileVault is off here, so it starts at boot without anyone logging in.
  local.colima = {
    cpu = 6;
    memory = 12;
    disk = 100;
  };

  # The keys allowed in (public keys only; the backup module adds the M2's).
  users.users.dawsonshay.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKAL6Lsp876QwJzwyhOxt4vutaFD0gL8y2q6QiysuNnP daws@macbook-air"
  ];

  # Keep the M2's nightly tinytrader backups here (tinytrader-ops
  # modules/backup-darwin.nix): its backup key, from tinytrader-ops'
  # inventory.nix backup.keys, goes in this user's authorized keys
  # (users.users.<you>.openssh.authorizedKeys), restricted to rrsync,
  # write-only, from the tailnet, into ~/Backups/tinytrader-from-mac-mini-m2
  # (mode 700). Its files are age-encrypted before they leave the M2; no
  # shell, no forwarding, nothing readable back. Needs the sshd above.
  tinytrader-ops.backup.receive = true;

  # Deploy what merges to tinytrader and tinytrader-ops main, every 5 minutes
  # outside market hours; never the gateways, relays or pead (tinytrader-ops
  # decision 0011). Pause: touch ~/.config/tinytrader/auto-deploy.off
  # It and the containers run from the deploy checkouts, clones only it
  # touches (tinytrader-ops.deployRoot, default
  # ~/.local/share/tinytrader/deploy; decision 0012), so ~/repos is an
  # ordinary working copy.
  tinytrader-ops.autoDeploy.enable = true;
}
