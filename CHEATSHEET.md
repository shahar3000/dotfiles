# Cheatsheet

Keybindings & commands **this config actually defines**. Leader is `,`.

---

## nvim / vim

### Files & search (fzf + ripgrep)
| Key | Action |
|-----|--------|
| `,p` | `:Files` — fuzzy find files |
| `,b` | `:Buffers` — list the buffer entries shown at the top-left |
| `[b` / `]b` | previous / next buffer (built into Neovim; configured here for Vim) |
| `,w` | `:Windows` — list actual splits, not buffers |
| `gT` / `gt` | previous / next tab page (shown at the top-right) |
| `,T` | `:Tags` (project) · `,BT` buffer tags |
| `,L` / `,BL` | `:Lines` / buffer lines · `,gl` = BLines on word under cursor |
| `F3` | `:Rg` (ripgrep search) · `F4` = Rg on word under cursor |
| `F5` | `:FGrep` (git grep) · `F6` = FGrep on word under cursor |
| `F9` | `:Format` (format buffer via LSP) |
| `,C` / `,BC` | `:Commits` / buffer commits |
| Inside fzf | `Ctrl-y/e` preview up/down · `Ctrl-b/f` page · `Ctrl-p` toggle preview |

### LSP / code (coc — clangd, pyright, gopls)
| Key | Action |
|-----|--------|
| `gd` `gr` `gy` | go to definition / references / type-definition |
| `,xd` `,xr` `,xi` | definition / references / implementation (tagstack-aware — `Ctrl-O`/`Ctrl-I` history works) |
| `g<space>d/r/y/i` | same, in a **vertical split** |
| `g<space><space>d/r/y/i` | same, in a **horizontal split** |
| `T` | hover documentation |
| `,rn` | rename symbol |
| `,qf` | quick-fix current line |
| `,ci` `,co` | call hierarchy tree: **i**ncoming / **o**utgoing calls |
| in call tree | `t` expand/collapse a node (drill deeper) · `<CR>` jump to call site · `M` collapse all · `f` filter · `<Esc>` close |
| `[e` `]e` | prev / next **error** |
| `[w` `]w` (or `[g` `]g`) | prev / next diagnostic (any) |
| `:Format` | format buffer · `:OR` organize imports · `:Fold` |
| `<space>a` | diagnostics list · `<space>o` outline · `<space>s` workspace symbols |
| `<space>e` | extensions · `<space>c` commands |
| `<space>j` `<space>k` | next / prev item in a CocList · `<space>p` resume last list |

### Debugging (vimspector)
Put a `.vimspector.json` in the project root (templates in `vimspector/`).
| Key | Action |
|-----|--------|
| `,dc` | continue |
| `,db` | toggle breakpoint · `,dB` conditional · `,df` function bp |
| `,dn` | step over |
| `,di` | step into · `,do` step out |
| `,dr` restart · `,ds` stop · `,dp` pause · `,dq` reset |

