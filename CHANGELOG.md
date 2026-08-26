# Changelog

All notable changes to `j3w1zsh` are documented here.

## [Unreleased]

### Added

- Independent lowercase `j3w1zsh` identity, exact tagline, original SVG/derived host PNG, and a
  built-in declarative true-black/blood-red theme.
- First-class adapters for native official Arch Linux, official Arch Linux under WSL 2, and
  native Termux on Android, with fail-closed unsupported-platform dispatch.
- A bounded CLI/output layer, typed action planner, fingerprinted resumable phases, atomic state,
  backups, restore, doctor/status, edit, attach, and generalized remote commands.
- Strict presets and package overrides, protected core closure, per-package provenance, explicit
  prune candidates, and dry-run/package-only/package-free install modes.
- Strict workspace schema v2 with explicit platform targets, candidate-to-approved trust,
  committed-clean sources, bounded direct argv lifecycle, hostile-input rejection, and v1
  candidate conversion reports.
- Standalone exact-commit major migration with discovery, classification, recovery, translation,
  partial-install support, verified cutover, rerunnable resume, and rollback.
- Fork-aware fast-forward updates, deterministic generated-drift recovery, fresh-executable
  relaunch, and protected authored/staged/divergent state.
- Version-pinned GitHub Wiki tooling, agent context routes, contributor patch workflow, and the
  complete 1.0.0 operations/security/maintenance manual.
- Local and hosted test contracts for platform, output, planner, packages, theme, workspace,
  migration, update/fork, Wiki, Windows profile, Termux simulation, identity, and security.

### Changed

- Explicit package-enabled installs now refresh the complete selected rolling software set. Arch
  and WSL use the supported keyring-first sequence: synchronize databases and reconcile
  `archlinux-keyring`, then immediately run the full upgrade with every selected Pacman target as
  one fail-closed package phase. Termux retains its supported upgrade/install flow; npm globals,
  Python user packages, and the stable official Codex CLI on WSL are refreshed. Completed package,
  Codex, and final-verification markers no longer suppress that explicit refresh; unrelated
  configuration phases remain cached.
- Codex now separates the checksum-pinned official installer artifact from the desired CLI
  release, resolves OpenAI's current stable channel during explicit install, verifies the
  installed result, preserves settings/authentication, and never downgrades a newer valid version.
  Product source updates and health checks remain network-independent of the stable channel when
  Codex is already installed.
- Base installation now validates every typed action and executes each selected aggregate phase
  exactly once. Any phase failure stops before its marker and every later phase.
- Package transactions now propagate Pacman, `pkg`, npm, and pip failures and require positive
  manager verification of every named package before provenance is recorded. The exact
  Corepack/Pacman `pnpm` shim collision pauses at a reviewable checkpoint without overwriting or
  deleting either path; ambiguous collisions stop protected.
- Added an explicit, dry-runnable `packages repair-provenance` recovery that removes only exact
  manager-disproved ownership claims, preserves durable evidence and unrelated provenance, and
  invalidates phase `20-packages` for verified reconciliation.
- Canonical checkout, command, settings, state, cache, helper, Neovim namespace, theme, profile,
  schema, and active source identity now use `j3w1zsh`.
- Default tmux session is `j3w1zsh`; `tma` remains the bounded multi-client picker and is exposed
  through `j3w1zsh attach`.
- Long-form operations moved from the repository `docs/` tree into the exact compatible Wiki
  commit named by `wiki-lock.json`.
- Legacy migration accepts both the former redirect URL and the renamed canonical repository URL
  for the preserved source checkout while rejecting every unrelated origin before mutation.
- Major-migration resolver and workspace-comparison directories now use exact script-owned
  registration, ownership markers, and non-interactive cleanup, including write-protected Git
  objects, without making permanent recovery generations eligible for automatic removal.
- Normal-runtime comparison and staging directories now use one process-registered,
  parent-scoped, prefix-validated, marker-owned cleanup primitive. Update/fork dry-runs remove
  non-writable fetched Git objects without a TTY prompt while recovery and user paths remain
  ineligible for forced recursive cleanup.
- Exact migration acquisition now creates a full-history `main` checkout with a resolvable
  `origin/main`, even when canonical main advances beyond the pinned migration target. A guarded
  tracking-repair mode fixes the affected shallow `[gone]` state without changing HEAD, authored
  files, branch configuration, packages, user configuration, or permanent recovery data.
- `doctor` now checks the locally resolvable Git upstream without making a network request, and
  updater classification returns the stable protected-state error for a missing upstream.
- Wiki publication now validates existing pages against their exact lock-derived filenames, so
  rerunning publication remains idempotent for required names that contain meaningful hyphens.
- The Windows current-user Nerd Font adapter now treats an exact pinned legacy file as already
  satisfied, installs changed pins beside older files under a SHA-256-addressed filename, and
  uses unique marker-owned download staging. It never overwrites an in-use or mismatched font,
  while the owned HKCU registration and single Windows Terminal fragment remain reconcilable.

### Removed

- Writing-oriented active identity, command aliases, namespaces, host artifacts, and current
  examples after verified migration.
- Legacy screenshots and pen artwork. New captures remain pending human privacy review.
- Any general plugin or arbitrary third-party execution surface.
