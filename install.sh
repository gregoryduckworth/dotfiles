#!/usr/bin/env bash
set -euo pipefail

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
  if [[ ! -f ".$1" ]]; then
    echo "Error: .$1 not found"
    return 1
  fi
  
  if [[ ! -d "scripts" ]]; then
    echo "Error: scripts directory not found"
    return 1
  fi
  
  cp -R scripts ~/
  cp ".$1" ~/."$1"

  echo "Sourcing .$1..."
  source ~/."$1"
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

  # Clear all command history
  history -c
}

# Actual script
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
