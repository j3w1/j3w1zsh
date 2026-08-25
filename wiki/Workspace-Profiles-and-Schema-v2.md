# Workspace Profiles and Schema v2

The canonical filename is `j3w1zsh.workspace.json`. Schema v2 separates platform authority into explicit optional `targets.arch`, `targets.wsl`, and `targets.termux` keys. At least one target is required. Supporting both native Arch and WSL requires both declarations; neither inherits privileged authority from the other.

Every target contains exact sections for packages, runtime requirements, required binaries/extensions, managed files, environment guards, direct-argv lifecycle, loopback ports, and capabilities.

Candidate profiles validate structurally and may be planned. Apply requires:

- `review_state: approved`;
- an explicit current-platform target;
- a regular tracked committed-clean profile;
- tracked committed-clean referenced sources within the project;
- an exact displayed manifest SHA-256;
- explicit trust; and
- supported direct-argv executables.

State generations are keyed by workspace ID, complete manifest SHA-256, and selected platform. Development commands are displayed but never started automatically.

Termux permits only user-home `home-file` mappings and bounded user package managers. Arch/WSL additionally permit the exact `php-conf` system adapter; there is no general `/etc` destination.
