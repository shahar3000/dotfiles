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

## Install

1. **Install the font on Windows** (see the repo root README's "Nerd Font on
   WSL / Windows Terminal" section): `JetBrainsMono Nerd Font Mono`.

2. **Install Windows Terminal** if needed:
   ```powershell
   winget install Microsoft.WindowsTerminal
   ```

3. **Apply the settings.** Open Windows Terminal → `Ctrl+,` → click
   **"Open JSON file"** (bottom-left) to see where your `settings.json` lives
   (`%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_*\LocalState\settings.json`).

   - **Fresh machine:** replace that file's contents with `settings.json` here.
   - **Existing setup you want to keep:** don't overwrite — instead merge the
     pieces you want: copy the `"Gruvbox Dark"` entry into your `schemes`, set
     the font under `profiles.defaults`, and add the WSL/SSH profiles to
     `profiles.list`.

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
