# Windows Terminal

Reference config for [Windows Terminal](https://aka.ms/terminal) — the terminal
to use on a Windows host that reaches this setup via **WSL** and/or **SSH**.

It only configures the Windows-side renderer/launcher: font, a gruvbox-dark
palette, `COLORTERM=truecolor`, and WSL + SSH profiles. Everything inside Linux
(zsh, tmux, nvim, starship) is handled by `install.sh` on the Linux/WSL side.

## Why this isn't symlinked

`install.sh` runs inside Linux/WSL and can't reliably write to the Windows
filesystem, and Windows Terminal keeps its config at a fixed per-package path.
So this file is **copied/merged in by hand, once** — not auto-installed.

## Setup (fresh Windows box, start to finish)

Run these in **PowerShell** (open Start → type "PowerShell").

1. **Install WSL2 + Ubuntu** (skip if you only SSH out and won't use local Linux):
   ```powershell
   wsl --install -d Ubuntu
   ```
   Reboot if prompted. On first launch it asks you to create a Linux username +
   password — that's your account *inside* Ubuntu.

2. **Install Windows Terminal** (may already be present on Windows 11):
   ```powershell
   winget install Microsoft.WindowsTerminal
   ```

3. **Install the font on Windows** — `JetBrainsMono Nerd Font Mono` (see the repo
   root README's "Nerd Font on WSL / Windows Terminal" section for the exact
   download/winget steps). Do this before applying settings or you'll see tofu.

4. **Get this file onto Windows.** Either clone the repo in WSL and read it from
   `\\wsl$\Ubuntu\home\<you>\dotfiles\windows-terminal\settings.json`, or just
   open the file on GitHub and copy its contents.

5. **Apply the settings.** Open Windows Terminal → `Ctrl+,` → click
   **"Open JSON file"** (bottom-left) to open the live `settings.json`
   (`%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_*\LocalState\settings.json`).

   - **Fresh machine:** replace that file's entire contents with `settings.json`
     here, save. Windows Terminal reloads instantly.
   - **Existing setup you want to keep:** don't overwrite — merge only the pieces
     you want: copy the `"Gruvbox Dark"` entry into your `schemes`, set the font
     under `profiles.defaults`, and add the WSL/SSH profiles to `profiles.list`.

6. **Provision Linux.** Open the **Ubuntu (WSL)** profile (see "Daily use" below)
   and run the dotfiles installer once:
   ```bash
   git clone https://github.com/shahar3000/dotfiles.git ~/dotfiles && ~/dotfiles/install.sh
   ```
   Then `exec zsh`. Now WSL has your full zsh/tmux/nvim/starship setup.

## Daily use

- **Open a shell:** click the **`⌄` dropdown** next to the `+` tab button and pick
  a profile — `Ubuntu (WSL)` for local Linux, `dev desk (ssh)` to jump to the
  remote box. `Ubuntu (WSL)` is the default, so a plain new tab (`Ctrl+Shift+T`)
  opens it.
- **New tab:** `Ctrl+Shift+T` · **switch tabs:** `Ctrl+Tab`.
- **Split panes (Windows Terminal's own):** `Alt+Shift+D` duplicates the current
  pane. *Note:* once you're inside a remote/WSL session you'll usually let **tmux**
  manage panes (`Ctrl+b` prefix) instead — Windows Terminal splits and tmux splits
  are independent layers, so pick one per session to avoid confusion.
- **Copy/paste:** `Ctrl+Shift+C` / `Ctrl+Shift+V` (kept off the bare `Ctrl+C`/`V`
  so they don't clash with shell/tmux). Selecting text does **not** auto-copy
  (`copyOnSelect` is off), so tmux copy-mode keeps working.
- **Find in scrollback:** `Ctrl+Shift+F`.
- **Settings GUI:** `Ctrl+,` any time to tweak fonts/colors without editing JSON.

## After applying — check these

- **WSL profile GUID.** The `Ubuntu (WSL)` GUID here is the standard one WSL
  Ubuntu generates. If yours differs (different distro/name), Windows Terminal
  will show a duplicate Ubuntu profile. Fix: delete this one's `guid`/`source`
  block and instead just add `"colorScheme"`, `"font"`, and `"environment"` to
  the Ubuntu profile Windows Terminal already generated. Update `defaultProfile`
  to that GUID too.
- **SSH host.** Edit `commandline` in the `dev desk (ssh)` profile from
  `ssh dev-desk` to your actual host or `~/.ssh/config` alias.
- **True color.** Inside WSL/SSH run `echo $COLORTERM` — it should print
  `truecolor`. If not, the gruvbox hexes in nvim/tmux fall back to the 256-color
  palette (still fine, just less exact). The `environment` blocks here set it.

## What each part does

| Part | Purpose |
|------|---------|
| `profiles.defaults.font` | `JetBrainsMono Nerd Font Mono` for powerline glyphs / starship icons |
| `schemes → Gruvbox Dark` | the 16 ANSI colors in gruvbox hexes (used by plain-ANSI output even under true color) |
| `Ubuntu (WSL)` profile | local Linux; run `~/dotfiles/install.sh` inside it |
| `dev desk (ssh)` profile | one-tap SSH to the remote box (tmux+nvim run there) |
| `environment.COLORTERM` | guarantees nvim's `termguicolors` guard engages |
| `actions` | minimal `ctrl+shift+*` chords so they never collide with tmux (`ctrl+b`) |
