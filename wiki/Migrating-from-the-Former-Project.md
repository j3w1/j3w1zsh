# Migrating from the Former Project

The standalone `scripts/legacy/migrate-to-j3w1zsh.sh` migrates installations of Bloody Writer into the independent lowercase j3w1zsh identity. Recovery data may retain the former names; active commands and paths do not after successful verification.

Never execute a mutable `main` URL. Download the script and checksum from the immutable final release OID, verify and inspect them, then run:

```bash
./migrate-to-j3w1zsh.sh \
  --target-ref FINAL_40_HEX_OID \
  --expected-commit FINAL_40_HEX_OID \
  --source ~/projects/bloody-writer \
  --dry-run
```

The migration discovers complete, partial, absent, generated-drift, authored-dirty, staged, untracked, local-commit, and divergent states. It creates a mode-0700 recovery root, inventory, binary patches, untracked-byte copies, unique-ref bundle, and pre-cutover path snapshots without printing content.

The preserved source checkout may still use the former repository URL or may already use the renamed canonical `j3w1/j3w1zsh` URL. Every unrelated origin is rejected before target or state mutation.

Dry-run ref resolution and interrupted-workspace comparison use only script-created temporary directories with exact parent/name validation and an ownership marker. Cleanup is non-interactive even for write-protected Git objects. These ephemeral directories are distinct from permanent migration recovery generations, which are never removed automatically.

Authored, staged, untracked, or unique-commit states stop with exit 21 before acquire or cutover. Exact allowlisted generated Neovim lock drift may continue only after its bytes and patch are preserved.

Known settings translate to `J3W1ZSH_EDIT_ROOT`, `J3W1ZSH_GITHUB_KEY`, and generalized remote host/user/attach settings. Unknown settings stop at a manual review checkpoint and are never sourced.

Old phase markers are evidence only. New phases are recorded only after new verification. The old command and XDG identity are deactivated only after the new command, links, status, platform, doctor, theme, tmux, Neovim, and host adapter pass.

Rollback restores old locations and user paths from the manifest, remains rerunnable-safe, and deliberately does not delete `~/j3w1zsh`.
