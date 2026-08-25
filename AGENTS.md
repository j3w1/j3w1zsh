# j3w1zsh agent instructions

## Purpose and authority

`j3w1zsh` is a public, reproducible shell-first workstation framework for native official Arch
Linux, official Arch Linux under WSL 2, and native Termux on Android. Preserve its true-black,
blood-red, and warm-white design while keeping installation safe, resumable, explicit, and
portable across those three supported targets.

The current tracked code, schemas, presets, `versions.env`, `wiki-lock.json`, compatible pinned
Wiki pages, and tests are the source of truth. Conversation, generated state, screenshots, and
the former product are not current authority.

Use this precedence:

1. explicit current owner authorization;
2. this file and the authorized task scope;
3. schemas, compatible pinned Wiki contract, and accepted repository policy;
4. current code, Git, configuration, and runtime evidence;
5. inference.

Stop rather than inventing a new business, security, schema, privilege, or release decision.

## Start every run

1. Read this file completely.
2. Inspect `git status --short --branch`, remotes, execution surface, and relevant worktrees.
3. Preserve unrelated human and agent work. Never assume a clean checkout, platform, or shell.
4. Select the topic in `agent-context.json`; load only its required code paths and compatible
   Wiki pages. Use `j3w1zsh wiki context TOPIC` when the pinned Wiki is locally available.
5. Trace `bin/j3w1zsh` through the selected `scripts/commands/`, `scripts/lib/core/`, platform
   adapter, and phase before changing user-facing behavior.
6. State scope, diagnose first, implement the smallest complete change, add focused regression
   coverage, update affected Wiki/root contract, and run the verification below.

If a decision exists only in conversation, encode the authorized decision in tracked code,
tests, and the appropriate contract as part of the same change.

## Security and privacy

- Never commit or print private keys, passwords, passphrases, tokens, OAuth/Codex sessions,
  GitHub CLI authentication, private repositories, documents, histories, caches, logs,
  installation IDs, personal absolute paths, or private database content.
- Public keys and Git identity still require an explicit documented reason before tracking.
- Keep privilege narrow, visible, planned, and platform-specific. Never add passwordless sudo.
- Never automate WSL unregister, home deletion, public SSH exposure, router/firewall changes,
  power-policy changes, secret migration, or arbitrary third-party execution.
- Validate every managed or recovery target under the intended home or named host adapter.
- Use authoritative downloads, immutable commits/releases where practical, and verified static
  checksums. Never recommend piping mutable `main` directly into a shell.

## Platform and installer contract

- Detect Termux first and reject root. It uses `pkg` and user-home destinations only.
- WSL requires WSL 2 plus official Arch. It alone owns WSL/systemd and Windows-host adapters.
- Native Arch requires official Arch, a normal user, and functional `sudo`; it never installs an
  OS, partitions, bootloaders, users, networking, firewalls, or host services.
- Reject WSL 1, derivatives, generic Linux, macOS, PRoot targets, and unsupported platforms
  before any mutation. Platform forcing is test-mode-only.
- Every phase is idempotent, fingerprinted, atomically marked only after verification, and
  resumable across user-owned checkpoints.
- Back up conflicts before replacement. Never silently overwrite user settings, authentication,
  SSH, Codex, GitHub, or personal files.
- Every mutating command uses the bounded action planner and typed adapters. `plan` and
  `--dry-run` must not write state, trust, cache, project files, Git refs, Wiki checkouts, or
  package-manager state.
- `update` remains fast-forward-only, protects authored/staged/divergent work, preserves known
  repair bytes, respects fork ownership, and relaunches the newly checked-out executable.

## Configuration and compatibility

- Personal shell values belong only in `~/.config/j3w1zsh/settings.zsh`; never overwrite it.
- Presets, packages, themes, workspaces, Wiki locks, and agent routes are strict JSON and never
  execute code.
- Keep reviewed Neovim commits in tracked `lazy-lock.json`; runtime state is device-local. Use
  `scripts/update-neovim-lock.sh` for deliberate lock updates.
- Keep Oh My Zsh, Codex, and Nerd Font pins in `versions.env`.
- Protect `Space ?`, responsive cheat-sheet behavior, platform clipboard mappings, `Ctrl-q`
  Visual Block, tmux `Ctrl-a`, exact-session targeting, and `tma` multi-client/confirmed-kill.
- Do not claim native Android Codex support; Termux reaches the official CLI on a private remote
  host through SSH/tmux.
- Old identifiers are allowed only by the exact migration identity allowlist and must never
  return to active commands, paths, examples, schemas, themes, profiles, or help.

## Documentation and Wiki

Root human documents remain concise. Detailed operations live in the compatible Wiki commit
named by `wiki-lock.json`; `agent-context.json` is the minimum-context route map.

Normal contributor PRs validate the existing pin. Wiki changes are proposed as a patch based on
the pinned OID; only an explicitly authorized owner publication may push Wiki history and update
the code lock. Code must never point to an unreachable Wiki commit.

Public screenshots require human pixel inspection for usernames, hostnames, private paths,
repositories, tokens, fingerprints, and notifications. Text scans alone are insufficient.

## Verification and change discipline

Run before completion:

```bash
tests/run.sh
git diff --check
git status --short
```

Behavior changes require focused tests. Preserve Bash/Zsh and PowerShell parsing where
applicable, ShellCheck, strict JSON/schema tests, isolated-home backup/link/restore tests,
platform dispatch, zero-mutation planning, secret/personal-path scans, current-identity scans,
brand derivative verification, Neovim lock parsing, migration rollback, update/fork safety, and
Wiki-pin validation.

Review the complete diff and executable modes. Report evidence as verified, inferred,
unavailable, deferred, blocked, or failed. Green CI is evidence, not authorization or proof.
Keep coherent commits; do not rewrite unrelated work or published history. Do not publish a tag
or release until the release contract's exact WSL and Termux device gates pass.
