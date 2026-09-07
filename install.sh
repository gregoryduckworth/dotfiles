#!/usr/bin/env bash
set -euo pipefail

# Resolve everything against the checkout rather than the caller's working
# directory, so `~/somewhere/dotfiles/install.sh` works from anywhere.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

homebrew_install() {
  # Check for Homebrew, install if we don't have it
  if ! command -v brew &>/dev/null; then
    echo "Installing Homebrew..."
    if ! /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
      echo "Error: Homebrew installation failed"
      return 1
    fi
    # Add Homebrew to PATH
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f "/usr/local/bin/brew" ]]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
  fi

  # Update Homebrew recipes
  brew update
}

# Clean up Homebrew
homebrew_cleanup() {
  echo "Cleaning up..."
  brew cleanup
}

# General Brew Install
brew_install() {
  local install_type=""
  if [[ "$1" == "--cask" ]]; then
    install_type="--cask"
    shift
  fi

  echo "Installing packages..."
  for package in "$@"; do
    if [[ -n "$install_type" ]]; then
      if ! brew list --cask "$package" &>/dev/null; then
        echo "Installing $package..."
        brew install --cask "$package"
      else
        echo "$package is already installed..."
      fi
    else
      if ! brew list --formula "$package" &>/dev/null; then
        echo "Installing $package..."
        brew install "$package"
      else
        echo "$package is already installed..."
      fi
    fi
  done
}

# Create and source the file
source_profile() {
  echo "Creating .$1 file..."

  # Check if source files exist
  if [[ ! -f "$SCRIPT_DIR/.$1" ]]; then
    echo "Error: .$1 not found"
    return 1
  fi

  if [[ ! -d "$SCRIPT_DIR/scripts" ]]; then
    echo "Error: scripts directory not found"
    return 1
  fi

  # This script runs under bash, so sourcing the zsh profile here would both
  # fail on zsh-only builtins and be thrown away when the script exits.
  # Parse it instead, and let the user pick the profile up in a new shell.
  # Checked before copying so a broken profile never lands in $HOME.
  if command -v zsh &>/dev/null; then
    echo "Validating .$1..."
    if ! zsh -n "$SCRIPT_DIR/.$1"; then
      echo "Error: .$1 is not valid zsh"
      return 1
    fi
  fi

  cp -R "$SCRIPT_DIR/scripts" "$HOME/"
  cp "$SCRIPT_DIR/.$1" "$HOME/.$1"

  echo "Run 'exec zsh' or open a new terminal to load .$1"
}

install_check() {
  # Non-interactive mode for CI
  if [[ -n "${CI:-}" ]]; then
    echo "Running in CI mode, skipping $1 dependencies..."
    return 0
  fi

  echo "Do you wish to install $1 dependencies?"
  select yn in "Yes" "No"; do
    case $yn in
      Yes)
        eval "${1}_install"
        break
        ;;
      No) break ;;
    esac
  done
}

## ---------- General Packages ---------- ##
packages_install() {
  PACKAGES=(
    git
    gh
    # Sourced by scripts/zsh-plugins, which skips them when they are missing.
    zsh-autosuggestions
    zsh-syntax-highlighting
  )
  brew_install "${PACKAGES[@]}"
  CASKS=(
    google-chrome
    iterm2
    slack
    visual-studio-code
  )
  brew_install --cask "${CASKS[@]}"
}

## ---------- Language Version Managers -- ##
# Latest stable version a version manager offers, from its `install --list`.
# Both rbenv and pyenv list oldest first, so the last plain X.Y.Z line is the
# newest stable release; anything with a suffix (3.4.0-preview1, 3.13.0rc1) or
# a prefix (jruby-, pypy-, miniconda-) is skipped, so a bootstrap never lands
# on a prerelease or an alternative implementation.
latest_stable_version() {
  "$1" install --list 2>/dev/null |
    tr -d '[:blank:]' |
    grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' |
    tail -1
}

# version_to_install <manager> [pinned]
#
# Echoes the version to install: the pinned one when the caller set it,
# otherwise the newest stable the manager knows about.
version_to_install() {
  local manager="$1" pinned="${2:-}" version=""

  if [[ -n "$pinned" ]]; then
    printf '%s\n' "$pinned"
    return 0
  fi

  version="$(latest_stable_version "$manager")" || version=""
  if [[ -z "$version" ]]; then
    echo "Error: could not work out which $manager version to install" >&2
    return 1
  fi

  printf '%s\n' "$version"
}

## ---------- Ruby Dependencies ---------- ##
ruby_install() {
  # Packages to install with Brew
  PACKAGES=(
    rbenv
  )
  brew_install "${PACKAGES[@]}"

  # scripts/rbenv only puts the shims on $PATH in a *new* shell, so without
  # this the gems below would go to the system Ruby - the very thing rbenv is
  # here to avoid, and where `gem install` fails on permissions.
  PATH="$(rbenv root)/shims:$PATH"
  export PATH

  local version
  version="$(version_to_install rbenv "${DOTFILES_RUBY_VERSION:-}")" || return 1

  echo "Installing Ruby $version..."
  rbenv install --skip-existing "$version"
  rbenv global "$version"

  RUBY_GEMS=(
    bundler
  )
  echo "Installing Ruby gems..."
  gem install "${RUBY_GEMS[@]}"
  # A freshly installed gem only gets an executable shim after a rehash.
  rbenv rehash
}

