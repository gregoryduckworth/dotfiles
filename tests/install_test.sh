#!/usr/bin/env bash
# Tests for install.sh. Sourcing the script only defines its functions, so each
# one can be exercised against stub commands and a throwaway $HOME.
#
# $HOME, $TEST_TMP and the stub helpers are set per test by the framework's
# subshell runner, which shellcheck cannot see, hence the SC2031 disable.
# shellcheck disable=SC2031
# shellcheck source-path=SCRIPTDIR
set -uo pipefail

# shellcheck source=helpers/framework.sh
source "$(dirname "$0")/helpers/framework.sh"

# install.sh bootstraps only when executed, not when sourced (see
# test_sourcing_install_sh_does_not_bootstrap). Point $HOME at a scratch
# directory and close stdin anyway, so a regression in that guard cannot
# bootstrap the machine of whoever runs the suite. Each test gets its own $HOME
# from the framework regardless.
HOME="$(mktemp -d)"
# shellcheck source=../install.sh
source "$REPO_ROOT/install.sh" </dev/null

# A brew stub that reports every package as missing.
stub_brew_missing() {
  # shellcheck disable=SC2016  # the stub body is a script, not a string to expand
  stub brew '[[ "$1 $2" == list* ]] && exit 1; exit 0'
}

# A brew stub that reports every package as already installed.
stub_brew_present() {
  stub brew 'exit 0'
}

## ---------- brew_install ---------- ##

test_brew_install_installs_missing_formulae() {
  stub_brew_missing
  brew_install git gh >/dev/null

  assert_stub_called brew "list --formula git"
  assert_stub_called brew "install git"
  assert_stub_called brew "install gh"
}

test_brew_install_skips_installed_formulae() {
  stub_brew_present
  local output
  output="$(brew_install git)"

  assert_stub_not_called brew "install git"
  assert_contains "$output" "git is already installed"
}

test_brew_install_uses_cask_for_casks() {
  stub_brew_missing
  brew_install --cask iterm2 >/dev/null

  assert_stub_called brew "list --cask iterm2"
  assert_stub_called brew "install --cask iterm2"
  assert_stub_not_called brew "install iterm2"
}

test_brew_install_handles_packages_with_dashes() {
  stub_brew_missing
  brew_install --cask google-chrome visual-studio-code >/dev/null

  assert_stub_called brew "install --cask google-chrome"
  assert_stub_called brew "install --cask visual-studio-code"
}

## ---------- homebrew_install / homebrew_cleanup ---------- ##

test_homebrew_install_only_updates_when_brew_exists() {
  stub brew 'exit 0'
  stub curl 'echo "curl should not have been called" >&2; exit 1'
  homebrew_install >/dev/null

  assert_eq "update" "$(stub_calls brew)"
  assert_eq "" "$(stub_calls curl)" "curl was called even though brew exists"
}

test_homebrew_cleanup_runs_brew_cleanup() {
  stub brew 'exit 0'
  homebrew_cleanup >/dev/null

  assert_stub_called brew "cleanup"
}

## ---------- install_check ---------- ##

test_install_check_skips_prompt_in_ci() {
  # Invoked indirectly, via eval in install_check. Older shellcheck reports
  # that as SC2317 on the body, newer as SC2329 on the function.
  # shellcheck disable=SC2317,SC2329
  demo_install() { touch "$TEST_TMP/demo-ran"; }
  CI=1 install_check demo >/dev/null

  assert_missing "$TEST_TMP/demo-ran"
}

test_install_check_installs_when_user_answers_yes() {
  # Invoked indirectly, via eval in install_check. Older shellcheck reports
  # that as SC2317 on the body, newer as SC2329 on the function.
  # shellcheck disable=SC2317,SC2329
  demo_install() { touch "$TEST_TMP/demo-ran"; }
  CI="" install_check demo <<<"1" >/dev/null

  assert_file "$TEST_TMP/demo-ran"
}

