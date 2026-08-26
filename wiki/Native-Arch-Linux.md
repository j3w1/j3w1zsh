# Native Arch Linux

Native support requires official Arch Linux, a normal user account, and functional `sudo`. Platform ID is `arch`.

j3w1zsh does not install an operating system, partition disks, manage a bootloader, create users, configure networking or firewalls, or claim ownership of general host services. Package operations use the Arch adapter; home configuration remains user-scoped. Remote host setup is an explicit, separate command.

```bash
j3w1zsh platform --json
j3w1zsh install --dry-run
j3w1zsh install --preset minimal
```

A package-enabled explicit install asks once for one fail-closed Pacman phase. It runs `sudo pacman -Sy --needed archlinux-keyring`, then immediately runs `sudo pacman -Su --needed` with the complete selected Pacman set. The first transaction safely makes current signing keys available to a stale machine; it is never treated as a successful standalone end state. The second transaction performs the coherent full system upgrade and installs or refreshes every selected target. Either failure prevents phase completion and all later phases. Routine forced database refreshes, partial upgrades, and downgrade-enabled repeated `-u` are not used. The protected `j3w1zsh update` command is a product source update and does not perform that full system upgrade.

For 1.0.0, native Arch acceptance may rely on the official Arch container and disposable-machine suite if physical hardware is unavailable. That evidence is simulation/disposable-host coverage, not real-hardware acceptance.
