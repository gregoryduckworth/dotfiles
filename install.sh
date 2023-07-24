#! /usr/bin/env bash

homebrew_install() {
  # Check for Homebrew, install if we don't have it
  if test ! $(which brew); then
    echo "Installing homebrew..."
    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
  fi
  
  # Update homebrew recipes
  brew update
}

# Clean up brew
homebrew_cleanup() {
  echo "Cleaning up..."
  brew cleanup
}

# General Brew Install
brew_install() {
  echo "Installing packages..."
  for package in $@; do
    if ! brew info $package &>/dev/null; then
      echo "Installing $package..."
      brew install $package
    else
       echo "$package is already installed..."
    fi
  done
}

# General Brew Install
brew_cask_install() {
  echo "Installing casks..."
  for cask in $@; do
    if ! brew info $cask &>/dev/null; then
      echo "Installing $cask..."
      brew install $cask --cask
    else
       echo "$cask is already installed..."
    fi
  done
}

# Create and source the file
source_profile() {
  echo "Creating .$1 file..."
  sudo cp -R scripts ~/
  sudo cp .$1 ~/.$1

  echo "Sourcing .$1..."
  source ~/.$1
  exec ~/.$1
}

install_check() {
  echo "Do you wish to install $1 dependencies?"
  select yn in "Yes" "No"; do
      case $yn in
          Yes ) $1_install; break;;
          No ) break;;
      esac
  done
}

## ---------- General Packages ---------- ##
packages_install() {
  PACKAGES=(
    git
    gh
  )
  brew_install "" "${PACKAGES[@]}"
  CASKS=(
    google-chrome
    iterm2
    slack
    visual-studio-code
  )
  brew_cask_install "${CASKS[@]}"
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
  sudo gem install ${RUBY_GEMS[@]}
}

## ---------- Python Dependencies -------- ##
python_install() {
  PACKAGES=(
    python
    pyenv
  )
  brew_install "${PACKAGES[@]}"
  echo "Checking Python version..."
  python --version
  echo "Installing pip..."
  curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
  sudo python get-pip.py
  echo "Install virtualenv..."
  sudo pip install virtualenv
}

## ---------- Node Dependencies ---------- ##
node_install() {
  PACKAGES=(
    node
    npm
    nvm
  )
  brew_install ${PACKAGES[@]}
}

# Basic OSX configurations
configure_osx() {
  echo "Configuring OSX..."

  # Set fast key repeat rate
  defaults write NSGlobalDomain KeyRepeat -int 2

  # Require password as soon as screensaver or sleep mode starts
  defaults write com.apple.screensaver askForPassword -int 1
  defaults write com.apple.screensaver askForPasswordDelay -int 0

  # Show filename extensions by default
  defaults write NSGlobalDomain AppleShowAllExtensions -bool true

  # Show battery percentage
  defaults write com.apple.menuextra.battery ShowPercent -string "YES"

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
configure_osx
homebrew_cleanup
echo "Bootstrapping Complete!"
