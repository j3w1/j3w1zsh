# Configuration and User Overrides

Canonical local paths are:

```text
~/.config/j3w1zsh/
~/.local/state/j3w1zsh/
~/.cache/j3w1zsh/
```

`~/.config/j3w1zsh/settings.zsh` is trusted, user-owned shell configuration. The installer creates it once and never overwrites it. Keep personal values there, including edit root, explicitly selected GitHub key path, and remote connection tokens.

All other configuration layers are strict JSON and are never sourced or evaluated:

- `packages.json` for package additions/exclusions;
- user themes under `themes/ID/theme.json`;
- workspace profiles;
- Wiki lock; and
- agent routes.

Generated theme output is device-local under `generated/theme/`. Package provenance, phases, migrations, workspace generations, backups, update recovery, and Wiki caches are state—not source—and are never committed.

Credentials, `.ssh`, `.codex`, GitHub CLI authentication, Tailscale state, histories, private repositories, caches, and database contents remain where their owning application keeps them. j3w1zsh neither copies nor logs them.
