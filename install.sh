#!/usr/bin/env bash
# Provision a dev environment from a (near-)clean Linux/macOS box, then symlink
# configs. IDEMPOTENT: every step checks first, so re-running is safe and cheap.
#
# This script NEVER runs sudo itself. When something needs root (installing OS
# prereqs, creating the bottle-enabled brew prefix, setting the login shell) it
# prints the exact command in a loud banner and waits for you to run it in
# another terminal and press Enter. Everything else is user-local.
#
# What it does:
#   1. ensure brew prerequisites (curl/git/unzip/compiler) — admin step if missing
#   2. install Homebrew (canonical /home/linuxbrew when possible, else ~/.homebrew)
#   3. brew install CLI tools + node + language servers
#   4. install zim (zsh loader); starship/fzf/zoxide come from brew
#   5. make zsh the login shell (sudo usermod, else a guarded ~/.bashrc hand-off)
#   6. install vim-plug + nvim plugins
#   7. symlink dotfiles into $HOME (timestamped backups)
#   8. prompt for git identity / vimwiki path / tmux clipboard (TTY only)
#
# Usage: ./install.sh            (full run)
#        SKIP_PACKAGES=1 ./install.sh   (only symlink + local config; no installs)
set -uo pipefail   # NOT -e: we handle failures per-step so one hiccup can't abort provisioning

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
info() { printf '\033[1;34m>>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# The "Do you want to proceed? [y/n]" prompt is suppressed by passing `-y` to each
# `brew install` (below). This env var is unrelated to prompts: it stops a slow
# `git` auto-update of homebrew-core before every install — kept purely for speed.
export HOMEBREW_NO_AUTO_UPDATE=1

# This script NEVER runs sudo itself. When a privileged command is required,
# priv_step shows it in a loud banner and waits for you to run it in another
# terminal, then press Enter. (If already root, it just runs it. If stdin isn't
# a TTY — e.g. piped — it prints the command, warns, and continues so it can't hang.)
#   priv_step "why this is needed" "the exact command to run as root"
priv_step() {
	local why="$1" cmd="$2"
	if [ "${IS_ROOT:-0}" = "1" ]; then
		info "running (already root): $cmd"
		eval "$cmd"
		return $?
	fi
	# bright yellow-on-red banner so it can't be missed
	printf '\n\033[1;37;41m  ADMIN STEP NEEDED  \033[0m \033[1m%s\033[0m\n' "$why"
	printf '\033[1;33m  Run this in another terminal (with sudo), then come back:\033[0m\n'
	printf '\n    \033[1;36m%s\033[0m\n\n' "$cmd"
	if [ -t 0 ]; then
		printf '  \033[1mPress Enter once it has completed (or Ctrl-C to abort)...\033[0m '
		read -r _ || true
	else
		warn "non-interactive: cannot wait — run the command above, then re-run this script."
	fi
}

# ---------------------------------------------------------------------------
# 0. detect OS + native package manager (sets globals OS, PM, IS_WSL, SUDO)
# ---------------------------------------------------------------------------
detect_env() {
	OS="unknown"; PM=""
	case "$(uname -s)" in
		Linux*)  OS="linux"  ;;
		Darwin*) OS="macos"  ;;
	esac
	if   have apt-get; then PM="apt"
	elif have dnf;     then PM="dnf"
	elif have pacman;  then PM="pacman"
	fi
	# WSL = Linux kernel rendered by a Windows terminal; fonts live on Windows, not here.
	IS_WSL=0
	grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null && IS_WSL=1
	# IS_ROOT=1 only when actually running as root. This script never invokes sudo;
	# privileged commands are surfaced via priv_step for the user to run.
	IS_ROOT=0; [ "$(id -u)" -eq 0 ] && IS_ROOT=1
	# Prefix for privileged commands: empty as root (sudo may not even exist in a
	# minimal root container), "sudo " otherwise. Baked into the command strings so
	# priv_step's root-eval path never runs a literal 'sudo'.
	SUDO_PREFIX=""; [ "$IS_ROOT" = "1" ] || SUDO_PREFIX="sudo "
	BREW_OK=0   # set to 1 by install_brew on success; gates brew-dependent steps
	# candidate brew locations, incl. the user-local (no-sudo) prefix
	BREW_LOCATIONS="/home/linuxbrew/.linuxbrew/bin/brew $HOME/.homebrew/bin/brew /opt/homebrew/bin/brew /usr/local/bin/brew"
	info "OS=$OS  native-pm=${PM:-none}  wsl=$IS_WSL  root=$IS_ROOT"
}

