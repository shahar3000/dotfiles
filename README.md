# dotfiles

Personal dev environment: nvim, zsh/PowerShell, tmux/Herdr, git, Claude Code.
Supports native Windows as well as Linux, macOS, and WSL. Built on
**vim-plug + coc.nvim** (not lazy.nvim/native-LSP — a deliberate choice; coc
gives full C++/Python/Go IDE support with minimal setup). Unix shells use
**zsh** via **zim**; Windows uses **PowerShell 7**; both use **starship**.

## Native Windows

The Windows setup runs directly on Windows without WSL, MSYS2, or Cygwin.
It requires an internet connection and **App Installer / winget** (included
with current Windows 10/11 installations). The bootstrap installs Git first
because the repository cannot clone itself.
Open PowerShell **as Administrator** using the Windows account being configured,
then run:

```powershell
winget install --id Git.Git --exact --source winget --accept-package-agreements --accept-source-agreements
$env:Path = @(
  [Environment]::GetEnvironmentVariable("Path", "Machine"),
  [Environment]::GetEnvironmentVariable("Path", "User")
) -join ";"
git clone https://github.com/shahar3000/dotfiles.git "$HOME\dotfiles"
Set-Location "$HOME\dotfiles"
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

If launched from a non-elevated terminal, the installer requests Administrator
approval once before running winget. This avoids a Windows Package Manager bug
that can otherwise display repeated Explorer "no app associated" dialogs while
elevating individual MSI packages. Approve the prompt using the same Windows
account being configured.

The installer is idempotent and:

1. installs Windows Terminal, PowerShell 7, Git, Neovim, Starship, Herdr,
   posh-git completion, PSFzf history search, Claude Code, Copilot CLI,
   language runtimes, compilers, CLI tools, and JetBrainsMono Nerd Font through
   winget, PowerShell Gallery, or the official Herdr installer;
2. links the Windows configuration, backing up conflicting files first;
3. prewarms PowerShell 7's Starship and zoxide startup cache;
4. installs vim-plug, Neovim plugins, pynvim, black, and gopls;
5. configures Claude Code's status line without replacing other Claude settings;
6. installs Herdr's Claude integration;
7. validates required commands, PowerShell modules, editor plugins, coc language
   extensions, and the markdown-preview binary before reporting success.

The Windows PowerShell bootstrap installs PowerShell 7 and relaunches the setup
there, allowing unprivileged symbolic links when Windows Developer Mode is
enabled. Otherwise, the installer uses hard links and directory junctions,
falling back to copies only when linking is unavailable. Re-run the installer
after every pull unless its output says all managed paths are symbolic links;
Git replaces files during pulls, so hard links and copies must be refreshed. Use
`.\install.ps1 -SkipPackages` to relink configuration without package installs,
or add `-SkipPlugins` to avoid network-dependent plugin updates.

After installation, restart Windows Terminal, select its **PowerShell 7**
profile, and set **JetBrainsMono Nerd Font Mono** under profile Appearance.
Git identity and service authentication remain intentionally personal: configure
`~/.gitconfig.local`, then sign in to Claude Code, Copilot CLI, and
`:Copilot setup` in nvim if you enable the optional editor integration.
Launch the complete pane/agent environment with:

```powershell
herdr
```

Herdr replaces tmux natively through Windows ConPTY while retaining this
repository's `Ctrl+B` pane, tab, navigation, zoom, and Gruvbox configuration.

## Install

### Linux, macOS, and WSL

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
4. `brew install`s tools: zsh, neovim, vim, **node** (coc/LSP), **python**,
   git-delta, bat, fzf, ripgrep, jq, universal-ctags, eza, zoxide, starship, tmux,
   herdr, gopls (llvm separate/best-effort). Then pip-installs **pynvim**
   (vimspector) and **black** (Python formatting for coc-pyright) into that python.
5. installs **zim** (zsh loader) + vim-plug + nvim plugins
6. makes **zsh** the login shell (`sudo usermod`, else a guarded `~/.bashrc` hand-off)
7. prompts (TTY only) for git identity, vimwiki path, tmux clipboard target

`SKIP_PACKAGES=1 ./install.sh` skips all installs and only symlinks + local config.

llvm (C++ toolchain, several GB) installs on its own step after the core tools; if
it fails (e.g. small disk) it's non-fatal — coc-clangd fetches its own clangd.

On first `nvim` launch, coc auto-installs `coc-clangd`/`coc-pyright`/`coc-go`.

## Nerd Font (required for icons)

The starship prompt, the editor statusline (lualine in nvim, vim-airline in vim),
and the tmux status line all use **Nerd Font glyphs** (git-branch icons, language
logos, powerline triangle separators). You
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

### Clipboard on WSL

`install.sh` installs `win32yank.exe` into `~/.local/bin` as the clipboard
bridge nvim's `unnamedplus` (see `nvim/vimrc`) needs to reach the Windows
clipboard. If yanking/pasting in nvim fails with a `win32yank.exe` error
about `VCRUNTIME140.dll` not found, the Windows side is missing the
Visual C++ runtime that binary was built with — install it once on Windows
(not inside WSL):

1. Download and run <https://aka.ms/vc14/vc_redist.x64.exe>.
2. Restart WSL so interop picks up the new DLLs: from PowerShell,
   `wsl --shutdown`, then reopen your WSL terminal.

### Windows Terminal steals Ctrl+V / Ctrl+C from vim

Windows Terminal binds plain `Ctrl+V` to its own paste action and plain
`Ctrl+C` to copy-if-selected, both by default — so they never reach the app
running inside WSL. That breaks vim's builtin `Ctrl+V` (blockwise-visual
mode), and `Ctrl+C` is worse: if you have leftover selected text (e.g. from a
mouse drag) when you mean to kill a stuck process, Windows Terminal copies
instead of sending the interrupt, silently leaving the process running
instead of ever getting an actual `^C` there. Free them both up on Windows
(not inside WSL):

1. Windows Terminal → `Ctrl+,` → open `settings.json` (bottom-left) → find
   the `keybindings`/`actions` entries binding `ctrl+c`/`ctrl+v` (they look
   like `{ "id": "Terminal.CopyToClipboard", "keys": "ctrl+c" }` and
   `{ "id": "Terminal.PasteFromClipboard", "keys": "ctrl+v" }`) and delete
   both entries outright.
   - If your file has no such entries (some Windows Terminal versions only
     store *overrides* there, with the actual defaults hidden elsewhere),
     add unbind overrides instead — same effect:
     ```json
     { "id": null, "keys": "ctrl+v" },
     { "id": null, "keys": "ctrl+c" }
     ```
2. Save — Windows Terminal reloads config automatically, no restart needed.

`Ctrl+V`/`Ctrl+C` now always go straight to whatever's running in the pane
(vim, a shell command, etc). Copy/paste still work exactly as before via
`Ctrl+Shift+C` / `Ctrl+Shift+V` (or `Shift+Insert` to paste) — those bindings
are untouched.

## Copilot (optional)

[`github/copilot.vim`](https://github.com/github/copilot.vim) adds inline AI
ghost-text completion alongside coc — different job (generated code vs coc's
verified LSP completion), so both run together. Needs a subscription (Free
tier works), so it's **opt-in**: both platform installers ask once and remember
the answer in `~/.vimrc.local` (`g:copilot_enabled`). Flip that value and re-run
the relevant installer to change your mind.

On native Windows, `install.ps1` also installs the separate GitHub Copilot CLI
through winget. CLI and editor authentication remain separate.

First use: `:Copilot setup` once inside nvim to authenticate. `<Tab>` stays
coc's; Copilot accepts on `<C-l>`.

## Layout

| Path | Purpose |
|------|---------|
| `nvim/vimrc` | main editor config (symlinked to `~/.vimrc`; vim + nvim share it) |
| `nvim/init.vim` | small shim: sets runtimepath and sources `~/.vimrc` |
| `nvim/coc-settings.json` | coc / LSP settings |
| `nvim/after/ftplugin/` | per-filetype settings (symlinked to `~/.vim/after`) |
| `vimspector/` | per-language debug config templates (copy to project as `.vimspector.json`) |
| `shell/zshrc`, `shell/zshenv` | zsh config (`zshenv` = env/PATH for all shells) |
| `shell/zimrc` | zim module list (plugins: autosuggestions, fast-syntax-highlighting, fzf-tab, history-substring-search) |
| `powershell/Microsoft.PowerShell_profile.ps1` | native Windows shell profile (PSReadLine, Starship, zoxide, aliases) |
| `starship/starship.toml` | prompt config (Nerd Font icons; symlinked to `~/.config/starship.toml`) |
| `tmux/tmux.conf` | tmux config |
| `herdr/config.toml` | Linux/macOS herdr config — Gruvbox theme and tmux-like keys |
| `herdr/config.windows.toml` | native Windows Herdr config — PowerShell 7 through ConPTY |
| `git/gitconfig` | git config + delta |
| `git/gitignore_global` | global gitignore (symlinked to `~/.gitignore` via `core.excludesfile`) — tags, editor/OS cruft |
| `claude/settings.json` | Claude Code settings (portable subset; use your own Anthropic account) |
| `claude/statusline.sh` | custom statusline (symlinked to `~/.claude/statusline.sh`; needs `jq`) |
| `claude/statusline.ps1` | native Windows Claude Code status line |
| `install.ps1` | idempotent native Windows provisioning and configuration |
| `CHEATSHEET.md` | keybindings per tool |

## Notes

- **git identity, vimwiki path, Copilot opt-in, tmux clipboard** are prompted by
  `install.sh` and stored in untracked local files (`~/.gitconfig.local` — pulled
  in via `[include]` from the tracked gitconfig — `~/.vimrc.local`,
  `~/.tmux.local.conf`).
- **Machine-local zsh overrides** go in `~/.zshrc.local` (untracked, sourced last).
- Re-run `./install.sh` any time — it only does what's missing.
