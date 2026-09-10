#!/usr/bin/env bash
set -euo pipefail

# Resolve everything against the checkout rather than the caller's working
# directory, so `~/somewhere/dotfiles/install.sh` works from anywhere.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HOMEBREW_INSTALLER="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
OH_MY_ZSH_REPO="https://github.com/ohmyzsh/ohmyzsh.git"

# Set by --dry-run. Every command that changes the machine goes through run(),
# so flipping this to 1 turns the whole script into a description of itself.
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: install.sh [options]

Bootstraps a machine: installs Homebrew, offers each group of optional
dependencies in turn, installs oh-my-zsh, symlinks scripts/ and .zshrc into
$HOME, and writes a few macOS defaults.

Options:
  -n, --dry-run  Print the commands that would change the machine, and run
                 none of them.
  -h, --help     Show this help and exit.

Optional dependency groups, each prompted for separately: packages, ruby,
python, node. Set CI to a non-empty value to decline all of them without
being asked.
EOF
}

# run <command...>: runs the command, or prints it when --dry-run is in effect.
# Read-only commands (brew list, zsh -n) are called directly, so a dry run still
# reports what is already installed.
run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] $*"
    return 0
  fi
  "$@"
}

homebrew_install() {
  # Check for Homebrew, install if we don't have it
  if ! command -v brew &>/dev/null; then
    echo "Installing Homebrew..."
    # Not run through run(): the installer is fetched inside a command
    # substitution, which a dry run must not reach either.
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "[dry-run] /bin/bash -c \"\$(curl -fsSL $HOMEBREW_INSTALLER)\""
    elif ! /bin/bash -c "$(curl -fsSL "$HOMEBREW_INSTALLER")"; then
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
  run brew update
}

# Clean up Homebrew
homebrew_cleanup() {
  echo "Cleaning up..."
  run brew cleanup
}

# Installs everything declared in one of the checkout's Brewfiles. Homebrew
# handles formulae, casks, taps and the already-installed check itself, so
# adding a package is a one-line diff to a Brewfile rather than a shell edit.
brew_bundle() {
  local brewfile="$SCRIPT_DIR/$1"

  if [[ ! -f "$brewfile" ]]; then
    echo "Error: $1 not found"
    return 1
  fi

  echo "Installing packages from $1..."
  run brew bundle --file="$brewfile"
}

# oh-my-zsh, cloned rather than run through its own installer. The other half
# of that installer is writing a .zshrc and running chsh, and this repo owns
# the first and does not ask for the second; a clone is all `omz update`
# needs. scripts/oh-my-zsh loads it, and skips itself when it is not there.
oh_my_zsh_install() {
  local dir="${ZSH:-$HOME/.oh-my-zsh}"

  if [[ -d "$dir" ]]; then
    echo "oh-my-zsh is already installed at $dir"
    return 0
  fi

  echo "Installing oh-my-zsh..."
  if ! run git clone --depth=1 "$OH_MY_ZSH_REPO" "$dir"; then
    echo "Error: oh-my-zsh installation failed"
    return 1
  fi
}

# link_into_checkout <target> <link>
#
# Points <link> at <target>, so the installed dotfiles are the checkout rather
# than copies of it and `git pull` is the whole update.
link_into_checkout() {
  local target="$1" link="$2" backup

  # A symlink here is one we installed, so it is replaced silently. Anything
  # else is the user's own file and is moved aside instead of clobbered.
  if [[ -e "$link" && ! -L "$link" ]]; then
    backup="$link.backup-$(date +%Y%m%d%H%M%S)"
    echo "Moving existing $link aside to $backup..."
    run mv "$link" "$backup"
  fi

  # -n stops ln from following an existing symlink to a directory and nesting
  # the new link inside the target rather than replacing the link.
  run ln -sfn "$target" "$link"
}

# Link the profile and scripts into $HOME
source_profile() {
  echo "Linking .$1 and scripts into \$HOME..."

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
  # Checked before linking so a broken profile is never what $HOME points at.
  if command -v zsh &>/dev/null; then
    echo "Validating .$1..."
    if ! zsh -n "$SCRIPT_DIR/.$1"; then
      echo "Error: .$1 is not valid zsh"
      return 1
    fi
  fi

  link_into_checkout "$SCRIPT_DIR/scripts" "$HOME/scripts"
  link_into_checkout "$SCRIPT_DIR/.$1" "$HOME/.$1"

  echo "Run 'exec zsh' or open a new terminal to load .$1"
}