# load brew into THIS session from the first location that is not just present
# but actually FUNCTIONAL (a partial/corrupt tree has the binary but can't run).
load_brew() {
	local b
	for b in $BREW_LOCATIONS; do
		if [ -x "$b" ] && "$b" --version >/dev/null 2>&1; then
			eval "$("$b" shellenv)"
			return 0
		fi
	done
	return 1
}

# ---------------------------------------------------------------------------
# 1. OS prerequisites (needed to bootstrap Homebrew + build things)
# ---------------------------------------------------------------------------
# All the up-front ROOT work, bundled into ONE priv_step: install missing brew
# prerequisites AND create/own the canonical /home/linuxbrew prefix. Both need
# root and are knowable now, so we ask once instead of twice. (The later
# 'usermod' login-shell step can't merge here — it needs zsh installed first.)
CANON_PREFIX="/home/linuxbrew/.linuxbrew"
install_prereqs() {
	[ "${SKIP_PACKAGES:-0}" = "1" ] && { info "SKIP_PACKAGES=1 — skipping prereqs"; return; }
	[ "$OS" = "macos" ] && return   # macOS: Xcode CLT/brew handle prereqs
	local s="$SUDO_PREFIX" parts="" why=""

	# (a) prerequisites brew needs: curl (download), git (clone taps), unzip
	# (font), zsh (shell), and a C compiler + build tools. Only if any missing.
	local miss=""
	for d in curl git unzip zsh; do have "$d" || miss="$miss $d"; done
	have cc || have gcc || have clang || miss="$miss compiler"
	if [ -n "$miss" ]; then
		local pkgcmd=""
		case "$PM" in
			apt)    pkgcmd="${s}apt-get update && ${s}apt-get install -y build-essential procps curl file git zsh unzip" ;;
			dnf)    pkgcmd="${s}dnf groupinstall -y 'Development Tools' && ${s}dnf install -y procps-ng curl file git zsh unzip" ;;
			pacman) pkgcmd="${s}pacman -Sy --noconfirm --needed base-devel procps-ng curl file git zsh unzip" ;;
			"")     warn "missing prereqs ($miss) and no supported package manager — install them manually." ;;
		esac
		[ -n "$pkgcmd" ] && { parts="$pkgcmd"; why="prerequisites (missing:$miss)"; }
	fi

	# (b) canonical brew prefix: create + chown to us (bottles need this exact
	# path). Skip when root (brew refuses root anyway) or already writable.
	if [ "$IS_ROOT" != "1" ] && ! { [ -w /home/linuxbrew ] && [ -w "$CANON_PREFIX" ]; }; then
		local brewcmd="sudo mkdir -p $CANON_PREFIX && sudo chown -R \$(whoami) /home/linuxbrew"
		if [ -n "$parts" ]; then parts="$parts && $brewcmd"; else parts="$brewcmd"; fi
		why="${why:+$why + }bottle-enabled Homebrew prefix"
	fi

	# Run the combined admin step if we built one; otherwise report accurately —
	# "nothing to do" ONLY when nothing is actually missing (not when we simply
	# can't automate it on an unsupported package manager).
	if [ -n "$parts" ]; then
		priv_step "Root setup: $why" "$parts"
	elif [ -z "$miss" ]; then
		info "no root setup needed (prereqs present, brew prefix ready)"
	fi
	# Always re-check prereqs and warn (unsupported-PM path, or user skipped the
	# admin step). Doesn't block — brew may still work if the canonical prefix has bottles.
	local still=""
	for d in curl git unzip zsh; do have "$d" || still="$still $d"; done
	have cc || have gcc || have clang || still="$still compiler"
	[ -n "$still" ] && warn "still missing:$still — install manually; brew steps may fail until then."
}

