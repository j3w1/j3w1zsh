# Security policy

## Supported version

Security fixes apply to the current `main` branch and latest tagged release.

## Report a vulnerability

Use GitHub private vulnerability reporting. Do not include live tokens, private keys,
passphrases, personal documents, database bytes, or third-party secrets.

For an accidentally published secret:

1. revoke or rotate it immediately;
2. remove it from the working tree and published history;
3. review relevant provider, SSH, and authentication logs;
4. report the incident privately.

Deleting a secret only from the latest commit is insufficient after publication.

## Trust boundary

Inspect the immutable checkout, `bin/j3w1zsh`, selected platform adapter, action plan, and phases
before installation on a sensitive machine. Begin with `./install.sh --dry-run`.

- WSL and native Arch privilege is explicit, narrow, planned, and foreground-only.
- Termux rejects root, privilege wrappers, system destinations, and host-level adapters before
  state or package mutation.
- Conflicting managed files are backed up; user settings and credentials are never overwritten.
- Workspace apply requires an approved tracked regular committed-clean profile, committed-clean
  referenced sources, exact digest display, explicit trust, and bounded adapters/direct argv.
- Update is fast-forward-only and stops on authored, staged, deleted, renamed, unique, or
  divergent work.
- Migration preserves recoverable bytes and unique Git refs before stopping; cutover happens
  only after new verification and rollback remains rerunnable.
- `plan` and `--dry-run` may inspect selected state and remote refs but create no durable state,
  trust, cache, host configuration, package operation, or Git ref.

The detailed compatible contract is the pinned Wiki [Security Model](https://github.com/j3w1/j3w1zsh/wiki/Security-Model).
