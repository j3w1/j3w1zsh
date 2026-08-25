# ✦ J3W1ZSH WORKSTATION — ARCH / WSL / TERMUX QUICK REFERENCE

> Neovim · Markdown · Zsh · tmux · Codex in WSL / remote Codex from Termux on Android

| CONTROL | KEY |
| :--- | :--- |
| Neovim leader | `Space` |
| Open / close guide | `Space ?` |
| Close focused guide | `q` |
| Discover mappings | `Space`, then pause |

> **Lost in Neovim?** Press `Esc` twice.
> **Lost in tmux?** Press `Ctrl-a`, then `?`.
> **Lost in Codex?** Enter `/help`.

---

## ◆ NEOVIM — ESSENTIAL LOOP

| KEY | ACTION |
| :--- | :--- |
| `i` / `a` | Insert before / after cursor |
| `o` / `O` | New line below / above |
| `jk` or `Esc` | Return to Normal mode |
| `Space w` | Save |
| `Space q` | Close window |
| `Space Q` | Close without saving |
| `u` / `Ctrl-r` | Undo / redo |
| `.` | Repeat last change |
| `:wq` | Save and quit |
| `:qa` / `:qa!` | Quit all / force quit all |

## ◆ MOVE, SELECT & EDIT

| KEY | ACTION |
| :--- | :--- |
| `h j k l` | Left, visual down/up, right |
| `w` / `b` / `e` | Next / previous / word end |
| `0` / `^` / `$` | Start / first text / end |
| `gg` / `G` | File top / bottom |
| `{` / `}` | Previous / next paragraph |
| `Ctrl-u` / `Ctrl-d` | Half-page up / down |
| `zz` | Center current line |
| `v` / `V` | Character / line selection |
| `Ctrl-q` | Rectangular Visual Block |
| `gv` | Reselect last selection |
| `dd` / `yy` | Delete / yank line |
| `p` / `P` | Paste after / before |
| `ciw` | Replace word |
| `diw` / `yiw` | Delete / yank word |
| `ci"` / `ci(` | Replace inside quotes / parens |
| `vip` | Select paragraph |
| `gqap` | Reflow paragraph |

> Operators combine with motions: `d3w`, `y$`, `c}`.

## ◆ SYSTEM CLIPBOARD

| KEY | ACTION |
| :--- | :--- |
| `Ctrl-c` | Copy line / visual selection |
| `Ctrl-v` | Paste from Windows or Android |
| `Ctrl-q` | Visual Block (moved from Ctrl-v) |
| `"+y` / `"+p` | Explicit system copy / paste |

## ◆ SEARCH, FILES & BUFFERS

| KEY | ACTION |
| :--- | :--- |
| `/text` | Search forward |
| `n` / `N` | Next / previous match |
| `*` / `#` | Search word forward / backward |
| `Esc` | Clear search highlight |
| `:%s/a/b/gc` | Replace all, with confirmation |
| `Space f f` | Find file |
| `Space f g` | Search text in files |
| `Space f b` | List open buffers |
| `Space f r` | Recent files |
| `Space f h` | Search Neovim help |
| `]b` / `[b` | Next / previous buffer |
| `Space b d` | Close current buffer |
| `:e file.md` | Open or create file |

## ◆ EDITOR WINDOWS & FILE TREE

| KEY | ACTION |
| :--- | :--- |
| `Space e` | Toggle right file tree |
| `Space e f` | Reveal current file |
| `Ctrl-h/j/k/l` | Focus adjacent window |
| `Ctrl-w v` / `s` | Vertical / horizontal split |
| `Ctrl-w =` | Equalize sizes |
| `Ctrl-w c` | Close focused window |

### In the tree

| KEY | ACTION |
| :--- | :--- |
| `Enter` or `o` | Open file / expand folder |
| `a` / `r` / `d` | Create / rename / delete |
| `x` / `c` / `p` | Cut / copy / paste |
| `H` / `I` | Hidden / ignored files |
| `R` | Refresh |
| `g?` | All tree mappings |
| `q` | Close tree |

## ◆ COMPLETION & SPELLING

| KEY | ACTION |
| :--- | :--- |
| `Ctrl-Space` | Show suggestions |
| `Ctrl-n` / `Ctrl-p` | Next / previous suggestion |
| `Enter` | Accept suggestion |
| `Ctrl-e` | Close suggestions |
| `]s` / `[s` | Next / previous misspelling |
| `Space s s` or `z=` | Suggested corrections |
| `Space s a` or `zg` | Add word to dictionary |
| `Space s u` or `zug` | Undo added word |
| `:setlocal spell!` | Toggle spelling |
| `:spellinfo` | Loaded dictionaries |

> Completion sources: spell, buffer, paths, snippets, LSP.

## ◆ MARKDOWN & NOTES

| KEY | ACTION |
| :--- | :--- |
| `Enter` | Follow/create link |
| `Backspace` | Return to previous note |
| `Tab` / `Shift-Tab` | Next / previous link |
| `]]` / `[[` | Next / previous heading |
| `Space m n` | New Markdown note |
| `Space m t` | Cycle task status |
| `Space m l` | Link visual selection |
| `Space m T` | Format table |
| `Space m b` | Return to previous note |
| `Space m r` | Toggle rendered Markdown |
| `Space m f` | Format file / selection |
| `Space z` | Distraction-free writing |

| MARKDOWN | SYNTAX |
| :--- | :--- |
| Heading | `# Heading` |
| Bold / italic | `**bold**` / `*italic*` |
| Link | `[label](page.md)` |
| Code | `` `inline` `` or fenced block |
| List / task | `- item` / `- [ ] task` |
| Quote / divider | `> quote` / `---` |