# ---------------------------------------------------------------------------
# 2. Homebrew (Linuxbrew on Linux)
# ---------------------------------------------------------------------------
install_brew() {
	[ "${SKIP_PACKAGES:-0}" = "1" ] && return
	# Homebrew HARD-REFUSES to run as root ("extremely dangerous and no longer
	# supported") — every `brew install` would abort. Don't pretend otherwise:
	# refuse the brew path up front so we don't report success then install nothing.
	if [ "$IS_ROOT" = "1" ]; then
		printf '\n\033[1;37;41m  RUN AS A NORMAL USER  \033[0m \033[1mHomebrew will not run as root.\033[0m\n'
		warn "You are root. Re-run this script as a regular user (Homebrew installs into that"
		warn "user's home and refuses to operate as root). Aborting the package steps."
		BREW_OK=0; return 1
	fi
	if have brew; then info "Homebrew present"; BREW_OK=1; return; fi
	if load_brew; then info "found existing Homebrew"; BREW_OK=1; return; fi   # installed but not on PATH
	have curl || { warn "curl required to install Homebrew — install it and re-run."; BREW_OK=0; return 1; }

	# macOS: the official installer handles prefix creation/permissions (and will
	# prompt for your password itself). Use it directly.
	if [ "$OS" = "macos" ]; then
		info "installing Homebrew (official installer)"
		NONINTERACTIVE=1 /bin/bash -c \
			"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
			|| { warn "Homebrew install failed"; BREW_OK=0; return 1; }
		load_brew || { warn "Homebrew installed but not on PATH"; BREW_OK=0; return 1; }
		BREW_OK=1; return
	fi

	# Linux. Canonical /home/linuxbrew/.linuxbrew is the ONLY prefix with prebuilt
	# bottles; creating/owning it is done in install_prereqs' single root step
	# (needs write to BOTH parent /home/linuxbrew and the .linuxbrew child, since
	# rm/mv of the child requires a writable parent). Here we just USE it if it's
	# writable, else fall back to user-local ~/.homebrew. No prompt of our own.
	local prefix="" canon="$CANON_PREFIX"
	mkdir -p "$canon" 2>/dev/null   # harmless if already ours; may succeed if $HOME-side
	if [ -w /home/linuxbrew ] && [ -w "$canon" ]; then
		prefix="$canon"
		info "using canonical Homebrew prefix $prefix (bottles available)"
	else
		prefix="$HOME/.homebrew"
		warn "using $prefix (NO prebuilt bottles; formulae build from source, needs a compiler)."
	fi

	# Populate the prefix UNPRIVILEGED via the brew git tarball. Stage into a temp
	# dir and swap in only once verified working, so an interrupted run never
	# leaves a half-written prefix a later run trusts.
	info "installing Homebrew into $prefix"
	local staging; staging="$(mktemp -d "${TMPDIR:-/tmp}/brew.XXXXXX")"
	if ! { curl -fsSL https://github.com/Homebrew/brew/tarball/master \
		 | tar xz --strip-components 1 -C "$staging"; }; then
		warn "Homebrew download/extract failed"; rm -rf "$staging"; return 1
	fi
	if ! "$staging/bin/brew" --version >/dev/null 2>&1; then
		warn "extracted Homebrew is not runnable — discarding"; rm -rf "$staging"; return 1
	fi
	# Only remove a prior tree if it has NO working brew (partial/corrupt). If a
	# real brew already lives at $prefix, NEVER rm it — that would wipe the whole
	# Cellar/formulae. (load_brew failed to find it, but a populated-yet-currently-
	# unrunnable brew — e.g. interrupted update — must be repaired by the user, not
	# nuked.) Guard is the difference between "clean partial" and "data loss".
	if [ -x "$prefix/bin/brew" ]; then
		warn "a Homebrew already exists at $prefix but isn't runnable. NOT deleting it (would"
		warn "lose installed formulae). Repair it (e.g. 'git -C \"$prefix\" reset --hard;"
		warn "$prefix/bin/brew update --force') or remove it manually, then re-run."
		rm -rf "$staging"; return 1
	fi
	rm -rf "$prefix"                              # safe: no working brew here
	mkdir -p "$(dirname "$prefix")"
	mv "$staging" "$prefix" 2>/dev/null
	# Trust the RESULT, not mv's exit code: confirm the binary actually landed at
	# $prefix/bin/brew (a non-writable parent would nest it one level down instead).
	if [ ! -x "$prefix/bin/brew" ] || ! "$prefix/bin/brew" --version >/dev/null 2>&1; then
		warn "brew did not land at $prefix/bin/brew (parent dir not writable?) — see the admin step above."
		rm -rf "$staging"; return 1
	fi

	load_brew || { warn "Homebrew installed but not runnable on expected paths"; BREW_OK=0; return 1; }
	BREW_OK=1
}

