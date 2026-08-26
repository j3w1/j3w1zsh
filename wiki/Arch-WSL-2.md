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

The current-user JetBrains Mono Nerd Font is verified against the SHA-256 pin before registration. An existing regular, non-reparse legacy font with that exact digest is already satisfied and is never rewritten, including while Windows Terminal has it open. New installations and future changed pins use a SHA-256-addressed filename beside preserved older files; the owned HKCU font value advances only to verified bytes. j3w1zsh does not automatically prune an older font. Download staging is unique to the running process and is removed only after its exact ownership marker and temporary parent validate.

Only after the font registration, fragment, stable profile GUID, and single lowercase scheme reconcile successfully does the adapter create the `windows-terminal-restart` checkpoint. Close every Windows Terminal window, reopen the lowercase `j3w1zsh - arch wsl` profile, and rerun the same installer to complete phase `50-theme`.

Do not copy Windows credentials into WSL. GitHub and Codex authentication remain interactive and user-owned.

A package-free migration intentionally leaves phase `70-codex` unselected. After the corrected checkout/upstream and normal update are verified, real-device acceptance separately runs `command -v codex` and `codex --version`; the migration does not infer Codex health from a preserved authentication session.
