# Source and Version References

`versions.env` is the tracked source for product, Oh My Zsh, Codex release and immutable installer checksum, and Nerd Font version/checksum anchors. The reviewed Neovim plugin commits live in the tracked `lazy-lock.json`; normal sessions use a device-local runtime copy.

Downloads use authoritative upstream sources and checksums where a static asset is fetched. Package versions otherwise follow the rolling official Arch and Termux repositories under their platform rules.

The product takes high-level inspiration from established terminal, shell, and security-oriented Linux workflows while remaining an independent project. It is not affiliated with or endorsed by Oh My Zsh, Arch Linux, BlackArch, Termux, OpenAI, Microsoft, GitHub, Tailscale, or the Nerd Fonts project. Names identify compatibility or upstream sources only.

Compatible Wiki content is pinned by exact commit in `wiki-lock.json`. Source code must never point at an unreachable Wiki commit, and agents must not silently replace the pin with latest content.

The repository is MIT licensed. See `LICENSE` for the authoritative terms.
