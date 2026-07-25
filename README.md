# dotfiles

Personal dev environment: nvim, zsh, tmux, git, Claude Code. Linux-first,
macOS-aware. Built on **vim-plug + coc.nvim** (not lazy.nvim/native-LSP — a
deliberate choice; coc gives full C++/Python/Go IDE support with minimal setup).
zsh via **zim** (fast loader) + **starship** prompt.

## Install

```bash
git clone https://github.com/shahar3000/dotfiles.git ~/dotfiles && ~/dotfiles/install.sh
```

After it finishes, run `exec zsh` (or reconnect) to land in the configured shell.

### What install.sh does
One command, **idempotent** (safe to re-run). It never runs `sudo` itself — when
root is needed it prints the exact command in a banner and waits for you to run it.
1. symlinks configs first (so you get your dotfiles even if a later step fails)
2. ensures brew prerequisites (curl/git/unzip/compiler) — admin step if missing
3. installs **Homebrew** (canonical `/home/linuxbrew` when possible, else `~/.homebrew`)
4. `brew install`s tools: neovim, vim, **node** (coc/LSP), **python** (pynvim for
   vimspector), git-delta, bat, fzf, ripgrep, jq, universal-ctags, eza, zoxide,
   starship, tmux, herdr, gopls (llvm separate/best-effort)
5. installs **zim** (zsh loader) + vim-plug + nvim plugins
6. makes **zsh** the login shell (`sudo usermod`, else a guarded `~/.bashrc` hand-off)
7. prompts (TTY only) for git identity, vimwiki path, tmux clipboard target

`SKIP_PACKAGES=1 ./install.sh` skips all installs and only symlinks + local config.

llvm (C++ toolchain, several GB) installs on its own step after the core tools; if
it fails (e.g. small disk) it's non-fatal — coc-clangd fetches its own clangd.

On first `nvim` launch, coc auto-installs `coc-clangd`/`coc-pyright`/`coc-go`.

## Nerd Font (required for icons)

The starship prompt, vim-airline, and the tmux status line all use **Nerd Font
glyphs** (git-branch icons, language logos, powerline triangle separators). You
need **JetBrainsMono Nerd Font Mono** set in your terminal — a clean, highly
readable monospace coding font (Nerd Font-patched). Without it those glyphs show
as tofu boxes (the configs still work, they just look wrong).

- **macOS / native Linux desktop** — `install.sh` installs the font automatically
  (brew cask on macOS; `~/.local/share/fonts` + `fc-cache` on Linux). Then set
  your terminal's font to `JetBrainsMono Nerd Font Mono`.

### Nerd Font on WSL / Windows Terminal

In WSL the font lives on **Windows**, not inside Linux — `install.sh` can't set
it, so do this once on Windows:

1. Install the font (either):
   - download `JetBrainsMono.zip` from
     <https://github.com/ryanoasis/nerd-fonts/releases/latest>, extract, select
     the `JetBrainsMonoNerdFontMono-*.ttf` files → right-click → **Install**, **or**
   - `winget search JetBrainsMono` (look for the Nerd Font entry) then
     `winget install --id <that id>`.
2. Windows Terminal → `Ctrl+,` → your WSL profile → **Appearance** →
   **Font face** → `JetBrainsMono Nerd Font Mono`.

Until then everything still works — you'll just see tofu boxes where icons/
triangle separators should be.

## Layout

| Path | Purpose |
|------|---------|
| `nvim/vimrc` | main editor config (symlinked to `~/.vimrc`; vim + nvim share it) |
| `nvim/init.vim` | 3-line shim: sources `~/.vimrc` |
| `nvim/coc-settings.json` | coc / LSP settings |
| `nvim/after/ftplugin/` | per-filetype settings (symlinked to `~/.vim/after`) |
| `vimspector/` | per-language debug config templates (copy to project as `.vimspector.json`) |
| `shell/zshrc`, `shell/zshenv` | zsh config (`zshenv` = env/PATH for all shells) |
| `shell/zimrc` | zim module list (plugins: autosuggestions, fast-syntax-highlighting, fzf-tab, history-substring-search) |
| `starship/starship.toml` | prompt config (Nerd Font icons; symlinked to `~/.config/starship.toml`) |
| `tmux/tmux.conf` | tmux config |
| `herdr/config.toml` | herdr (agent multiplexer) config — gruvbox theme, tmux-like keys (symlinked to `~/.config/herdr/config.toml`) |
| `git/gitconfig` | git config + delta |
| `claude/settings.json` | Claude Code settings (portable subset; use your own Anthropic account) |
| `claude/statusline.sh` | custom statusline (symlinked to `~/.claude/statusline.sh`; needs `jq`) |
| `CHEATSHEET.md` | keybindings per tool |

## Notes

- **git identity, vimwiki path, tmux clipboard** are prompted by `install.sh` and
  stored in untracked local files (`~/.gitconfig` global, `~/.vimrc.local`, `~/.tmux.local.conf`).
- **Machine-local zsh overrides** go in `~/.zshrc.local` (untracked, sourced last).
- Re-run `./install.sh` any time — it only does what's missing.