test_install_check_skips_when_user_answers_no() {
  # Invoked indirectly, via eval in install_check. Older shellcheck reports
  # that as SC2317 on the body, newer as SC2329 on the function.
  # shellcheck disable=SC2317,SC2329
  demo_install() { touch "$TEST_TMP/demo-ran"; }
  CI="" install_check demo <<<"2" >/dev/null

  assert_missing "$TEST_TMP/demo-ran"
}

## ---------- source_profile ---------- ##

test_source_profile_installs_profile_and_scripts() {
  # prove the script does not depend on the caller's working directory
  cd "$TEST_TMP" || fail "could not enter $TEST_TMP"
  source_profile zshrc >/dev/null

  assert_file "$HOME/.zshrc"
  assert_file "$HOME/scripts/git"
  diff "$REPO_ROOT/.zshrc" "$HOME/.zshrc" || fail "installed .zshrc differs"
  diff -r "$REPO_ROOT/scripts" "$HOME/scripts" || fail "installed scripts differ"
}

test_source_profile_is_idempotent() {
  source_profile zshrc >/dev/null
  source_profile zshrc >/dev/null

  # A second run must refresh ~/scripts in place, not nest a copy inside it.
  assert_missing "$HOME/scripts/scripts"
  diff -r "$REPO_ROOT/scripts" "$HOME/scripts" || fail "installed scripts differ"
}

test_source_profile_removes_nothing_the_user_owns() {
  mkdir -p "$HOME/scripts"
  echo "mine" >"$HOME/scripts/local"
  source_profile zshrc >/dev/null

  assert_file "$HOME/scripts/local"
}

test_source_profile_keeps_the_local_override() {
  # ~/.zshrc.local holds machine-specific settings and secrets, so an install
  # must never overwrite or remove it.
  echo 'export SECRET=mine' >"$HOME/.zshrc.local"
  source_profile zshrc >/dev/null

  assert_eq "export SECRET=mine" "$(cat "$HOME/.zshrc.local")"
}

# Copies install.sh into a checkout-shaped directory so the failure paths can be
# exercised without touching the real repo. Sets FAKE_CHECKOUT; the caller
# populates it and then re-sources install.sh from there, which repoints
# SCRIPT_DIR at the fake checkout.
fake_checkout() {
  FAKE_CHECKOUT="$TEST_TMP/checkout"
  mkdir -p "$FAKE_CHECKOUT"
  cp "$REPO_ROOT/install.sh" "$FAKE_CHECKOUT/"
}

test_source_profile_fails_when_profile_missing() {
  fake_checkout
  mkdir -p "$FAKE_CHECKOUT/scripts"
  # shellcheck source=../install.sh
  source "$FAKE_CHECKOUT/install.sh"

  assert_failure source_profile zshrc
}

test_source_profile_fails_when_scripts_missing() {
  fake_checkout
  touch "$FAKE_CHECKOUT/.zshrc"
  # shellcheck source=../install.sh
  source "$FAKE_CHECKOUT/install.sh"

  assert_failure source_profile zshrc
}

test_source_profile_rejects_invalid_zsh() {
  skip_unless_command zsh
  fake_checkout
  mkdir -p "$FAKE_CHECKOUT/scripts"
  echo 'if then fi done' >"$FAKE_CHECKOUT/.zshrc"
  # shellcheck source=../install.sh
  source "$FAKE_CHECKOUT/install.sh"

  assert_failure source_profile zshrc
  # A profile that does not parse must never reach $HOME.
  assert_missing "$HOME/.zshrc"
}

## ---------- configure_macos ---------- ##

