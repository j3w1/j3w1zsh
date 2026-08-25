# j3w1zsh plan

Planning resolves the platform, strict configuration layers, preset, user overrides, selected workspace target, and theme into a deterministic action graph.

Every action records:

- ID, phase, and bounded kind;
- platform and declaring layer;
- package manager or managed destination;
- reason;
- privilege, confirmation, and user-owned checkpoint requirements;
- mutation flag; and
- verification rule.

Allowed action kinds are package operation, file reconciliation, host adapter, direct-argv lifecycle, manual checkpoint, and verification. No action accepts a shell expression.

```bash
j3w1zsh plan
j3w1zsh plan ./j3w1zsh.workspace.json --preset minimal
j3w1zsh plan --json
```

Plan and every `--dry-run` may inspect files, installed packages, Git state, and remote refs. They do not write state, cache, trust, project files, Git refs, Wiki checkouts, packages, or host configuration. When a remote comparison genuinely needs objects, a disposable system-temporary Git repository is removed afterward.
