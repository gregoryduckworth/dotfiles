#!/usr/bin/env bash
# Helpers shared by install.sh and update.sh.

# install_scripts <source-dir> <dest-dir>
#
# Mirrors <source-dir> onto <dest-dir>, so afterwards <dest-dir> holds exactly
# what the checkout holds and nothing else. `cp -R` on its own merges into an
# existing directory and never deletes, so a script removed or renamed in the
# repo would survive in ~/scripts on every already-bootstrapped machine and
# keep being sourced by .zshrc forever.
#
# The fresh copy is staged alongside the destination and swapped in at the end,
# so a copy that fails part-way through leaves the installed scripts as they
# were rather than half-replaced.
install_scripts() {
  local src="$1" dest="$2"
  local staged="$dest.new.$$" previous="$dest.old.$$"

  rm -rf "$staged" "$previous"
  if ! cp -R "$src" "$staged"; then
    rm -rf "$staged"
    return 1
  fi

  if [[ -e "$dest" ]]; then
    mv "$dest" "$previous"
  fi
  mv "$staged" "$dest"
  rm -rf "$previous"
}
