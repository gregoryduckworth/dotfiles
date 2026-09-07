#!/usr/bin/env bash
set -euo pipefail

PROFILE=zshrc

# Resolve everything against the checkout rather than the caller's working
# directory, so `~/somewhere/dotfiles/update.sh` works from anywhere.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install_profile() {
  echo "Creating .$PROFILE file..."

  # No sudo: these files live in $HOME, and root-owned dotfiles only cause
  # trouble on the next update.
  cp -R "$SCRIPT_DIR/scripts" "$HOME/"
  cp "$SCRIPT_DIR/.$PROFILE" "$HOME/.$PROFILE"
}

main() {
  local choice
  read -r -p "Do you want to update your scripts and .$PROFILE? [n/Y]" choice
  choice=${choice:-y}
  if [[ $choice =~ ^[Yy]$ ]]; then
    install_profile
  fi

  # Replacing this bash script with zsh loads .$PROFILE; sourcing it here would
  # fail on zsh-only builtins and be discarded when this script exits anyway.
  echo "Loading .$PROFILE..."
  exec /bin/zsh
}

# Only update when executed. Sourcing the file just defines the functions,
# which is how tests/update_test.sh exercises them.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
