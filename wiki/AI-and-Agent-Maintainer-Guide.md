# AI and Agent Maintainer Guide

Repository instructions and current tracked evidence are authority. Do not depend on old chat context.

1. Read `AGENTS.md` and inspect clean status, branch, worktrees, remotes, and platform.
2. Read `agent-context.json` and select one route.
3. Run `j3w1zsh wiki context TOPIC` to materialize only compatible pinned pages.
4. Trace the user-facing command through the core, command family, platform adapter, and phase before editing.
5. Preserve unrelated work and add focused regression tests.
6. Update authoritative root/Wiki content when behavior or operations change.
7. Run the repository verification contract and report exact limitations.

Do not use `wiki sync --latest` as agent authority. Default exclusions prevent screenshots, local `.wiki` checkouts, downloaded/generated state, unrelated fixtures, and legacy material from entering ordinary context.

Implementation and independent acceptance remain separate when the delivery workflow requires it. A changed head invalidates stale acceptance evidence. Green CI is execution evidence, not owner acceptance or merge/release authority.
