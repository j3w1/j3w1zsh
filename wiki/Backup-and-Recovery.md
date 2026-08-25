# Backup and Recovery

## Configuration backup

```bash
j3w1zsh backup --dry-run
j3w1zsh backup
j3w1zsh restore BACKUP_ID --dry-run
j3w1zsh restore BACKUP_ID
```

Archives contain only selected j3w1zsh-managed configuration paths. Restore validates every archive path, rejects traversal and unmanaged entries, preserves displaced current paths, then restores. Installer conflict backups use exact manifests and may also be restored.

## Update recovery

Allowlisted generated Neovim lock drift is saved as exact bytes plus a binary patch under `~/.local/state/j3w1zsh/update-recovery/` before repair. Unknown or authored state is never repaired automatically.

An explicitly approved false package-provenance repair stores the exact removed rows, negative manager verification, corrected code commit, and invalidated phase-20 marker under `~/.local/state/j3w1zsh/packages/repairs/`. That evidence is permanent local recovery data. Unrelated ledger rows and all package-manager state remain unchanged.

## Workspace recovery

Each manifest/platform generation owns managed-file backups, optional SQLite pre-setup bytes, trust, and phase markers. A changed manifest creates a new generation. Failed lifecycle actions leave later markers absent for explicit resume.

## Major migration recovery

Major migration creates a permanent mode-0700 recovery root with inventory, patches, untracked bytes, unique-ref bundle where needed, pre-cutover paths, relocated legacy state, journal, and rollback evidence. Recovery data is never pruned automatically, and rollback never deletes the new checkout.

Only exact registered resolver, workspace-comparison, and tracking-comparison temporary directories are automatically cleaned. Their guarded cleanup does not make the recovery root or any recovery generation eligible for recursive removal.

Tracking repair for the affected shallow `[gone]` checkout is not rollback. It verifies the exact current and canonical commits, repairs only full Git history plus `refs/remotes/origin/main`, and preserves HEAD, checkout files, local Git configuration, package/user state, and every migration recovery generation.