## ---------- Python Dependencies -------- ##
python_install() {
  # No Homebrew python: pyenv builds and owns the interpreter this profile
  # uses, and pip refuses to touch a Homebrew one anyway
  # (error: externally-managed-environment).
  PACKAGES=(
    pyenv
  )
  brew_install "${PACKAGES[@]}"

  # As with rbenv above: scripts/pyenv only takes effect in a new shell.
  PATH="$(pyenv root)/shims:$PATH"
  export PATH

  local version
  version="$(version_to_install pyenv "${DOTFILES_PYTHON_VERSION:-}")" || return 1

  echo "Installing Python $version..."
  pyenv install --skip-existing "$version"
  pyenv global "$version"

  # A pyenv interpreter owns its own site-packages, so pip needs neither
  # --user (unsupported on Homebrew Python) nor a virtualenv of its own.
  echo "Ensuring pip is up to date..."
  python3 -m pip install --upgrade pip
  echo "Install virtualenv..."
  python3 -m pip install virtualenv
  pyenv rehash
}

## ---------- Node Dependencies ---------- ##

# Prints the path to nvm.sh, which has to be sourced before `nvm` exists as a
# shell function. Mirrors the lookup in scripts/nvm: $NVM_DIR for an
# install-script install, Homebrew's prefix for the formula.
nvm_script_path() {
  local brew_prefix=""
  if command -v brew &>/dev/null; then
    brew_prefix="$(brew --prefix nvm 2>/dev/null || true)"
  fi

  local dir
  for dir in "${NVM_DIR:-$HOME/.nvm}" "$brew_prefix"; do
    if [[ -n "$dir" && -s "$dir/nvm.sh" ]]; then
      echo "$dir/nvm.sh"
      return 0
    fi
  done

  echo "Error: could not find nvm.sh; is nvm installed?" >&2
  return 1
}

# nvm is the only node here, the way rbenv and pyenv own their runtimes: a
# Homebrew-installed node would race nvm's shims for $PATH and take the global
# packages with it, and Homebrew's `npm` is just an alias for the `node`
# formula, so it would install node a second time.
node_install() {
  PACKAGES=(
    nvm
  )
  brew_install "${PACKAGES[@]}"

  # The formula leaves $NVM_DIR to us, and nvm needs it to exist before it can
  # install a runtime into it.
  export NVM_DIR="$HOME/.nvm"
  mkdir -p "$NVM_DIR"

  local nvm_sh
  nvm_sh="$(nvm_script_path)" || return 1

  echo "Installing the Node LTS..."
  # nvm.sh is not written to be sourced under `set -eu`, so load it and use it
  # in a subshell with both relaxed; the runtime it installs lands in $NVM_DIR,
  # which outlives the subshell.
  if ! (
    set +eu
    # shellcheck source=/dev/null
    \. "$nvm_sh"
    nvm install --lts && nvm alias default "lts/*"
  ); then
    echo "Error: nvm could not install the Node LTS"
    return 1
  fi
}

# Basic macOS configurations
configure_macos() {
  echo "Configuring macOS..."

  # Set fast key repeat rate
  defaults write NSGlobalDomain KeyRepeat -int 2

  # Require password as soon as screensaver or sleep mode starts
  defaults write com.apple.screensaver askForPassword -int 1
  defaults write com.apple.screensaver askForPasswordDelay -int 0

  # Show filename extensions by default
  defaults write NSGlobalDomain AppleShowAllExtensions -bool true

  # Show battery percentage (note: this may not work on macOS Ventura+ due to Control Center changes)
  defaults write com.apple.menuextra.battery ShowPercent -string "YES" 2>/dev/null || true

  # Stop the bouncing icons
  defaults write com.apple.dock no-bouncing -bool true

  # The writes above only land when the app that owns the preference restarts,
  # so the Dock and Finder changes would otherwise appear not to have worked.
  # Skipped in CI, where there is nothing running to restart, and never allowed
  # to fail the bootstrap: killall exits non-zero when an app is not running.
  if [[ -n "${CI:-}" ]]; then
    echo "Running in CI mode, skipping app restarts..."
  else
    echo "Restarting Dock, Finder and SystemUIServer to apply the settings..."
    killall Dock Finder SystemUIServer 2>/dev/null || true
  fi
}

# Actual script
main() {
  echo "Starting Bootstrapping..."
  homebrew_install
  install_check "packages"
  install_check "ruby"
  install_check "python"
  install_check "node"
  source_profile "zshrc"
  configure_macos
  homebrew_cleanup
  echo "Bootstrapping Complete!"
}

# Only bootstrap when executed. Sourcing the file just defines the functions,
# which is how tests/install_test.sh exercises them.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
