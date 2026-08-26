# Source and Version References

`versions.env` is the tracked source for product, Oh My Zsh, the immutable official Codex installer artifact and checksum, and Nerd Font version/checksum anchors. The Codex installer version is an implementation-security pin, not the desired CLI version. During an explicit install, that verified installer receives the exact current stable release resolved from OpenAI's official stable channel. The reviewed Neovim plugin commits live in the tracked `lazy-lock.json`; normal sessions use a device-local runtime copy.

Downloads use authoritative upstream sources and checksums where a static asset is fetched. Pacman, `pkg`, selected npm globals, selected Python user packages, Codex CLI, and similar user-facing software follow their rolling official sources under the explicit-install platform rules. A valid manually installed version newer than the currently resolved stable requirement is preserved rather than downgraded. Product version, migration/bootstrap checksum, reviewed font bytes, Neovim lock, intentional Oh My Zsh revision, and the verified installer artifact remain exact release inputs.

The product takes high-level inspiration from established terminal, shell, and security-oriented Linux workflows while remaining an independent project. It is not affiliated with or endorsed by Oh My Zsh, Arch Linux, BlackArch, Termux, OpenAI, Microsoft, GitHub, Tailscale, or the Nerd Fonts project. Names identify compatibility or upstream sources only.

Compatible Wiki content is pinned by exact commit in `wiki-lock.json`. Source code must never point at an unreachable Wiki commit, and agents must not silently replace the pin with latest content.

The repository is MIT licensed. See `LICENSE` for the authoritative terms.