# ---------------------------------------------------------------------------
# 3. CLI tools + node + language servers (brew is idempotent: skips installed)
# ---------------------------------------------------------------------------
install_tools() {
	[ "${SKIP_PACKAGES:-0}" = "1" ] && return
	[ "$BREW_OK" = "1" ] || { warn "Homebrew not available — skipping tool install (see brew step above)."; return; }
	load_brew  # ensure brew is on PATH for this step
	have brew || { warn "brew unavailable — skipping tool install"; return; }
	info "installing CLI tools via brew (idempotent)"
	# Core tools in one shot (brew doesn't prompt). llvm is deliberately NOT here:
	# it's huge, bottle-fragile, and if it fails in a single `brew install` line it
	# aborts the whole line, taking nvim/node/starship down with it (as happened).
	# zsh via brew so we never depend on a system zsh (prereqs may be skipped).
	# vim AND neovim: shared vimrc uses modern features; brew's vim is current.
	# node = coc/LSP + markdown-preview build. python = clean latest Python that
	# nvim's python3 provider picks up (brew's bin is first on PATH via zshenv), so
	# pynvim installs there without the distro's PEP-668 restriction.
	brew install -y \
		zsh vim neovim node python \
		git-delta bat fzf ripgrep jq universal-ctags eza zoxide \
		starship tmux herdr gopls \
		|| warn "some brew packages failed — check output above"

	# llvm (full toolchain: clang-format, clang-tidy, lldb, and C++ clangd) is
	# installed on its OWN command, AFTER the core tools — it's several GB, so
	# doing it separately guarantees a disk/bottle failure here can't starve the
	# essentials above (brew resolves a combined line's graph in any order).
	if ! brew list llvm >/dev/null 2>&1; then
		info "installing llvm (C++ toolchain: clangd/clang-format/clang-tidy; several GB)"
		if ! brew install -y llvm; then
			warn "=================================================================="
			warn "llvm FAILED to install (most likely: not enough disk space —"
			warn "llvm needs ~3-5 GB). This is NON-FATAL: nvim/node/etc. are fine,"
			warn "and coc-clangd will fetch its own clangd for C++ on first use."
			warn "To get the full toolchain later: free disk, then 'brew install llvm'."
			warn "=================================================================="
		fi
	fi

	# verify the essentials actually landed; warn loudly (don't fail silently)
	local missing=""
	for t in zsh nvim node starship; do have "$t" || missing="$missing $t"; done
	[ -n "$missing" ] && warn "MISSING after install:$missing — check brew output above."
}

# ---------------------------------------------------------------------------
# 3b. JetBrainsMono Nerd Font (strict-monospace 'Mono' face) for prompt/tmux/
#     airline glyphs. Handles all NON-WSL cases; WSL prints a pointer to the
#     README (font must be installed on Windows, not inside WSL).
# ---------------------------------------------------------------------------
FONT_FAMILY="JetBrainsMono Nerd Font Mono"
install_font() {
	[ "${SKIP_PACKAGES:-0}" = "1" ] && return
	if [ "$IS_WSL" = "1" ]; then
		warn "WSL detected — fonts live on Windows, not here."
		warn "Install the Nerd Font on Windows: see README 'Nerd Font on WSL/Windows Terminal'."
		return
	fi
	if [ "$OS" = "macos" ]; then
		if brew list --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1; then
			info "Nerd Font present (brew cask)"
		else
			info "installing Nerd Font (brew cask)"
			brew install -y --cask font-jetbrains-mono-nerd-font || warn "font cask install failed"
		fi
		warn "Set your terminal font to '$FONT_FAMILY' (Terminal/iTerm settings)."
		return
	fi
	# native Linux desktop: drop the Mono ttfs into the user font dir + refresh cache
	have unzip || { warn "unzip missing — cannot install font (add it via your package manager)"; return; }
	local fdir="$HOME/.local/share/fonts"
	if ls "$fdir"/JetBrainsMonoNerdFontMono-*.ttf >/dev/null 2>&1; then
		info "Nerd Font present ($fdir)"
	else
		info "installing JetBrainsMono Nerd Font -> $fdir"
		local tmp; tmp="$(mktemp -d)"
		if curl -fsSL -o "$tmp/JetBrainsMono.zip" \
			https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip; then
			mkdir -p "$fdir"
			# extract only the strict-monospace Mono faces (not the NL/Propo variants)
			( cd "$tmp" && unzip -oq JetBrainsMono.zip 'JetBrainsMonoNerdFontMono-*.ttf' -d "$fdir" ) \
				|| warn "font unzip failed"
			have fc-cache && fc-cache -f "$fdir" >/dev/null 2>&1
			info "installed; set your terminal font to '$FONT_FAMILY'"
		else
			warn "font download failed — see README to install manually"
		fi
		rm -rf "$tmp"
	fi
}