test_configure_macos_writes_expected_defaults() {
  stub defaults 'exit 0'
  stub killall 'exit 0'
  CI="" configure_macos >/dev/null

  assert_stub_called defaults "write NSGlobalDomain KeyRepeat -int 2"
  assert_stub_called defaults "write com.apple.screensaver askForPassword -int 1"
  assert_stub_called defaults "write NSGlobalDomain AppleShowAllExtensions -bool true"
  assert_stub_called defaults "write com.apple.dock no-bouncing -bool true"
}

test_configure_macos_survives_a_failing_defaults_write() {
  # The battery percentage write is expected to fail on recent macOS.
  # shellcheck disable=SC2016  # the stub body is a script, not a string to expand
  stub defaults '[[ "$2" == com.apple.menuextra.battery ]] && exit 1; exit 0'
  stub killall 'exit 0'
  CI="" configure_macos >/dev/null
}

# The Dock and Finder only pick the new preferences up when they restart.
test_configure_macos_restarts_the_apps_that_own_the_settings() {
  stub defaults 'exit 0'
  stub killall 'exit 0'
  CI="" configure_macos >/dev/null

  assert_stub_called killall "Dock Finder SystemUIServer"
}

test_configure_macos_survives_killall_finding_nothing_to_restart() {
  stub defaults 'exit 0'
  # killall exits non-zero when an app is not running, which must not abort the
  # bootstrap.
  stub killall 'exit 1'
  CI="" configure_macos >/dev/null
}

test_configure_macos_does_not_restart_apps_in_ci() {
  stub defaults 'exit 0'
  stub killall 'exit 0'
  CI=1 configure_macos >/dev/null

  assert_eq "" "$(stub_calls killall)" "CI restarted the Dock"
}

# `history -c` used to sit at the end of configure_macos, where it only cleared
# the empty history of the non-interactive bash running the script.
test_configure_macos_does_not_touch_shell_history() {
  assert_not_contains "$(cat "$REPO_ROOT/install.sh")" "history -c"
}

## ---------- version resolution ---------- ##

# A version manager whose `install --list` looks like the real thing: sorted
# oldest first, with prereleases and alternative implementations mixed in.
stub_version_manager() {
  # shellcheck disable=SC2016  # the stub body is a script, not a string to expand
  stub "$1" '
    case "$1 $2" in
      "install --list")
        printf "  %s\n" 2.7.18 3.2.6 3.3.6 3.4.0-preview1 jruby-9.4.9.0 ;;
      "root ") echo "$HOME/.$(basename "$0")" ;;
    esac
    exit 0'
}

test_latest_stable_version_picks_the_newest_release() {
  stub_version_manager demoenv

  # Not the prerelease that sorts after it, and not the alternative runtime.
  assert_eq "3.3.6" "$(latest_stable_version demoenv)"
}

test_version_to_install_prefers_a_pinned_version() {
  stub_version_manager demoenv

  assert_eq "3.2.2" "$(version_to_install demoenv 3.2.2)"
  assert_eq "" "$(stub_calls demoenv)" "a pinned version still asked for the list"
}

test_version_to_install_fails_when_the_list_is_empty() {
  stub demoenv 'exit 0'

  assert_failure version_to_install demoenv ""
}

## ---------- ruby_install / python_install ---------- ##

# shim <dir> <name>: an executable outside $STUB_BIN that records its calls
# under "shim-<name>", so a test can tell the version manager's shim apart from
# the system command of the same name.
shim() {
  local dir="$1" name="$2"
  mkdir -p "$dir"
  {
    echo '#!/usr/bin/env bash'
    printf 'printf "%%s\\n" "$*" >>%q\n' "$STUB_CALLS/shim-$name"
    echo 'exit 0'
  } >"$dir/$name"
  chmod +x "$dir/$name"
}

# rbenv plus a shimmed gem, and a system gem that fails the way the real one
# does when it is asked to write into a root-owned Ruby.
stub_ruby_env() {
  stub_brew_missing
  stub_version_manager rbenv
  shim "$HOME/.rbenv/shims" gem
  stub gem 'echo "system gem: permission denied" >&2; exit 1'
}

