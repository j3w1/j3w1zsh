# Package Layers and Presets

Package requirements resolve in this order:

1. the small immutable core needed to parse, plan, and manage state;
2. the selected strict preset;
3. validated user additions and exclusions in `~/.config/j3w1zsh/packages.json`; and
4. an explicitly selected approved workspace target.

Preset files contain features and package arrays only. They cannot contain commands, scripts, URLs, privileged destinations, or arbitrary adapters.

Arch and WSL targets may declare `pacman`, `npm_global`, and `pip_user`. Termux may declare `pkg`, `npm_global`, and `pip_user`. Exclusions cannot remove core packages or the protected closure required by selected features.

## Provenance

The atomic provenance ledger records manager, package, declaring layers, whether the package pre-existed, whether j3w1zsh installed it, first product version, and latest plan digest. A pre-existing package never becomes owned merely because a later preset declares it.

The platform manager, npm, and user-level Python sets are actions in one aggregate `20-packages` phase. That phase executes exactly once. A failed Pacman, `pkg`, npm, or pip command stops immediately; every required package must then pass an exact manager query before any provenance for that manager set is recorded. A failed or unverified set creates no phase marker and no later base phase runs.

`j3w1zsh packages prune --dry-run` lists candidates and reasons. Removal requires proof of j3w1zsh ownership, no active declaration, current package-manager identity, and confirmation. It removes only exact names and never performs recursive dependency cleanup. Ambiguity means preserve. Update never invokes prune.

## Corepack and Pacman `pnpm`

Pacman's `pnpm` package can conflict with `/usr/bin/pnpm` and `/usr/bin/pnpx` shims created by the Pacman-owned `corepack` package. j3w1zsh checks this exact condition before starting Pacman. If both unowned shim paths resolve to files owned by Pacman package `corepack`, installation exits 20 with ownership evidence and the direct owner-review command:

```bash
sudo corepack disable pnpm --install-directory /usr/bin
```

j3w1zsh never runs that command, deletes a shim, or overwrites the collision automatically. Verify both shim paths are absent, then rerun phase 20. Any partial, authored, differently owned, or otherwise ambiguous path state exits 21 unchanged.

## Repairing a disproved ownership claim

Use this only when a known failed pre-release transaction wrote provenance for packages the exact manager still reports absent. Start read-only:

```bash
j3w1zsh packages repair-provenance \
  --manager pacman \
  --package pnpm \
  --package stylua \
  --dry-run
```

Review the exact candidates, then rerun with `--yes`. The command revalidates the ledger and manager state immediately before mutation, preserves the removed rows and any phase-20 marker under `~/.local/state/j3w1zsh/packages/repairs/`, removes only the named false claims, and invalidates phase `20-packages`. It refuses installed packages, non-ownership rows, missing or duplicate targets, malformed state, changed projections, and platform/manager mismatches. It never installs, removes, or modifies a package.

Arch initial installation may offer a confirmed full `pacman -Syu`. Routine update never performs a full upgrade and never runs `pacman -Sy`.
