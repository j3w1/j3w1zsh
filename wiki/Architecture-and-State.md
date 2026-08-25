# Architecture and State

The shell-first execution path is:

```text
bin/j3w1zsh
  -> scripts/lib/core/       environment, output, platform, state, filesystem, Git, plan
  -> scripts/commands/       command-family dispatch
  -> scripts/platforms/      arch, wsl, termux adapters
  -> scripts/phases/         selected idempotent installation phases
  -> scripts/lib/            presets, packages, themes, workspace, Wiki
```

Base phases are `00-preflight`, `10-platform`, `20-packages`, `30-shell`, `40-config`, `50-theme`, `60-neovim`, `70-codex`, `80-github`, and `90-verify`.

The action graph may contain several typed actions for one phase. Execution validates every selected action, then invokes the aggregate phase exactly once in canonical phase order. Phase functions are simple commands rather than shell conditions, so a failing child command terminates the phase before its marker and before every later phase.

Each completed phase is atomic JSON containing state schema, product version, platform, selected preset/theme, relevant input digest, UTC timestamp, and verified commit. Changed inputs invalidate the marker. Unselected and platform-inapplicable features are reported instead of falsely marked successful.

Workspace generations add workspace ID, full manifest SHA-256, and platform. Trust and phase completion are separate records. A failed action is never marked complete.

Filesystem reconciliation validates the intended home boundary, backs up conflicts, and uses atomic replace for state/config output. Script-created staging and comparison directories use one registered, parent-scoped, prefix-validated, process-marker-owned cleanup primitive; promotion to an approved persistent destination removes ephemeral ownership. Manual checkpoints persist exact instructions and exit 20.