# pyenv plus a shimmed python3, and a system python3 that refuses the way
# Homebrew's does.
stub_python_env() {
  stub_brew_missing
  stub_version_manager pyenv
  shim "$HOME/.pyenv/shims" python3
  stub python3 'echo "error: externally-managed-environment" >&2; exit 1'
}

test_ruby_install_installs_a_ruby_before_any_gem() {
  stub_ruby_env
  ruby_install >/dev/null

  assert_stub_called brew "install rbenv"
  assert_stub_called rbenv "install --skip-existing 3.3.6"
  assert_stub_called rbenv "global 3.3.6"
  assert_stub_called shim-gem "install bundler"
  # New executables are only reachable once rbenv has written their shims.
  assert_stub_called rbenv "rehash"
}

test_ruby_install_never_uses_the_system_gem() {
  stub_ruby_env
  ruby_install >/dev/null

  assert_stub_not_called gem "install bundler"
}

test_ruby_install_honours_a_pinned_version() {
  stub_ruby_env
  DOTFILES_RUBY_VERSION=3.2.2 ruby_install >/dev/null

  assert_stub_called rbenv "install --skip-existing 3.2.2"
  assert_stub_called rbenv "global 3.2.2"
}

test_ruby_install_stops_when_no_version_can_be_resolved() {
  stub_brew_missing
  # A manager whose list is empty, so no version can be resolved.
  # shellcheck disable=SC2016  # the stub body is a script, not a string to expand
  stub rbenv 'case "$1 $2" in "root ") echo "$HOME/.rbenv" ;; esac; exit 0'
  shim "$HOME/.rbenv/shims" gem

  assert_failure ruby_install
  assert_missing "$STUB_CALLS/shim-gem"
}

test_python_install_installs_a_python_before_any_pip() {
  stub_python_env
  python_install >/dev/null

  assert_stub_called brew "install pyenv"
  assert_stub_called pyenv "install --skip-existing 3.3.6"
  assert_stub_called pyenv "global 3.3.6"
  assert_stub_called shim-python3 "-m pip install --upgrade pip"
  assert_stub_called shim-python3 "-m pip install virtualenv"
}

test_python_install_never_uses_the_system_python() {
  stub_python_env
  python_install >/dev/null

  # Homebrew's python3 refuses both of these: --user is unsupported, and pip
  # reports an externally-managed-environment.
  assert_eq "" "$(stub_calls python3)" "python_install used the system python3"
  assert_stub_not_called brew "install python"
  assert_not_contains "$(stub_calls shim-python3)" "--user"
}

test_python_install_honours_a_pinned_version() {
  stub_python_env
  DOTFILES_PYTHON_VERSION=3.12.7 python_install >/dev/null

  assert_stub_called pyenv "install --skip-existing 3.12.7"
  assert_stub_called pyenv "global 3.12.7"
}

test_python_install_stops_when_no_version_can_be_resolved() {
  stub_brew_missing
  # A manager whose list is empty, so no version can be resolved.
  # shellcheck disable=SC2016  # the stub body is a script, not a string to expand
  stub pyenv 'case "$1 $2" in "root ") echo "$HOME/.pyenv" ;; esac; exit 0'
  shim "$HOME/.pyenv/shims" python3

  assert_failure python_install
  assert_missing "$STUB_CALLS/shim-python3"
}

## ---------- main guard ---------- ##

test_sourcing_install_sh_does_not_bootstrap() {
  stub brew 'exit 0'
  stub defaults 'exit 0'
  # stdin is closed so a regression fails the test instead of hanging on the
  # interactive prompt.
  # shellcheck source=../install.sh
  source "$REPO_ROOT/install.sh" </dev/null

  assert_eq "" "$(stub_calls brew)" "sourcing install.sh ran the bootstrap"
  assert_missing "$HOME/.zshrc"
}

run_tests "$@"
