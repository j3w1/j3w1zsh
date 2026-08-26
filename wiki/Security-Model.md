# Security Model

j3w1zsh is fail-closed around platform authority, filesystem destinations, Git history, workspace lifecycle, and private state.

## Secrets and identity

Private keys, tokens, passwords, OAuth/Codex sessions, GitHub CLI hosts data, histories, private projects, and databases are not committed, migrated, printed, hashed, or transformed. Public keys still require an explicit local reason.

## Platform boundary

Detection occurs before mutation. Production has no platform-forcing escape hatch. Test overrides work only in test mode. Termux rejects root, privilege wrappers, system services, absolute managed destinations, shell evaluation, and host-level adapters.

## Files and Git

Managed destinations remain under the intended home or one exact platform adapter. Conflicts are preserved. Updates stop on authored/staged/untracked/deleted/renamed/ahead/divergent state and fast-forward only. Migration captures protected bytes and unique refs before stopping.

Recursive forced cleanup is confined to the normal-runtime and standalone-migration guarded ephemeral helpers. Both require exact registration, a resolved allowed parent, an exact basename prefix shape, a non-symlink directory, and a regular ownership marker before removal. The runtime marker is process-owned. Persistent recovery generations, generated product paths, user destinations, workspaces, config/state/cache roots, and repository checkouts cannot be registered through this interface.

The Windows current-user font adapter hashes installed bytes before deciding to write. It rejects reparse-point or non-regular installed destinations, accepts an exact pinned legacy file without replacement, and installs a changed verified pin under its full SHA-256 filename rather than overwriting an in-use fixed path. A mismatched file at the expected content-addressed destination is preserved and stops the adapter. Older font files are not automatically removed. Downloads use a unique process path and checksum verification; recursive cleanup requires the exact in-memory parent, basename, directory type, and ownership-marker token.

Package reconciliation fails closed: each aggregate phase runs once, a child failure stops all later phases, and provenance requires positive exact-manager verification. Known Corepack/Pacman `pnpm` shims become a manual checkpoint; ambiguous path ownership is protected. The bounded provenance repair revalidates exact named records and manager state, preserves evidence, and cannot install, remove, or alter packages.

Rolling refresh is an explicit install boundary. Arch uses one complete `-Syu --needed` transaction and never a sync-only partial-upgrade command; Termux uses its supported unprivileged upgrade path. Product update never silently broadens into a full platform upgrade. npm and pip receive validated direct package-name argv only. Codex stable-channel metadata must contain a strict stable release tag; a checksum-pinned official installer artifact installs that exact resolved release and verifies the result. A newer valid installed Codex is preserved, while an unclassifiable version stops for owner review. Health checks do not contact upstream version services.

## Workspace execution

Profiles are strict JSON. Apply requires candidate review, explicit platform target, tracked-clean profile and sources, displayed digest, explicit trust, supported unqualified executable, and direct argv. Shells, `env`, privilege wrappers, traversal, symlinks, dirty indirection, arbitrary system destinations, and unsupported executables are rejected.

Development commands are displayed and never auto-started. Environment guards parse selected `.env` fields without sourcing the file and enforce loopback/local/SQLite constraints where declared.
