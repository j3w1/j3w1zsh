# Arch WSL 2

WSL support requires the official Arch distribution running as WSL 2. Platform ID is `wsl`. WSL 1, derivatives, and generic Linux are rejected before mutation.

The WSL-only adapter owns:

- the one-time fresh-root bootstrap;
- bounded `/etc/wsl.conf` reconciliation;
- systemd and Windows interop checkpoints;
- Windows Terminal theme/profile integration; and
- the official Codex CLI flow.

When a host restart is required, state is persisted and the installer exits 20 with exact PowerShell commands. Rerun the same installer after reopening WSL.

The Windows Terminal adapter uses a fragment instead of rewriting `settings.json`. Migration preserves a discovered existing profile GUID and updates the lowercase profile in place to avoid duplicates.

Do not copy Windows credentials into WSL. GitHub and Codex authentication remain interactive and user-owned.

A package-free migration intentionally leaves phase `70-codex` unselected. After the corrected checkout/upstream and normal update are verified, real-device acceptance separately runs `command -v codex` and `codex --version`; the migration does not infer Codex health from a preserved authentication session.
