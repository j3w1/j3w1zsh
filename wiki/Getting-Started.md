# Getting Started

## Before installation

Use a normal user account, a stable network connection, and a clean checkout. j3w1zsh supports only the three documented platform IDs: `arch`, `wsl`, and `termux`.

Verify the downloaded bootstrap or checkout before running it. For a released migration, use the immutable release or commit URL, compare the tracked SHA-256, inspect the script, run `--dry-run`, then execute with the same explicit target ref and 40-character commit.

## First commands

```bash
./install.sh --dry-run
./install.sh --preset minimal --dry-run
./install.sh --yes
```

After installation:

```bash
j3w1zsh platform --json
j3w1zsh status --json
j3w1zsh doctor --json
j3w1zsh plan
```

`j3w1zsh plan` checks only the current Git repository root for `j3w1zsh.workspace.json`. Outside Git it checks only the current directory. It never recursively searches your home or parent repositories.

## Choose a preset

- `j3w1` preserves the full owner workstation capability, including developer tools, GitHub integration, remote support, and WSL-only Codex.
- `minimal` keeps Zsh, tmux, Neovim, SSH, planning prerequisites, and the built-in theme while omitting broad tooling and automation.

Use `--no-packages` when packages must remain entirely owner-managed. Missing tools are reported rather than installed.

Package-enabled `install` is an explicit rolling-software refresh, not a restore to historical version references. Review its dry-run: Arch/WSL uses one coherent full-upgrade transaction for the complete selected Pacman set; Termux performs its supported upgrade plus complete selected `pkg` reconciliation; selected npm and user-level Python packages are refreshed; and WSL refreshes Codex from OpenAI's current stable channel. A newer valid local version remains healthy and is not downgraded.
