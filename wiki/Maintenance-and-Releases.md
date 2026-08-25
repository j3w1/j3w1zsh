# Maintenance and Releases

Maintainers keep every behavior change narrow, tested, documented, and reproducible. The final local contract is:

```bash
tests/run.sh
git diff --check
git status --short
```

Review the complete diff, tracked filenames, executable modes, JSON schemas, generated logo derivative, bootstrap bytes, and checksums. Hosted evidence must identify the exact head and distinguish Ubuntu, official Arch container, Windows, simulated Termux, migration/update/fork, and pinned-Wiki jobs.

## Wiki publication

The owner publishes the full reviewed Wiki before merge, verifies the Wiki commit is reachable, and updates `wiki-lock.json` in the code PR. Contributor PRs validate the pinned commit but do not need Wiki push rights. Contributors provide Wiki patches based on the pinned OID; an owner publishes them and updates the lock through code review.

## 1.0.0 gate

Merge the exact verified PR with a merge commit. Verify the resulting `main` OID and hosted jobs. Then stop for real WSL and Termux migration evidence against that exact OID. Simulation is not device acceptance.

If either device fails, preserve evidence and correct through a new branch/PR. The new merge OID becomes the release candidate. Only after both devices pass may the owner create annotated `v1.0.0` and a GitHub Release with byte-identical verified assets/checksums. Tagging, release, deployment, and branch cleanup are separate authority.
