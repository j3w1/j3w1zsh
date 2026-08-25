# Workspace v1-to-v2 Migration

The former `bloody-writer.workspace.json` schema described a WSL-only contract. The isolated converter recognizes only valid schema v1 input and maps it into an explicit `targets.wsl` declaration:

```bash
j3w1zsh workspace migrate ./bloody-writer.workspace.json \
  --output ./j3w1zsh.workspace.json \
  --dry-run
```

The converter:

- renames the profile and minimum-product fields;
- converts versions into runtime requirements;
- converts system files into managed files;
- renames the base capability;
- writes `review_state: candidate`; and
- emits a sidecar report of transformed, defaulted, omitted, and unresolved fields.

It never imports `.env` bytes, SQLite contents, credentials, histories, caches, machine identity, or private evidence. Output is never overwritten. A human must review every target, package, adapter, lifecycle argv, port, and capability, then commit and explicitly approve the profile before apply.

Supporting native Arch or Termux requires a separately reviewed explicit target. The converter never infers their authority from the old WSL declaration.
