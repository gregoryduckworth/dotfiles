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
      Yes) eval "${1}_install"; break ;;
      No) break ;;
    esac
  done
}

## ---------- General Packages ---------- ##
packages_install() {
  PACKAGES=(
    git
    gh
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

## ---------- Ruby Dependencies ---------- ##
ruby_install() {
  # Packages to install with Brew
  PACKAGES=(
    rbenv
  )
  brew_install "${PACKAGES[@]}"
  RUBY_GEMS=(
    bundler
  )
  echo "Installing Ruby gems..."
  gem install "${RUBY_GEMS[@]}"
}

## ---------- Python Dependencies -------- ##
python_install() {
  PACKAGES=(
    python
    pyenv
  )
  brew_install "${PACKAGES[@]}"
  echo "Checking Python version..."
  python3 --version
  # pip is included with Python 3.4+, so we just need to ensure it's up to date
  echo "Ensuring pip is up to date..."
  python3 -m pip install --upgrade pip --user
  echo "Install virtualenv..."
  python3 -m pip install --user virtualenv
}

## ---------- Node Dependencies ---------- ##
node_install() {
  PACKAGES=(
    node
    npm
    nvm
  )
  brew_install "${PACKAGES[@]}"
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
