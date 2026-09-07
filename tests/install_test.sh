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