# ---------------------------------------------------------------------------
# 4. zim (zsh plugin loader). starship/zoxide/fzf came from brew above.
# ---------------------------------------------------------------------------
install_zim() {
	[ "${SKIP_PACKAGES:-0}" = "1" ] && return
	# NOTE: separate `local` statements — bash evaluates all RHS on one `local`
	# line before assigning, so `dest="$zim_home/..."` on the same line would see
	# an unset zim_home and abort under `set -u`.
	local zim_home="${ZIM_HOME:-$HOME/.zim}"
	local dest="$zim_home/zimfw.zsh"
	# Treat an existing file as good only if it looks complete (a truncated download
	# from an interrupted run would otherwise be trusted forever). Download to a
	# temp file, verify, then move into place.
	if [ -s "$dest" ] && grep -q 'zimfw' "$dest" 2>/dev/null; then info "zim present"; return; fi
	info "installing zim"
	local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/zimfw.XXXXXX")"
	if curl -fsSL -o "$tmp" https://github.com/zimfw/zimfw/releases/latest/download/zimfw.zsh \
		&& [ -s "$tmp" ] && grep -q 'zimfw' "$tmp" 2>/dev/null; then
		mkdir -p "$zim_home"; mv "$tmp" "$dest"
	else
		warn "zim download failed or incomplete"; rm -f "$tmp"
	fi
}

# ---------------------------------------------------------------------------
# 5. default shell -> zsh (idempotent)
# ---------------------------------------------------------------------------
# Make interactive bash shells hand off to zsh, loading brew there too — so a
# box where we couldn't set the login shell (no sudo / usermod declined) still
# lands you in zsh with tools on PATH. Written to BOTH ~/.bashrc (interactive
# non-login) AND a login
# file (~/.bash_profile or ~/.profile) so SSH/console LOGIN shells trigger it too.
# Each target guarded by a marker (idempotent). Brew paths are written literally
# (not via $BREW_LOCATIONS) so no write-time word-splitting/globbing.
_bashrc_handoff_block() {
	local zsh_path="$1"
	cat <<BLOCK

# >>> dotfiles: exec zsh >>>
# Load Homebrew (so tools are on PATH), then hand interactive bash off to zsh.
for _b in /home/linuxbrew/.linuxbrew/bin/brew "\$HOME/.homebrew/bin/brew" /opt/homebrew/bin/brew /usr/local/bin/brew; do
	[ -x "\$_b" ] && eval "\$("\$_b" shellenv)" && break
done
# Only for a real interactive shell: not when running a command (bash -c / bash -i -c),
# not if already in zsh, and skippable via NO_EXEC_ZSH=1 if zsh startup ever breaks.
case \$- in
	*c*) ;;
	*i*) [ -z "\${NO_EXEC_ZSH:-}" ] && [ -z "\${ZSH_VERSION:-}" ] && [ -x "$zsh_path" ] && exec "$zsh_path" -l ;;
esac
# <<< dotfiles: exec zsh <<<
BLOCK
}

add_bashrc_exec_zsh() {
	local zsh_path="$1" marker="# >>> dotfiles: exec zsh >>>" login_rc target
	# interactive non-login shells
	grep -qF "$marker" "$HOME/.bashrc" 2>/dev/null || _bashrc_handoff_block "$zsh_path" >> "$HOME/.bashrc"
	# login shells (SSH/console): use an existing login file, else create ~/.bash_profile
	if   [ -f "$HOME/.bash_profile" ]; then login_rc="$HOME/.bash_profile"
	elif [ -f "$HOME/.bash_login" ];   then login_rc="$HOME/.bash_login"
	elif [ -f "$HOME/.profile" ];      then login_rc="$HOME/.profile"
	else login_rc="$HOME/.bash_profile"; fi
	grep -qF "$marker" "$login_rc" 2>/dev/null || _bashrc_handoff_block "$zsh_path" >> "$login_rc"
	info "added brew + 'exec zsh' hand-off to ~/.bashrc and $(basename "$login_rc") (NO_EXEC_ZSH=1 to bypass)"
}

