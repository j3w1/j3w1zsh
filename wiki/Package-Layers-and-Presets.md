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

`j3w1zsh packages prune --dry-run` lists candidates and reasons. Removal requires proof of j3w1zsh ownership, no active declaration, current package-manager identity, and confirmation. It removes only exact names and never performs recursive dependency cleanup. Ambiguity means preserve. Update never invokes prune.

Arch initial installation may offer a confirmed full `pacman -Syu`. Routine update never performs a full upgrade and never runs `pacman -Sy`.
