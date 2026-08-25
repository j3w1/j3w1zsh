# Troubleshooting

## Exit 20

A user-owned external action is pending—commonly WSL restart, Windows Terminal reload, Android permission, companion app, authentication, or reviewed settings. Follow the exact message and rerun the same command. `--yes` never bypasses a manual host checkpoint.

## Exit 21

Git or migration found protected authored, staged, untracked, deleted, renamed, ahead, divergent, or unique-commit state. Inspect the listed paths and recovery root. Do not reset, clean, rebase, or force-push merely to continue.

## Unsupported platform

Run `j3w1zsh platform --json`. WSL must be version 2 and official Arch. Native Linux must be official Arch. Termux must be the native main environment and not root.

## Missing package in `--no-packages`

The flag intentionally acquires nothing. Install the reported prerequisite through the platform owner or rerun without the flag after reviewing the plan.

## Candidate workspace cannot apply

Review all fields, ensure the current platform has an explicit target, set `review_state` to `approved`, commit the profile and referenced sources cleanly, then apply and confirm the displayed SHA-256.

## Wiki pin unavailable

Normal synchronization follows only `wiki-lock.json`. A pending or unreachable commit is a publication/lock error; do not silently follow latest. Owners publish the Wiki first, verify reachability, then update the code lock.