set_default_shell() {
	local zsh_path; zsh_path="$(command -v zsh || true)"
	[ -z "$zsh_path" ] && { warn "zsh not installed — cannot set default shell"; return; }
	# zsh_path gets baked into ~/.bashrc and the usermod command. Refuse anything
	# outside a safe charset so a metacharacter in the path can't corrupt those or
	# inject code that runs on every shell start. (A normal zsh path is always safe.)
	case "$zsh_path" in
		/*) : ;;  # must be absolute
		*)  warn "zsh path '$zsh_path' is not absolute — skipping shell setup"; return ;;
	esac
	if printf '%s' "$zsh_path" | LC_ALL=C grep -q '[^A-Za-z0-9._/-]'; then
		warn "zsh path '$zsh_path' has unsafe characters — skipping shell setup (set it manually)"; return
	fi
	# $USER can be unset under `set -u` (minimal containers, su); derive safely.
	local user="${USER:-$(id -un)}"
	# Current login shell already zsh? (check both $SHELL and the passwd record)
	local cur; cur="$(getent passwd "$user" 2>/dev/null | cut -d: -f7)"
	if [ "${SHELL:-}" = "$zsh_path" ] || [ "$cur" = "$zsh_path" ]; then
		info "default shell already zsh"; return
	fi

	# Build the right root command per-OS: Linux uses `usermod -s` (no password,
	# unlike user `chsh` which fails on passwordless cloud accounts; and no
	# /etc/shells requirement). macOS has no usermod -> use chsh (+ /etc/shells).
	local shellcmd=""
	if [ "$OS" = "macos" ]; then
		shellcmd="grep -qxF '$zsh_path' /etc/shells || echo '$zsh_path' | ${SUDO_PREFIX}tee -a /etc/shells; ${SUDO_PREFIX}chsh -s '$zsh_path' '$user'"
	elif have usermod; then
		shellcmd="${SUDO_PREFIX}usermod -s '$zsh_path' '$user'"
	fi

	if [ -n "$shellcmd" ]; then
		priv_step "Set zsh as your login shell" "$shellcmd"
		cur="$(getent passwd "$user" 2>/dev/null | cut -d: -f7)"
	fi

	if [ "$cur" = "$zsh_path" ] || [ "${SHELL:-}" = "$zsh_path" ]; then
		info "login shell set to zsh (re-login / reconnect to take effect)"
	else
		# Not applied (skipped, no usermod, unverifiable) -> guarantee zsh anyway
		# via a ~/.bashrc + login-file hand-off.
		warn "login shell unchanged — installing a ~/.bashrc + login-file 'exec zsh' hand-off instead"
		add_bashrc_exec_zsh "$zsh_path"
	fi
}

# ---------------------------------------------------------------------------
# 6. vim-plug + nvim plugins
# ---------------------------------------------------------------------------
install_vim_plugins() {
	[ "${SKIP_PACKAGES:-0}" = "1" ] && return
	load_brew  # make sure brew-installed nvim is on PATH before we look for it
	local plug="$HOME/.vim/autoload/plug.vim"
	# Re-fetch unless the existing plug.vim looks complete (guards a truncated file).
	if ! { [ -s "$plug" ] && grep -q 'plug#begin' "$plug" 2>/dev/null; }; then
		info "installing vim-plug"
		local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/plug.XXXXXX")"
		if curl -fsSL -o "$tmp" https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim \
			&& [ -s "$tmp" ] && grep -q 'plug#begin' "$tmp" 2>/dev/null; then
			mkdir -p "$(dirname "$plug")"; mv "$tmp" "$plug"
		else
			warn "vim-plug download failed or incomplete"; rm -f "$tmp"
		fi
	fi
	# vimspector needs nvim's python3 provider -> the 'pynvim' module, installed
	# into the SAME python3 nvim resolves. nvim uses the first python3 on PATH,
	# which (with brew loaded) is brew's python3 — so target `command -v python3`
	# rather than guessing a prefix. Ensure pip exists, then install pynvim.
	local py; py="$(command -v python3 || true)"
	if [ -n "$py" ]; then
		info "installing pynvim into $py (vimspector)"
		"$py" -m ensurepip --upgrade >/dev/null 2>&1 || true   # some pythons ship pip lazily
		# Both brew python and modern distro python are PEP-668 "externally managed"
		# and reject a plain install. Two escape hatches, and they differ:
		#   - distro python: --user (into ~/.local) + --break-system-packages
		#   - brew  python: DISABLES --user, so it needs --break-system-packages WITHOUT --user
		# Try each; the first that succeeds wins.
		if   "$py" -m pip install --quiet pynvim; then :
		elif "$py" -m pip install --break-system-packages --quiet pynvim; then :
		elif "$py" -m pip install --user --break-system-packages --quiet pynvim; then :
		else
			warn "pynvim install failed — try: $py -m pip install --break-system-packages pynvim"
		fi
		# verify it actually imports in the python nvim will use
		if "$py" -c 'import pynvim' 2>/dev/null; then
			info "pynvim OK in $py"
		else
			warn "pynvim still not importable by $py — vimspector will report 'Requires +python3'."
		fi
	else
		warn "python3 not found — vimspector needs it + pynvim for debugging."
	fi

	if have nvim; then
		info "installing nvim plugins (PlugInstall)"
		nvim --headless +PlugInstall +qall 2>/dev/null || warn "PlugInstall had issues — run 'nvim +PlugInstall' manually"
	else
		warn "nvim not installed — skipping PlugInstall"
	fi
}

# ---------------------------------------------------------------------------
# 7. symlink configs (timestamped backup of any existing real file)
# ---------------------------------------------------------------------------
link() {
	local src="$1" dest="$2"
	mkdir -p "$(dirname "$dest")"
	# already correctly linked? no-op (idempotent)
	[ "$(readlink "$dest" 2>/dev/null)" = "$src" ] && return
	# Back up anything already there — including a symlink pointing ELSEWHERE
	# (don't silently rm a user's hand-made link). -L test first: -e follows links.
	if [ -L "$dest" ] || [ -e "$dest" ]; then
		local bak="$dest.backup.$(date +%Y%m%d%H%M%S)"
		info "backup: $dest ($(readlink "$dest" 2>/dev/null || echo file)) -> $bak"
		# plain mv: $bak is a fresh timestamped path (never pre-exists), so the -T
		# dir-nesting guard is moot — and BSD/macOS mv has no -T flag anyway.
		mv "$dest" "$bak"
	fi
	ln -s "$src" "$dest"
	info "link:   $dest -> $src"
}

link_configs() {
	info "linking configs"
	link "$DOTFILES/nvim/vimrc"              "$HOME/.vimrc"        # nvim's init.vim sources this
	link "$DOTFILES/nvim/init.vim"           "$HOME/.config/nvim/init.vim"
	link "$DOTFILES/nvim/coc-settings.json"  "$HOME/.config/nvim/coc-settings.json"
	link "$DOTFILES/nvim/after"              "$HOME/.vim/after"
	link "$DOTFILES/shell/zshrc"             "$HOME/.zshrc"
	link "$DOTFILES/shell/zshenv"            "$HOME/.zshenv"
	link "$DOTFILES/shell/zimrc"             "$HOME/.zimrc"
	link "$DOTFILES/starship/starship.toml"  "$HOME/.config/starship.toml"
	link "$DOTFILES/tmux/tmux.conf"          "$HOME/.tmux.conf"
	link "$DOTFILES/herdr/config.toml"       "$HOME/.config/herdr/config.toml"
	link "$DOTFILES/git/gitconfig"           "$HOME/.gitconfig"
	link "$DOTFILES/claude/settings.json"    "$HOME/.claude/settings.json"
	link "$DOTFILES/claude/statusline.sh"    "$HOME/.claude/statusline.sh"
}

# ---------------------------------------------------------------------------
# 8. interactive machine-local config (TTY only; skipped/defaulted under pipes)
# ---------------------------------------------------------------------------

# git identity — kept out of the tracked, public gitconfig
configure_git_identity() {
	[ -t 0 ] || return                                   # only prompt on a TTY
	[ -n "$(git config --global user.email 2>/dev/null)" ] && return  # already set
	local gname gemail
	read -r -p ">> git user.name (blank to skip): " gname || gname=""
	read -r -p ">> git user.email (blank to skip): " gemail || gemail=""
	[ -n "$gname" ]  && git config --global user.name  "$gname"
	[ -n "$gemail" ] && git config --global user.email "$gemail"
}

# vimwiki path -> ~/.vimrc.local (untracked)
configure_vimwiki() {
	[ -f "$HOME/.vimrc.local" ] && return
	local wpath="~/vimwiki/src" reply
	if [ -t 0 ]; then
		read -r -p ">> vimwiki path [~/vimwiki/src]: " reply || reply=""
		wpath="${reply:-$wpath}"
	fi
	echo "let g:vimwiki_path = '${wpath}'" > "$HOME/.vimrc.local"
	info "wrote ~/.vimrc.local"
}

# map a clipboard target name -> the external command tmux pipes copies to.
# (osc52 and none are handled specially in configure_tmux_clipboard, not here.)
clipboard_cmd_for() {
	case "$1" in
		wsl)     echo "clip.exe" ;;
		macos)   echo "pbcopy" ;;
		wayland) echo "wl-copy" ;;
		x11)     echo "xclip -in -selection clipboard" ;;
		*)       echo "" ;;
	esac
}

# pick the sensible default clipboard target for this environment.
# No local display (headless/SSH) -> osc52 (sends to your LOCAL terminal's
# clipboard over the connection); a real X11/Wayland desktop -> its native tool.
default_clipboard_target() {
	if   [ "$IS_WSL" = "1" ];              then echo "wsl"
	elif [ "$OS" = "macos" ];              then echo "macos"
	elif [ -n "${WAYLAND_DISPLAY:-}" ];    then echo "wayland"
	elif [ -n "${DISPLAY:-}" ];            then echo "x11"
	else                                        echo "osc52"; fi
}

# tmux clipboard bridge -> ~/.tmux.local.conf (untracked)
configure_tmux_clipboard() {
	[ -f "$HOME/.tmux.local.conf" ] && return
	local default_clip clip reply clip_cmd
	default_clip="$(default_clipboard_target)"
	clip="$default_clip"
	if [ -t 0 ]; then
		echo ">> tmux clipboard target — where 'y' (copy-mode) sends the selection:"
		echo "   wsl/macos/wayland/x11 = local clipboard tool · osc52 = local clipboard"
		echo "   over SSH (headless-friendly) · none = tmux buffer only"
		read -r -p "   [wsl / macos / wayland / x11 / osc52 / none] (${default_clip}): " reply || reply=""
		clip="${reply:-$default_clip}"
	fi
	if [ "$clip" = "osc52" ]; then
		# tmux emits the OSC 52 escape itself; no external command needed.
		{ echo "set -g set-clipboard on"
		  echo "bind -T copy-mode-vi y send -X copy-selection-and-cancel"
		} > "$HOME/.tmux.local.conf"
		info "wrote ~/.tmux.local.conf (clipboard -> OSC 52 / local terminal over SSH)"
		return
	fi
	clip_cmd="$(clipboard_cmd_for "$clip")"
	if [ -n "$clip_cmd" ]; then
		echo "bind -T copy-mode-vi y send -X copy-pipe-and-cancel \"$clip_cmd\"" > "$HOME/.tmux.local.conf"
		info "wrote ~/.tmux.local.conf (clipboard -> $clip_cmd)"
	else
		: > "$HOME/.tmux.local.conf"   # 'none' — tmux buffer only
		info "wrote ~/.tmux.local.conf (no system-clipboard bridge)"
	fi
}

# ---------------------------------------------------------------------------
# run
# ---------------------------------------------------------------------------
main() {
	detect_env

	# Symlink configs FIRST — they don't depend on any package, so you always get
	# your dotfiles (.tmux.conf, .zshrc, starship.toml, ...) even if a later
	# install step fails. (Previously this ran late, so an abort in install_zim
	# left nothing linked.)
	link_configs

	# provision
	install_prereqs
	install_brew
	install_tools
	install_font
	install_zim
	install_vim_plugins    # after link_configs so nvim sees its config
	set_default_shell

	# machine-local (interactive) settings
	configure_git_identity
	configure_vimwiki
	configure_tmux_clipboard

	echo
	if [ "${SKIP_PACKAGES:-0}" != "1" ] && [ "$BREW_OK" != "1" ]; then
		warn "Done, but Homebrew was NOT set up — tools (nvim/node/etc.) were skipped."
		warn "Fix the brew step above (commonly: re-run as a normal user, not root), then re-run."
		return 1
	fi
	info "Done."
	local zsh_path; zsh_path="$(command -v zsh || echo zsh)"
	if [ "${SHELL:-}" = "$zsh_path" ]; then
		info "You're set — open a new shell."
	else
		info "Your CURRENT shell is unchanged. Start zsh now with:  exec \"$zsh_path\""
		info "New logins/SSH sessions will land in zsh automatically."
	fi
	have clangd || warn "clangd: ensure \$(brew --prefix llvm)/bin is on PATH (zshenv/bashrc handle this in a fresh shell)."
}

main "$@"