(Debug maps are under `<leader>d*` — NOT bare `d*`, which would shadow vim's delete operator.)

### Git in editor (fugitive + vimagit)
| Key | Action |
|-----|--------|
| `gb` | `:Git blame` |
| `gs` | `:vertical G show` |
| `,M` | `:Magit` — magit-style staging/commit UI (vimagit) |
| `F8` | `:Gvdiffsplit` (diff current file) |
| `:Git`, `:G` | any git command |

### Windows / navigation
| Key | Action |
|-----|--------|
| `Ctrl-w z` | **zoom** current split fullscreen (toggle) — like tmux prefix z |
| `Shift-arrows` | move across vim splits **and** tmux panes (tmux-navigator) |
| `F10` | NERDTree toggle (finds current file) |
| `Ctrl-k` | close all coc floating windows in Normal or Insert mode |

### Editing
| Key | Action |
|-----|--------|
| `gc` | comment/uncomment (motion: `gcc` line, `gcap` paragraph) — vim-commentary |
| `,F` | toggle clang-format-on-save |
| open `file.c:42` | jumps to line 42 (vim-fetch) |
| `F2` | toggle Copilot Chat in Normal or Insert mode (when enabled) |
| `F12` | toggle `paste`+`spell` together (verbatim-paste code blocks, no autoindent mangling) — shown in the statusline while on. Persists across inserts until you press `F12` again; turning it back **off** only works from Normal mode |
| `Ctrl-l` (insert, Copilot suggestion showing) | accept Copilot's ghost-text suggestion — opt-in, see README |

### Marks — multi-color highlighting (vim-mark)
Highlight several words at once, each in its own color — great for tracing
identifiers across a file or log. (Distinct from `hlsearch`, which is one pattern.)
| Key | Action |
|-----|--------|
| `,m` | mark/unmark word under cursor (cycles colors) |
| `,R` | mark by **regex** (prompts) — remapped from vim-mark's default `,r` to protect `,rn` |
| `,n` | clear mark under cursor · (not on a mark) clear all |
| `,*` `,#` | next / prev occurrence of the **current** mark |
| `,/` `,?` | next / prev occurrence of **any** mark |

### Markdown / vimwiki  (see the "why" note below)
| Key / cmd | Action |
|-----------|--------|
| `<CR>` on a list item | vimwiki: new bullet/number (native) |
| `<C-Space>` | vimwiki: toggle checkbox (native) |
| `zM` / `zr` | fold all / unfold one level (vimwiki `expr` folding) |
| `F7` / `:MarkdownPreview` | toggle live browser preview (markdown-preview.nvim) |

**Why it's wired this way:** vimwiki assigns `.md` files the filetype `vimwiki`
(verified). `g:vimwiki_filetypes=['markdown']` adds the `markdown` filetype too
(→ `vimwiki.markdown`) so markdown-preview activates on wiki files. Folding is
owned by vimwiki (`g:vimwiki_folding='expr'`) — we do **not** use
vim-markdown-folding (it would conflict). bullets.vim is scoped to
`['markdown','text','gitcommit']` so it never double-handles vimwiki's native lists.

---

## tmux (prefix = `Ctrl-b`)

| Key | Action |
|-----|--------|
| `prefix \|` | split vertical (keep cwd) |
| `prefix -` | split horizontal (keep cwd) |
| `prefix c` | new window (keep cwd) |
| `prefix h` | toggle synchronize-panes (type in all panes) |
| `prefix r` | reload tmux.conf |
| `prefix b` | toggle status bar |
| `Alt-arrows` | switch pane (no prefix) |
| `Shift-arrows` | switch pane / vim split transparently (tmux-navigator) |
| copy-mode | vi motions (`h/j/k/l`, `w/b`, `/`,`?`,`n`, `Ctrl-u/d`, `g/G`) |
| copy-mode | `v` select · `V` line-select · `r` rectangle · `y` copy · `Esc` cancel |
| copy-mode | `H` / `L` jump to top / bottom of visible screen |

---

## herdr (agent multiplexer · prefix = `Ctrl-b`)

Defaults mirror tmux; only `split_vertical` is remapped to `|` for parity.

| Key | Action |
|-----|--------|
| `prefix \|` | split vertical |
| `prefix -` | split horizontal |
| `prefix c` | new tab · `prefix n` / `prefix p` next / prev tab |
| `prefix h/j/k/l` | focus pane · `prefix shift+h/j/k/l` swap pane |
| `prefix z` | zoom pane · `prefix x` close pane |
| `prefix [` | copy-mode |
| `prefix r` | resize mode · `prefix shift+r` reload config |
| `prefix w` | workspace picker · `prefix shift+n` new workspace |
| `prefix b` | toggle sidebar · `prefix q` detach · `prefix ?` help |

---

## zsh

| Item | Action |
|------|--------|
| autosuggestions | grey suggestion from history; `→` / `End` to accept |
| fast-syntax-highlighting | valid commands green, errors red, as you type |
| `↑` / `↓` | history-substring-search: cycle history matching typed prefix |
| `Tab` | fzf-tab: fuzzy completion menu with bat/eza preview |
| `Ctrl-t` | fzf file picker with preview |
| `Ctrl-r` | fzf history search |
| `Alt-c` | fzf cd into subdirectory |
| `z foo` | zoxide: jump to most-used dir matching "foo" · `zi` = fuzzy pick |
| `vim` | aliased to `nvim` |
| `ll` | long list (eza if installed, else `ls -alF`) |
| `bat file` | syntax-highlighted cat (`batcat` on Debian) |
| `show_csv f.csv` | pretty-print a CSV in less |
| `rezsh` | reload zshenv + zshrc |

Prompt: **starship** (async git branch/status, fast in large repos). Loader: **zim**.

## PowerShell 7

| Key | Action |
|-----|--------|
| `Tab` | open completion menu for commands, files/directories, and arguments |
| `Shift-Tab` | move backward through completion choices |
| `Ctrl-r` | fuzzy-search persistent command history with fzf |
| `git … Tab` | Git commands, branches, remotes, tags, and paths (posh-git loads on first use) |

---

## git

| Alias | Expands to |
|-------|-----------|
| `git st` | status |
| `git co` / `br` / `ci` | checkout / branch / commit |
| `git df` / `dc` | diff / diff --cached |
| `git lg` | pretty one-line graph log |
| `git dag` | detailed graph log with author/email |
| `git l` | compact colored log |
| `git diff-side` | side-by-side diff (delta) |
| `git r` | fetch origin + rebase onto the remote's default branch (main/master) |

**delta** is the pager → all `git diff` / `git show` / `git log -p` output is
syntax-highlighted. `n` / `N` jump between files in a diff.

---

## Claude Code statusline
`claude/statusline.sh` shows: **path** (blue) · **git branch** (green) ·
**model** (yellow) · **context %** (cyan). Needs `jq`.
