# Native Arch Linux

Native support requires official Arch Linux, a normal user account, and functional `sudo`. Platform ID is `arch`.

j3w1zsh does not install an operating system, partition disks, manage a bootloader, create users, configure networking or firewalls, or claim ownership of general host services. Package operations use the Arch adapter; home configuration remains user-scoped. Remote host setup is an explicit, separate command.

```bash
j3w1zsh platform --json
j3w1zsh install --dry-run
j3w1zsh install --preset minimal
```

A package-enabled explicit install asks for one coherent `sudo pacman -Syu --needed` transaction containing the complete selected Pacman set. This refreshes the Arch system consistently and avoids partial-upgrade behavior; `pacman -Sy` is never used. The protected `j3w1zsh update` command is a product source update and does not perform that full system upgrade.

For 1.0.0, native Arch acceptance may rely on the official Arch container and disposable-machine suite if physical hardware is unavailable. That evidence is simulation/disposable-host coverage, not real-hardware acceptance.