## ◆ LSP & SIMPLE CODING

| KEY | ACTION |
| :--- | :--- |
| `gd` | Go to definition |
| `gr` | Find references |
| `K` | Hover documentation |
| `Space c r` | Rename symbol |
| `Space c a` | Code action |
| `]d` / `[d` | Next / previous diagnostic |
| `Space m f` | Format |
| `:LspInfo` | Active language servers |

## ◆ NEOVIM TERMINAL

| KEY / COMMAND | ACTION |
| :--- | :--- |
| `:terminal` | Open shell in a buffer |
| `Ctrl-\\ Ctrl-n` | Terminal → Normal mode |
| `i` | Resume terminal input |
| `Ctrl-w h/j/k/l` | Leave terminal window |
| `exit` or `Ctrl-d` | Close shell |
| `:bd!` | Close terminal buffer |

## ◆ ZSH / TERMINAL

| KEY | ACTION |
| :--- | :--- |
| `Ctrl-c` | Cancel running command |
| `Ctrl-l` | Clear screen |
| `Ctrl-r` | Search command history |
| `Ctrl-a` / `Ctrl-e` | Start / end of command |
| `Alt-b` / `Alt-f` | Previous / next word |
| `Ctrl-w` | Delete previous word |
| `Ctrl-u` / `Ctrl-k` | Delete before / after cursor |
| `Tab` | Complete command / path |
| `Ctrl-d` | Exit when line is empty |

| COMMAND | ACTION |
| :--- | :--- |
| `j3w1zsh edit` | Open Documents in Neovim |
| `v file` | Open file in Neovim |
| `pwd` / `cd path` | Show / change directory |
| `ls` / `ll` / `la` | List files |
| `z name` | Jump to frequent folder |
| `extract file` | Extract common archive |
| `sudo` then `Esc Esc` | Add sudo to command (Windows WSL only) |

## ◆ TMUX — PREFIX IS CTRL-A

> Press `Ctrl-a`, release it, then press the second key.

| KEY | ACTION |
| :--- | :--- |
| `tn` | Create / attach the `j3w1zsh` session |
| `ta` / `tma` | Choose any tmux session |
| `Ctrl-a c` | New window |
| `Ctrl-a 1…9` | Select window |
| `Ctrl-a n` / `p` | Next / previous window |
| `Ctrl-a \|` / `-` | Split right / below |
| `Ctrl-a h/j/k/l` | Focus pane |
| `Ctrl-a H/J/K/L` | Resize pane |
| `Ctrl-a z` | Zoom / restore pane |
| `Ctrl-a d` | Detach session |
| `Ctrl-a r` | Reload tmux config |
| `Ctrl-a ?` | Show all tmux bindings |

### tmux copy mode

| KEY | ACTION |
| :--- | :--- |
| `Ctrl-a [` | Enter copy mode |
| `v` / `V` | Character / line selection |
| `y` | Copy to Windows or Android clipboard |
| `q` | Leave copy mode |
| Mouse drag | Select and copy |

## ◆ CODEX CLI — START & RESUME

> Codex runs locally in Windows WSL. From Termux on Android, run `j3w1zsh remote attach` and use Codex
> inside the selected WSL tmux session.

| COMMAND | ACTION |
| :--- | :--- |
| `codex` | Interactive session here |
| `codex "task"` | Start with a prompt |
| `codex -C path` | Choose working directory |
| `codex --search` | Enable live web search |
| `codex resume` | Pick a saved session |
| `codex resume --last` | Resume most recent |
| `codex fork` | Fork a saved session |
| `codex doctor` | Diagnose installation |
| `j3w1zsh reset-phase 70-codex` | Reapply the pinned Codex CLI release |
| `codex --help` | Complete CLI help |

## ◆ CODEX — INSIDE A SESSION

| INPUT | ACTION |
| :--- | :--- |
| `/help` | Show available commands |
| `/status` | Session/model/context status |
| `/model` | Select model / reasoning |
| `/permissions` | Review execution permissions |
| `/review` | Review current changes |
| `/compact` | Compress long context |
| `/usage` | View plan usage |
| `Ctrl-c` | Cancel current operation |
| `Ctrl-d` | Exit when input is empty |

> Project rules belong in `AGENTS.md`; one-off needs go in the prompt.
> Avoid dangerous sandbox-bypass flags.

## ◆ GIT — DAILY MINIMUM

| COMMAND | ACTION |
| :--- | :--- |
| `git status` | See changed files |
| `git diff` | Review unstaged changes |
| `git diff --staged` | Review staged changes |
| `git add file` | Stage selected file |
| `git commit` | Commit staged changes |
| `git log --oneline -10` | Recent history |
| `git restore --staged file` | Unstage safely |

> Review `git diff` before committing. Avoid destructive resets.

## ◆ HEALTH & RECOVERY

| KEY / COMMAND | ACTION |
| :--- | :--- |
| `Space n h` | Neovim health report |
| `Space n l` | Lazy plugin manager |
| `:checkhealth` | Diagnose Neovim |
| `:Lazy sync` | Sync/update plugins |
| `:messages` | Recent Neovim messages |
| `:verbose map KEY` | Find mapping source |
| `:set option?` | Inspect an option |
| `:pwd` | Neovim working directory |

---

> **Flow:** `j3w1zsh edit` → edit → `Space w` → terminal/tmux → Codex
> **Safety:** Normal mode = commands. Insert mode = writing.
