#!/usr/bin/env bash
# Tests for the Brewfiles. `brew bundle` is what actually reads these, and the
# suite must run on a machine with no Homebrew, so these checks are limited to
# what can be established without it: every Brewfile install.sh names exists,
# and every line in one is something `brew bundle` understands.
#
# shellcheck source-path=SCRIPTDIR
set -uo pipefail

# shellcheck source=helpers/framework.sh
source "$(dirname "$0")/helpers/framework.sh"

# The Brewfiles install.sh installs, one per optional group plus the base set.
BREWFILES=(Brewfile Brewfile.ruby Brewfile.python Brewfile.node)

# Strips comments and blank lines, leaving the entries `brew bundle` acts on.
entries() {
  sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$REPO_ROOT/$1"
}

test_every_brewfile_install_sh_names_exists() {
  local brewfile
  for brewfile in "${BREWFILES[@]}"; do
    assert_file "$REPO_ROOT/$brewfile" || return 1
    grep -Fq "brew_bundle $brewfile" "$REPO_ROOT/install.sh" ||
      fail "install.sh never installs $brewfile" || return 1
  done
}

test_install_sh_names_every_brewfile_in_the_checkout() {
  local path brewfile
  for path in "$REPO_ROOT"/Brewfile*; do
    brewfile="$(basename "$path")"
    grep -Fq "brew_bundle $brewfile" "$REPO_ROOT/install.sh" ||
      fail "$brewfile is in the checkout but install.sh never installs it" ||
      return 1
  done
}

test_every_brewfile_entry_is_a_directive_brew_bundle_understands() {
  local brewfile line
  for brewfile in "${BREWFILES[@]}"; do
    while IFS= read -r line; do
      # tap/brew/cask/mas "name", optionally followed by , key: value options.
      [[ "$line" =~ ^(tap|brew|cask|mas)\ \"[^\"]+\" ]] ||
        fail "$brewfile: cannot parse '$line'" || return 1
    done <<<"$(entries "$brewfile")"
  done
}

test_no_brewfile_is_empty() {
  local brewfile
  for brewfile in "${BREWFILES[@]}"; do
    [[ -n "$(entries "$brewfile")" ]] ||
      fail "$brewfile declares no packages" || return 1
  done
}

test_no_package_is_declared_twice() {
  local brewfile duplicates
  for brewfile in "${BREWFILES[@]}"; do
    duplicates="$(entries "$brewfile" | sort | uniq -d)"
    assert_eq "" "$duplicates" "$brewfile declares a package twice" || return 1
  done
}

# The base set is the one `brew bundle` picks up with no --file, so it has to
# carry what every machine gets rather than an optional group's packages.
test_the_base_brewfile_carries_the_general_packages() {
  local base
  base="$(entries Brewfile)"

  assert_contains "$base" 'brew "git"'
  assert_contains "$base" 'brew "gh"'
  # scripts/zsh-plugins sources these on every shell start.
  assert_contains "$base" 'brew "zsh-autosuggestions"'
  assert_contains "$base" 'brew "zsh-syntax-highlighting"'
  assert_contains "$base" 'cask "google-chrome"'
  assert_contains "$base" 'cask "iterm2"'
  assert_contains "$base" 'cask "slack"'
  assert_contains "$base" 'cask "visual-studio-code"'
}

# install.sh installs the runtime with the version manager, so a language group
# declares the manager and nothing else. A Homebrew ruby or python would be the
# toolchain rbenv and pyenv are here to keep gems and pip packages out of - pip
# refuses to touch a Homebrew python at all
# (error: externally-managed-environment) - and a Homebrew node would race
# nvm's shims for $PATH.
test_the_language_groups_declare_only_a_version_manager() {
  local ruby python node
  ruby="$(entries Brewfile.ruby)"
  python="$(entries Brewfile.python)"
  node="$(entries Brewfile.node)"

  assert_contains "$ruby" 'brew "rbenv"'
  assert_not_contains "$ruby" 'brew "ruby'

  assert_contains "$python" 'brew "pyenv"'
  assert_not_contains "$python" 'brew "python'

  assert_contains "$node" 'brew "nvm"'
  assert_not_contains "$node" 'brew "node"'
  # brew's npm is an alias for the node formula, not a formula of its own.
  assert_not_contains "$node" 'brew "npm"'
}

# Groups stay opt-in, so nothing a group installs may leak into the base set.
test_the_base_brewfile_carries_no_group_packages() {
  local base
  base="$(entries Brewfile)"

  assert_not_contains "$base" 'brew "rbenv"'
  assert_not_contains "$base" 'brew "pyenv"'
  assert_not_contains "$base" 'brew "nvm"'
}

run_tests "$@"
