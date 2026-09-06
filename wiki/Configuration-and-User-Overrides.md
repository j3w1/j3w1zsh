# Configuration and User Overrides

Canonical local paths are:

```text
~/.config/j3w1zsh/
~/.local/state/j3w1zsh/
~/.cache/j3w1zsh/
```

`~/.config/j3w1zsh/settings.zsh` is trusted, user-owned shell configuration. The installer creates it once and never overwrites it. Keep personal values there, including edit root, explicitly selected GitHub key path, and remote connection tokens.

All other configuration layers are strict JSON and are never sourced or evaluated:

- `packages.json` for package additions/exclusions;
- user themes under `themes/ID/theme.json`;
- workspace profiles;
- Wiki lock; and
- agent routes.

Generated theme output is device-local under `generated/theme/`. Package provenance, phases, migrations, workspace generations, backups, update recovery, and Wiki caches are state—not source—and are never committed.

Credentials, `.ssh`, Claude Code and Codex authentication/session/plugin state, GitHub CLI authentication, Tailscale state, histories, private repositories, caches, and database contents remain where their owning application keeps them. j3w1zsh neither copies nor logs them.

## Claude Code

On native Arch (best effort) and WSL, selecting the `claude` preset feature installs the official
`@anthropic-ai/claude-code` npm package through the ordinary package phase. Claude Code itself is
never launched during installation, `doctor`, phase 90, or `j3w1zsh claude status`.

`~/.claude/settings.json`, `~/.claude.json`, project `.claude/` directories, `.mcp.json`, login
credentials, session history, MCP servers, plugins, and trust decisions all remain entirely
user-owned. j3w1zsh does not create, parse, modify, copy, or report their contents. Authenticate
and configure the CLI with Claude Code's own commands. `j3w1zsh claude status --json` reports only
the current platform, whether `claude` is available on `PATH`, and safe local npm package metadata.

Anthropic's current setup documentation explicitly names Ubuntu/Debian Linux and Windows via WSL,
not native Arch. The native Arch path is therefore a j3w1zsh best-effort integration, not an
Anthropic platform-support claim.

## WSL Codex portable baseline

`~/.codex/config.toml` is a Codex user configuration file, never a whole-file j3w1zsh artifact.
On WSL, j3w1zsh continuously reconciles exactly one public, portable key:

```text
mcp_servers.openaiDeveloperDocs.url
```

The tracked baseline contains the public OpenAI Developer Docs MCP endpoint. The following are
first-install defaults only and are never reset after a config exists:

```text
approval_policy
sandbox_mode
sandbox_workspace_write.network_access
```

Models, reasoning/UI preferences, features, project trust, absolute paths, personal MCPs, unknown
future settings, authentication, OAuth/session state, installation IDs, plugins, and conversation
data are user-owned. The reconciler edits only the allowlisted portable key using a round-trip
TOML editor. It never broad-rewrites config text, copies user values into state, or exposes them
through status output.

Use the bounded controls below:

```bash
j3w1zsh codex status --json
j3w1zsh codex disable openaiDeveloperDocs
j3w1zsh codex reset openaiDeveloperDocs --yes
```

`disable` records only the public key ID and leaves the current Codex configuration untouched;
this is the durable opt-out when a missing portable key would otherwise be added. `reset --yes`
is explicit recovery: it re-enables management and sets only that public URL to the current
tracked baseline. `status` reports bounded counts and public key/action names, never arbitrary
Codex values. If a future j3w1zsh baseline retires the managed key, it removes it only when the
local value still equals the last public baseline it applied; a differing value remains user-owned.

Malformed TOML, an unavailable TOML editor, a symlink, or an unexpected config/state file type
stops reconciliation before a config/state write and leaves phase 70 incomplete for owner review.
The CLI installation may already be present, but no phase completion record claims a successful
configuration reconciliation.
