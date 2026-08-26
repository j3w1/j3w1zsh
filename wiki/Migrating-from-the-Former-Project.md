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

The former repository URL includes the exact early-install identity `https://github.com/1w3j/bloody-writer.git`. The preserved source checkout may use that historical `1w3j/bloody-writer` identity, its exact HTTPS no-`.git` or SSH form, the corresponding later-owner `j3w1/bloody-writer` forms, or the renamed canonical `j3w1/j3w1zsh` forms. These historical URLs identify the source only: acquisition still uses only `https://github.com/j3w1/j3w1zsh.git`. Redirect following, owner or repository guessing, suffix matching, malformed URLs, and every unrelated origin are rejected before target or state mutation. Migration does not require or perform a source-origin rewrite.

Dry-run ref resolution and interrupted-workspace comparison use only script-created temporary directories with exact parent/name validation and an ownership marker. Cleanup is non-interactive even for write-protected Git objects. These ephemeral directories are distinct from permanent migration recovery generations, which are never removed automatically.

Acquisition verifies the exact target first, then independently resolves and materializes the observed canonical `origin/main`. The selected local `main` remains at the exact requested target even if canonical main has advanced, but the target must be an ancestor of canonical main. The acquired checkout has full history, a resolvable upstream, and no `[gone]` status; a later normal `j3w1zsh update` may fast-forward it under the usual protected-state rules.

Authored, staged, untracked, or unique-commit states stop with exit 21 before acquire or cutover. Exact allowlisted generated Neovim lock drift may continue only after its bytes and patch are preserved.

Known settings translate to `J3W1ZSH_EDIT_ROOT`, `J3W1ZSH_GITHUB_KEY`, and generalized remote host/user/attach settings. Unknown settings stop at a manual review checkpoint and are never sourced.

Old phase markers are evidence only. New phases are recorded only after new verification. The old command and XDG identity are deactivated only after the new command, links, status, platform, doctor, theme, tmux, Neovim, and host adapter pass.

Rollback restores old locations and user paths from the manifest, remains rerunnable-safe, and deliberately does not delete `~/j3w1zsh`.

## Repairing the affected `[gone]` tracking state

An installation acquired by the earlier 1.0.0 candidate may be healthy at its exact commit while `git status --short --branch` reports `main...origin/main [gone]`. Do not roll back, reset, reclone, delete the checkout, or remove either migration recovery generation merely to repair tracking.

Download and checksum-verify the bootstrap from the corrected immutable final-main OID. Confirm that `CURRENT_40_HEX_OID` is the unchanged local HEAD and that `FINAL_40_HEX_OID` is the corrected canonical main, then inspect and dry-run the bounded repair:

```bash
./migrate-to-j3w1zsh.sh \
  --repair-tracking \
  --target ~/j3w1zsh \
  --expected-commit CURRENT_40_HEX_OID \
  --expected-upstream-commit FINAL_40_HEX_OID \
  --dry-run
```

The repair requires a clean local `main`, exact canonical HTTPS origin, the existing `origin`/`refs/heads/main` branch configuration, the exact expected HEAD, and a missing or already exact `origin/main`. A disposable guarded comparison proves that the preserved HEAD is an ancestor of the exact expected canonical main. Dirty, staged, untracked, unique, divergent, unexpected-origin, unexpected-config, or mismatched-ref state stops without repair.

After reviewing the plan, rerun without `--dry-run`. The operation materializes only the exact tracking ref and, for the affected shallow checkout, restores the full canonical history. It verifies that HEAD, the checked-out tree, and local Git configuration did not change. User configuration, packages, phase state, and permanent migration recoveries are outside the repair mutation surface.

Then verify and use the ordinary updater:

```bash
git -C ~/j3w1zsh status --short --branch
git -C ~/j3w1zsh rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'
git -C ~/j3w1zsh rev-parse '@{upstream}'
j3w1zsh doctor --json
j3w1zsh update --dry-run
j3w1zsh update --dry-run --json
j3w1zsh update --yes
```

A package-free WSL migration deliberately reports phase `70-codex` as `unselected`; that is not tracking-repair failure. Codex acceptance remains a later user-owned check with `command -v codex` and `codex --version`. Termux never installs a local Codex binary.
