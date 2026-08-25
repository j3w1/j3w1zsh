# Theme Architecture

Themes are declarative JSON. They contain an ID, display name, named palette roles, and exactly 16 ANSI colors. They cannot execute code or supply templates.

The built-in `j3w1zsh` theme preserves:

- background `#000000`;
- foreground `#FFF1F1`;
- blood red `#B00020`;
- bright red `#FF334D`;
- selection, muted red, orange, blue, and semantic green roles.

Terminal ANSI green intentionally maps to red for the visual identity. Neovim semantic green remains green for meaningful success and diagnostic distinctions.

Renderers derive device-local Zsh, tmux, Neovim, Windows Terminal, and Termux artifacts under `~/.config/j3w1zsh/generated/theme/`. A manifest ties generated output to the source SHA-256. User themes live under `~/.config/j3w1zsh/themes/ID/theme.json` and pass the same strict validation.

```bash
j3w1zsh theme list
j3w1zsh theme show j3w1zsh
j3w1zsh theme apply j3w1zsh --dry-run
j3w1zsh theme current --json
```

The identity is original and independent. No fonts or third-party artwork are bundled.
