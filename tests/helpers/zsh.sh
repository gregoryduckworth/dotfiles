#!/usr/bin/env bash
# Helpers for exercising the zsh side of the dotfiles. Everything runs in a
# child zsh so the bash test process is never affected.

# Installs the repo's profile and scripts into the sandbox $HOME, the same way
# install.sh does.
install_profile_into_home() {
  cp -R "$REPO_ROOT/scripts" "$HOME/"
  cp "$REPO_ROOT/.zshrc" "$HOME/.zshrc"
}

# zsh_profile [code]: sources ~/.zshrc under `set -e` and then runs [code]. The
# errexit matters: .zshrc is sourced by scripts that abort on a non-zero status,
# so no script may leave one behind.
#
# Called with no code the exit status is the profile's own, which is the thing
# worth asserting; anything appended would mask it.
zsh_profile() {
  zsh -c "set -e; source ~/.zshrc; ${1:-}"
}

# zsh_script <name> [code]: sources a single file from scripts/ and runs [code].
# As above, omit the code to assert on the script's own exit status.
zsh_script() {
  zsh -c "set -e; source '$REPO_ROOT/scripts/$1'; ${2:-}"
}
