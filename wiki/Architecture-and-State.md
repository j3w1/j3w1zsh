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

An explicit package-enabled install deliberately refreshes phases `20-packages`, selected `60-neovim`, selected WSL `70-codex`, and `90-verify` even when their fingerprints are current. This is bounded rolling-software policy, not a global `--force`: unrelated configuration phases keep their cached markers. Product `update` uses the separate missing-requirement reconciliation mode and never turns a source fast-forward into an unconditional platform upgrade.

Phase 60 seeds the device-local runtime lock from the reviewed tracked `lazy-lock.json`, installs missing plugins from that lock, reseeds it to discard installer-generated drift, runs lazy.nvim's lock-directed restore and clean operations, and then independently proves semantic lock equality plus every managed plugin repository HEAD. Missing, older, newer, or partially installed plugin state converges to the tracked commits; malformed, symlinked, non-Git, ambiguous, or mismatched state cannot receive a phase marker. Phase 90 repeats the same read-only proof before loading the verified Neovim configuration. Normal Neovim sessions continue using device-local runtime state, while `scripts/update-neovim-lock.sh` is the separate maintainer-only path for intentionally advancing the tracked lock.

On WSL, phase 90 proves actual Windows PE execution. A failed probe records the manual `wsl-interop-restart` checkpoint before phase completion; `j3w1zsh install --only 90-verify` retries only the bounded final phase and clears the checkpoint only after the runtime proof succeeds.

Workspace generations add workspace ID, full manifest SHA-256, and platform. Trust and phase completion are separate records. A failed action is never marked complete.

Filesystem reconciliation validates the intended home boundary, backs up conflicts, and uses atomic replace for state/config output. Script-created staging and comparison directories use one registered, parent-scoped, prefix-validated, process-marker-owned cleanup primitive; promotion to an approved persistent destination removes ephemeral ownership. Manual checkpoints persist exact instructions and exit 20.