install_check() {
  # Non-interactive mode for CI
  if [[ -n "${CI:-}" ]]; then
    echo "Running in CI mode, skipping $1 dependencies..."
    return 0
  fi

  local yn choice=""
  echo "Do you wish to install $1 dependencies?"
  # The answer is only recorded here; the install itself runs below, so the
  # `|| true` on the loop cannot swallow a failure from ${1}_install.
  select yn in "Yes" "No"; do
    case $yn in
      Yes)
        choice=yes
        break
        ;;
      No)
        choice=no
        break
        ;;
      # $yn is empty for anything that is not one of the listed numbers.
      # Without this branch the prompt simply reappeared, with no hint that the
      # answer was not understood or that Ctrl-D is the way out.
      *) echo "'$REPLY' is not one of the choices. Enter 1 for Yes, 2 for No, or Ctrl-D to skip $1." ;;
    esac
  done || true # select exits non-zero at end of input (Ctrl-D)

  if [[ -z "$choice" ]]; then
    echo "No answer given, skipping $1 dependencies..."
    return 0
  fi

  if [[ "$choice" == "yes" ]]; then
    eval "${1}_install"
  fi
}

## ---------- General Packages ---------- ##
packages_install() {
  brew_bundle Brewfile
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
    # A dry run reaches here whenever $manager is not on the machine yet: the
    # `brew install` that would have provided it was only printed. Report the
    # step rather than failing on a version that cannot be known in advance.
    if [[ $DRY_RUN -eq 1 ]]; then
      printf '%s\n' "<latest stable>"
      return 0
    fi
    echo "Error: could not work out which $manager version to install" >&2
    return 1
  fi

  printf '%s\n' "$version"
}

## ---------- Ruby Dependencies ---------- ##
ruby_install() {
  brew_bundle Brewfile.ruby

  # scripts/rbenv only puts the shims on $PATH in a *new* shell, so without
  # this the gems below would go to the system Ruby - the very thing rbenv is
  # here to avoid, and where `gem install` fails on permissions. Skipped in a
  # dry run, where `rbenv root` would fail because rbenv was never installed.
  if [[ $DRY_RUN -eq 0 ]]; then
    PATH="$(rbenv root)/shims:$PATH"
    export PATH
  fi

  local version
  version="$(version_to_install rbenv "${DOTFILES_RUBY_VERSION:-}")" || return 1

  echo "Installing Ruby $version..."
  run rbenv install --skip-existing "$version"
  run rbenv global "$version"

  RUBY_GEMS=(
    bundler
  )
  echo "Installing Ruby gems..."
  run gem install "${RUBY_GEMS[@]}"
  # A freshly installed gem only gets an executable shim after a rehash.
  run rbenv rehash
}

## ---------- Python Dependencies -------- ##
python_install() {
  brew_bundle Brewfile.python

  # As with rbenv above: scripts/pyenv only takes effect in a new shell, and a
  # dry run has no pyenv to ask for its root.
  if [[ $DRY_RUN -eq 0 ]]; then
    PATH="$(pyenv root)/shims:$PATH"
    export PATH
  fi

  local version
  version="$(version_to_install pyenv "${DOTFILES_PYTHON_VERSION:-}")" || return 1

  echo "Installing Python $version..."
  run pyenv install --skip-existing "$version"
  run pyenv global "$version"

  # A pyenv interpreter owns its own site-packages, so pip needs neither
  # --user (unsupported on Homebrew Python) nor a virtualenv of its own.
  echo "Ensuring pip is up to date..."
  run python3 -m pip install --upgrade pip
  echo "Install virtualenv..."
  run python3 -m pip install virtualenv
  run pyenv rehash
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
  brew_bundle Brewfile.node

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
  run defaults write NSGlobalDomain KeyRepeat -int 2

  # Require password as soon as screensaver or sleep mode starts
  run defaults write com.apple.screensaver askForPassword -int 1
  run defaults write com.apple.screensaver askForPasswordDelay -int 0

  # Show filename extensions by default
  run defaults write NSGlobalDomain AppleShowAllExtensions -bool true

  # Show battery percentage (note: this may not work on macOS Ventura+ due to Control Center changes)
  run defaults write com.apple.menuextra.battery ShowPercent -string "YES" 2>/dev/null || true

  # Stop the bouncing icons
  run defaults write com.apple.dock no-bouncing -bool true

  # The writes above only land when the app that owns the preference restarts,
  # so the Dock and Finder changes would otherwise appear not to have worked.
  # Skipped in CI, where there is nothing running to restart, and never allowed
  # to fail the bootstrap: killall exits non-zero when an app is not running.
  if [[ -n "${CI:-}" ]]; then
    echo "Running in CI mode, skipping app restarts..."
  else
    echo "Restarting Dock, Finder and SystemUIServer to apply the settings..."
    run killall Dock Finder SystemUIServer 2>/dev/null || true
  fi
}

# Actual script
main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help)
        usage
        return 0
        ;;
      -n | --dry-run)
        DRY_RUN=1
        shift
        ;;
      *)
        echo "Error: unknown option '$1'" >&2
        usage >&2
        return 2
        ;;
    esac
  done

  echo "Starting Bootstrapping..."
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "Dry run: the commands below are printed, not run."
  fi
  homebrew_install
  install_check "packages"
  install_check "ruby"
  install_check "python"
  install_check "node"
  oh_my_zsh_install
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
