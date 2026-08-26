# Termux on Android

Termux support targets the native main environment from a current official Termux distribution. Platform ID is `termux`. Root and PRoot installation targets are rejected; PRoot is only an optional companion selected by the full preset.

Termux uses `pkg` and user-level adapters. It may manage Android storage permission, matching-source Termux:API integration, colors, clipboard, and user-home files. It rejects `sudo`, `doas`, `su`, systemd, absolute managed destinations, shell evaluation, firewall/router changes, and host adapters before any state or package mutation.

No unofficial Android Codex binary is installed. Use the official WSL CLI through private SSH/tmux:

```bash
j3w1zsh remote configure-client --host HOST --user USER
j3w1zsh remote attach
```

Keep Termux and Termux:API from the same signing source. Android storage, clipboard, font, and color behavior must be verified on a real device before a release is accepted.

A package-enabled explicit install runs the supported `pkg upgrade` flow and then ensures the complete selected `pkg` set before refreshing selected npm globals and user-level Python packages. It never invokes root or a privilege wrapper. Product `update` does not imply a full Termux upgrade.
