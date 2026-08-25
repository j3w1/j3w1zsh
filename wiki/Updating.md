# Updating

`j3w1zsh update` classifies the branch, upstream, remotes, repository identity, worktree, index, untracked files, and ahead/behind/divergence before mutation.

```bash
j3w1zsh update --dry-run --json
j3w1zsh update
j3w1zsh update --configure-upstream
```

Dry-run uses `git ls-remote` and disposable comparison data; it does not fetch into the checkout or change local refs. Real execution fetches only after protected-state checks and fast-forwards only a tracking branch that is neither ahead nor divergent.

The current branch must have a locally resolvable upstream. A missing or `[gone]` upstream stops with exit 21 and stable error code `missing_upstream`; the updater does not invent a tracking ref. Installations from the affected early migration candidate use the guarded `--repair-tracking` procedure in [Migrating from the Former Project](Migrating-from-the-Former-Project) before running update.

The exact generated Neovim lock drift allowlist may be byte- and patch-preserved and repaired. Staged, deleted, renamed, untracked, unknown, and authored changes stop with exit 21. No update rebases, resets, merges divergent history, force-pushes, removes packages, starts workspace lifecycle, changes credentials, or runs a full Arch upgrade.

Fork `origin` is never changed. A canonical `upstream` is recognized or added only with `--configure-upstream` and confirmation. Exact fork/canonical relations are reported.

After a successful fast-forward, update relaunches the freshly checked-out executable before framework/state reconciliation. Active workspace status is reported without running project lifecycle.

The Git fast-forward and post-pull reconciliation are deliberately separate boundaries. If a package manager or later phase fails after the fast-forward, the checkout may already be at the new verified commit, but the failed phase is not marked complete and no later phase runs. Correct the reported condition and rerun the normal installer from the pending phase; update never runs workspace lifecycle while doing so.

An installation affected by the pre-release false package-provenance defect must first fast-forward to the corrected executable under the normal protected update rules. Then use the exact-target, manager-verified `packages repair-provenance` procedure in [Package Layers and Presets](Package-Layers-and-Presets), resolve any displayed Corepack/Pacman checkpoint without automatic deletion, and rerun from `20-packages`. Do not edit the ledger manually or infer package ownership from an executable on `PATH`.
