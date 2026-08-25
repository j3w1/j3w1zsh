# CLI and Help

Use `j3w1zsh help`, `j3w1zsh help edit`, or `j3w1zsh help remote`. Global output options may appear before or after the command until `--`:

```text
--json
--plain
--color=auto|always|never
```

`--json` emits one envelope with `schema_version`, `command`, `status`, and `data`. Errors add a stable error code. JSON and plain output never include ANSI or a human banner.

## Command families

- Installation: `install`, `plan`, `status`, `doctor`, `platform`, `reset-phase`.
- Maintenance: `update`, `backup`, `restore`, `migrate`.
- Daily use: `edit`, `attach`, `remote`.
- Declarative layers: `packages`, `theme`, `workspace`, `wiki`.

`edit [PATH]` runs `nvim -- PATH`. With no path it uses `J3W1ZSH_EDIT_ROOT`, defaulting to `$HOME/Documents`.

`attach` opens `tma`; `attach SESSION` attaches exactly that session; `--new`, `--list`, and confirmed `--kill` are bounded operations. Attaching creates another tmux client and does not disconnect an existing client.

## Exit codes

| Code | Meaning |
|---:|---|
| 0 | Success, healthy status, or no required change |
| 1 | Validation, verification, runtime, or health failure |
| 2 | Invalid command, option, or argument |
| 20 | External or manual checkpoint required |
| 21 | Protected authored, staged, ahead, or divergent state requires owner review |
