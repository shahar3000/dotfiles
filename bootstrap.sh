#!/usr/bin/env bash
# One-command bootstrap:
#   curl -fsSL https://raw.githubusercontent.com/shahar3000/dotfiles/main/bootstrap.sh | bash
#
# Ensures git is present, clones (or fast-forward updates) the dotfiles
# repo, then hands off to install.sh, which does everything else. This
# script's only job is getting the repo onto disk -- install.sh assumes
# it's already there (it reads its own sibling files).
#
# Usage:
#   curl -fsSL .../bootstrap.sh | bash
#   DOTFILES_DIR=~/dotfiles curl -fsSL .../bootstrap.sh | bash   # custom location
set -euo pipefail

REPO_URL="https://github.com/shahar3000/dotfiles.git"
DEST="${DOTFILES_DIR:-./dotfiles}"

info() { printf '\033[1;34m>>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---- ensure git ----
if ! have git; then
	info "git not found -- installing it"
	case "$(uname -s)" in
		Darwin)
			# Mirrors install.sh's own stance: don't fight Apple's toolchain
			# gate, just point at it (Xcode CLT's installer is interactive/GUI).
			die "git is required. Install it via 'xcode-select --install' (or Homebrew), then re-run this command."
			;;
		*)
			if have apt-get; then
				sudo apt-get update && sudo apt-get install -y git
			elif have dnf; then
				sudo dnf install -y git
			elif have pacman; then
				sudo pacman -Sy --noconfirm --needed git
			else
				die "git is required and no supported package manager was found. Install git manually, then re-run."
			fi
			;;
	esac
	have git || die "git installation failed."
fi

# ---- clone or update ----
if [ -e "$DEST" ]; then
	if [ -d "$DEST/.git" ] && \
	   git -C "$DEST" remote get-url origin 2>/dev/null | grep -q 'shahar3000/dotfiles'; then
		info "found existing checkout at $DEST -- updating"
		git -C "$DEST" pull --ff-only \
			|| die "$DEST has local commits that don't fast-forward -- resolve manually, then run $DEST/install.sh yourself."
	else
		die "$DEST already exists and isn't a dotfiles checkout -- move it aside or set DOTFILES_DIR, then re-run."
	fi
else
	info "cloning into $DEST"
	git clone "$REPO_URL" "$DEST"
fi

# ---- hand off to install.sh, reattaching the real terminal ----
# This script's own stdin is the curl pipe, not a terminal. install.sh's
# interactive prompts (git identity, vimwiki path, Copilot opt-in, tmux
# clipboard) gate on `[ -t 0 ]` / read from stdin -- if they inherited the
# pipe instead of a real tty, they'd silently take defaults instead of
# asking, the same class of bug this repo's Windows installer was just
# fixed for. Reattach /dev/tty when one exists so those prompts still work.
cd "$DEST"
if [ -r /dev/tty ]; then
	exec ./install.sh < /dev/tty
else
	warn "no terminal available -- install.sh will run non-interactively (defaults only)"
	exec ./install.sh
fi
