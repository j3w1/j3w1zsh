# Installation Methods

## Git checkout

Clone the canonical repository into `~/j3w1zsh`, inspect it, and run the shim:

```bash
git clone https://github.com/j3w1/j3w1zsh.git ~/j3w1zsh
cd ~/j3w1zsh
./install.sh --dry-run
./install.sh
```

The shim delegates directly to `bin/j3w1zsh install`.

## Rolling software refresh

Every explicit package-enabled `j3w1zsh install` refreshes the selected rolling software definition. On Arch and WSL, the reviewed Pacman action is equivalent to:

```bash
sudo pacman -Syu --needed COMPLETE_SELECTED_PACMAN_SET
```

It never runs `pacman -Sy`. On Termux it performs the supported `pkg upgrade` and then ensures the complete selected `pkg` set. Selected npm globals use their current distribution tags; selected user-level Python packages use upgrade semantics. WSL Codex follows OpenAI's current stable official distribution and a newer valid local version is not downgraded.

Completed package, Codex, and final-verification markers do not suppress this explicit refresh. Unrelated configuration phases retain their fingerprints and may be skipped. `--dry-run` shows the actions but changes no package database, state, cache, or host path.

## Exact-commit bootstrap

For releases and major migration, prefer an immutable URL containing the final release OID. Download the script and checksum from that same OID, run `sha256sum -c`, inspect the script, and use the explicit commit twice:

```bash
./migrate-to-j3w1zsh.sh --dry-run \
  --target-ref FINAL_40_HEX_OID \
  --expected-commit FINAL_40_HEX_OID \
  --source ~/projects/former-checkout
```

Do not pipe mutable `main` directly into a shell.

## Package-free reconciliation

```bash
j3w1zsh install --no-packages
```

The exact synonyms are `--no-packages`, `--do-not-install-anything`, and `-dnia`. They perform configuration reconciliation with already available tools and acquire nothing.

## Packages only

```bash
j3w1zsh install --packages-only --preset minimal
j3w1zsh install --packages-only --workspace ./j3w1zsh.workspace.json
```

Packages-only mode never runs managed-file or workspace lifecycle phases.
