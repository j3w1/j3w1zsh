# j3w1zsh

**one shell. every machine. zero compromise.**

j3w1zsh is a public, reproducible Zsh workstation framework for:

- native official Arch Linux;
- official Arch Linux under Windows WSL 2; and
- the native main Termux environment on Android.

The same shell, tmux, Neovim, planning, theme, backup, and safety model follows you across the three platforms. Platform adapters remain explicit: WSL host integration never leaks into native Arch, and Termux never receives privilege or system-level operations.

Start with [Getting Started](Getting-Started), then choose an [installation method](Installation-Methods). The [CLI reference](CLI-and-Help) documents stable commands and exit codes.

## Design promises

- Resume markers are written only after verification.
- Existing user paths are backed up before reconciliation.
- Plans and dry-runs do not mutate state, packages, Git refs, trust, or host configuration.
- Presets, themes, package overrides, workspaces, Wiki locks, and agent routes are strict JSON.
- Authentication, credentials, private projects, and application data remain user-owned.
- Updates fast-forward only and preserve authored or divergent work for review.
- Workspace lifecycle is direct argv, bounded, tracked-clean, and never started automatically for development.

The visual language is true black, blood red, and warm white. ANSI terminal green deliberately maps to red; semantic Neovim green remains green where meaning requires it.
