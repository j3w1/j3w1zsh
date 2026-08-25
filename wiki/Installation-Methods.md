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
