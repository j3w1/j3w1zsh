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

## Workspace recovery

Each manifest/platform generation owns managed-file backups, optional SQLite pre-setup bytes, trust, and phase markers. A changed manifest creates a new generation. Failed lifecycle actions leave later markers absent for explicit resume.

## Major migration recovery

Major migration creates a permanent mode-0700 recovery root with inventory, patches, untracked bytes, unique-ref bundle where needed, pre-cutover paths, relocated legacy state, journal, and rollback evidence. Recovery data is never pruned automatically, and rollback never deletes the new checkout.

Only exact registered resolver and workspace-comparison temporary directories are automatically cleaned. Their guarded cleanup does not make the recovery root or any recovery generation eligible for recursive removal.
