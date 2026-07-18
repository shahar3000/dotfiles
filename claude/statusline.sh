#!/usr/bin/env bash
input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')
ctx=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# Git branch — silent if not in a repo or git unavailable
branch=$(git --no-optional-locks -C "${cwd:-$(pwd)}" symbolic-ref --short HEAD 2>/dev/null)

# Path in blue
printf '\033[01;34m%s\033[00m' "${cwd:-$(pwd)}"

# Git branch in green (only when inside a repo)
[ -n "$branch" ] && printf ' \033[00m|\033[00m \033[01;32m%s\033[00m' "$branch"

# Model name in yellow
[ -n "$model" ] && printf ' \033[00m|\033[00m \033[01;33m%s\033[00m' "$model"

# Context window usage in cyan (only once a response has been made)
[ -n "$ctx" ] && printf ' \033[00m|\033[00m \033[01;36mctx:%.0f%%\033[00m' "$ctx"
