# Updating

`j3w1zsh update` classifies the branch, upstream, remotes, repository identity, worktree, index, untracked files, and ahead/behind/divergence before mutation.

```bash
j3w1zsh update --dry-run --json
j3w1zsh update
j3w1zsh update --configure-upstream
```

Dry-run uses `git ls-remote` and disposable comparison data; it does not fetch into the checkout or change local refs. Real execution fetches only after protected-state checks and fast-forwards only a tracking branch that is neither ahead nor divergent.

The exact generated Neovim lock drift allowlist may be byte- and patch-preserved and repaired. Staged, deleted, renamed, untracked, unknown, and authored changes stop with exit 21. No update rebases, resets, merges divergent history, force-pushes, removes packages, starts workspace lifecycle, changes credentials, or runs a full Arch upgrade.

Fork `origin` is never changed. A canonical `upstream` is recognized or added only with `--configure-upstream` and confirmation. Exact fork/canonical relations are reported.

After a successful fast-forward, update relaunches the freshly checked-out executable before framework/state reconciliation. Active workspace status is reported without running project lifecycle.
