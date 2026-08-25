# Security Model

j3w1zsh is fail-closed around platform authority, filesystem destinations, Git history, workspace lifecycle, and private state.

## Secrets and identity

Private keys, tokens, passwords, OAuth/Codex sessions, GitHub CLI hosts data, histories, private projects, and databases are not committed, migrated, printed, hashed, or transformed. Public keys still require an explicit local reason.

## Platform boundary

Detection occurs before mutation. Production has no platform-forcing escape hatch. Test overrides work only in test mode. Termux rejects root, privilege wrappers, system services, absolute managed destinations, shell evaluation, and host-level adapters.

## Files and Git

Managed destinations remain under the intended home or one exact platform adapter. Conflicts are preserved. Updates stop on authored/staged/untracked/deleted/renamed/ahead/divergent state and fast-forward only. Migration captures protected bytes and unique refs before stopping.

## Workspace execution

Profiles are strict JSON. Apply requires candidate review, explicit platform target, tracked-clean profile and sources, displayed digest, explicit trust, supported unqualified executable, and direct argv. Shells, `env`, privilege wrappers, traversal, symlinks, dirty indirection, arbitrary system destinations, and unsupported executables are rejected.

Development commands are displayed and never auto-started. Environment guards parse selected `.env` fields without sourcing the file and enforce loopback/local/SQLite constraints where declared.
