# Contributing

Contributions are welcome when they preserve `j3w1zsh` safety, reproducibility, and portability
across native official Arch Linux, official Arch Linux under WSL 2, and native Termux on Android.

Read [AGENTS.md](AGENTS.md) even when working without an agent. Use `agent-context.json` and the
compatible Wiki commit pinned by `wiki-lock.json` for the smallest task-specific context.

## Development

```bash
git clone https://github.com/j3w1/j3w1zsh.git
cd j3w1zsh
tests/run.sh
```

Use `./install.sh --dry-run` before a real install. Exercise configuration, migration, update,
and workspace behavior in disposable homes/repositories rather than against personal state.

## Pull requests

- Explain the problem, authority, user-visible behavior, and platform impact.
- Keep phases idempotent, verified, and resumable.
- Add focused tests and update the affected root/Wiki contract.
- Update [CHANGELOG.md](CHANGELOG.md) for user-visible changes.
- Preserve unrelated work and never include credentials, private data, personal paths, or
  generated device state.
- Distinguish local, hosted, simulated, and real-device evidence.

Run:

```bash
tests/run.sh
git diff --check
git status --short
```

## Wiki changes

Normal contributors do not need Wiki push rights. Base a patch on the exact OID in
`wiki-lock.json`; an owner publishes it, verifies reachability, and updates the code lock in a
reviewable commit. A lock naming an unreachable or incompatible Wiki commit fails CI.

## Theme and screenshot changes

Theme changes must keep declarative roles and all generated renderers synchronized. Explain
contrast and deliberate terminal-versus-semantic color differences.

Screenshots must be genuine new captures and receive human pixel inspection for private or
identifying content before publication. Do not relabel historical captures.

## Security reports

Do not open a public issue for credential exposure or a remotely exploitable installer flaw.
Follow [SECURITY.md](SECURITY.md).
