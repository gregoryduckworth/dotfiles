# Packages installed on every machine.
#
#   brew bundle --file=Brewfile         # install
#   brew bundle check --file=Brewfile   # dry run: what is missing?
#   brew bundle cleanup --file=Brewfile # report packages no longer declared
#
# The optional per-language groups live in Brewfile.ruby and Brewfile.python.
# `brew bundle` has no tag support, so a group is a file. Node has no Brewfile:
# install.sh clones nvm itself.

brew "git"
brew "gh"

# Sourced by scripts/zsh-plugins, which skips them when they are missing.
brew "zsh-autosuggestions"
brew "zsh-syntax-highlighting"

# Docker, with colima as the runtime instead of Docker Desktop. compose and
# buildx are CLI plugins in their own formulae, and Homebrew's docker finds them
# without any ~/.docker/config.json. colima runs as a login service, so
# `docker` works in a new terminal without a `colima start` first.
brew "docker"
brew "docker-buildx"
brew "docker-compose"
brew "colima", restart_service: :changed

cask "google-chrome"
cask "iterm2"
cask "slack"
cask "visual-studio-code"
