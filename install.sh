#!/usr/bin/env bash

echo "Starting Bootstrapping..."

# Check for Homebrew, install if we don't have it
if test ! $(which brew); then
    echo "Installing homebrew..."
    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
fi

# Update homebrew recipes
brew update

# Packages to install with Brew
PACKAGES=(
    git
    hub
    rbenv
    python
    pyenv
)

echo "Installing packages..."
brew install ${PACKAGES[@]}

echo "Cleaning up..."
brew cleanup

# Apps to install with Brew
CASKS=(
    docker
    dropbox
    google-chrome
    iterm2
    java
    skype
    slack
    visual-studio-code
)

echo "Installing cask apps..."
brew cask install ${CASKS[@]}

# Packages to install with Brew
echo "Installing Ruby gems..."
RUBY_GEMS=(
    bundler
)

sudo gem install ${RUBY_GEMS[@]}

NODE_PACKAGES=(
    node
    npm
    nvm
)
echo "Installing Node packages..."
brew install ${NODE_PACKAGES[@]}

echo "Setting to dark mode..."
sudo npm i -g macdarkmode
darkmode true

echo "Checking Python version..."
python --version

echo "Installing pip..."
curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
sudo python get-pip.py

echo "Install virtualenv..."
sudo pip install virtualenv

echo "Creating .bash_profile file..."
cp -R scripts ~/
cp .bash_profile ~/.bash_profile

echo "Sourcing .bash_profile..."
. ~/.bash_profile
exec bash_profile

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

# Clear all command history
history -c

echo "Bootstrapping Complete!"
