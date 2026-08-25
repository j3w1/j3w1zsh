# Remote j3w1zsh Hosts

Remote access uses private Tailscale SSH plus tmux. It does not expose a public SSH port, change router forwarding, migrate credentials, or alter host power policy.

On native Arch or WSL:

```bash
j3w1zsh remote setup-host
```

This is the only flow that offers to install Tailscale. It requires explicit confirmation, enables `tailscaled`, and starts user-owned Tailscale authentication.

On Termux:

```bash
j3w1zsh remote configure-client --host HOST --user USER
j3w1zsh remote status --json
j3w1zsh remote attach [SESSION]
```

Settings are `J3W1ZSH_REMOTE_HOST`, `J3W1ZSH_REMOTE_USER`, and `J3W1ZSH_REMOTE_ATTACH_COMMAND`. Host, user, command, and session tokens are strictly bounded before SSH. `tma` attaches an additional tmux client; it never disconnects a client already attached from another device. Session deletion always targets the exact name and requires confirmation.
