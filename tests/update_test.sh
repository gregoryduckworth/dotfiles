#!/usr/bin/env bash
# Tests for update.sh. main() ends in `exec zsh`, so the tests drive
# install_profile directly and check the prompt handling separately.
#
# shellcheck disable=SC2031
# shellcheck source-path=SCRIPTDIR
set -uo pipefail

# shellcheck source=helpers/framework.sh
source "$(dirname "$0")/helpers/framework.sh"

# update.sh updates only when executed, not when sourced (see
# test_sourcing_update_sh_does_not_run_main). Point $HOME at a scratch directory
# and close stdin anyway, so a regression in that guard cannot overwrite the
# dotfiles of whoever runs the suite. Each test gets its own $HOME from the
# framework regardless.
HOME="$(mktemp -d)"
# shellcheck source=../update.sh
source "$REPO_ROOT/update.sh" </dev/null

test_install_profile_copies_profile_and_scripts() {
  # prove the script does not depend on the caller's working directory
  cd "$TEST_TMP" || fail "could not enter $TEST_TMP"
  install_profile >/dev/null

  diff "$REPO_ROOT/.zshrc" "$HOME/.zshrc" || fail "installed .zshrc differs"
  diff -r "$REPO_ROOT/scripts" "$HOME/scripts" || fail "installed scripts differ"
}

test_install_profile_is_idempotent() {
  install_profile >/dev/null
  install_profile >/dev/null

  assert_missing "$HOME/scripts/scripts"
  diff -r "$REPO_ROOT/scripts" "$HOME/scripts" || fail "installed scripts differ"
}

test_install_profile_does_not_use_sudo() {
  # Root-owned files in $HOME break every later update, so update.sh must not
  # reach for sudo just to copy into the user's own home directory.
  stub sudo 'exit 1'
  install_profile >/dev/null

  assert_eq "" "$(stub_calls sudo)" "install_profile shelled out to sudo"
}

test_sourcing_update_sh_does_not_run_main() {
  local output
  # main() ends in `exec zsh`, which would replace the process rather than fail
  # an assertion, so the check is that execution gets past the source at all.
  output="$(bash -c 'source "$1"; echo reached-the-end' bash "$REPO_ROOT/update.sh" </dev/null)"

  assert_eq "reached-the-end" "$output"
  assert_missing "$HOME/.zshrc"
}

# Runs update.sh as a real program with the given answer on stdin. zsh is
# replaced by a stub so `exec /bin/zsh` cannot hijack the test run.
run_update() {
  local answer="$1" fake="$TEST_TMP/checkout"
  mkdir -p "$fake/bin"
  cp "$REPO_ROOT/.zshrc" "$fake/"
  cp -R "$REPO_ROOT/scripts" "$fake/"

  # update.sh ends in `exec /bin/zsh`. Point that at a do-nothing stub so the
  # exec cannot replace the test process with a real interactive shell.
  echo '#!/usr/bin/env bash' >"$fake/bin/zsh"
  chmod +x "$fake/bin/zsh"
  sed "s|exec /bin/zsh|exec '$fake/bin/zsh'|" "$REPO_ROOT/update.sh" >"$fake/update.sh"

  bash "$fake/update.sh" <<<"$answer"
}

test_update_installs_when_answer_is_empty() {
  # The prompt defaults to yes, so a bare Return must still update.
  run_update "" >/dev/null

  assert_file "$HOME/.zshrc"
}

test_update_installs_when_answer_is_yes() {
  run_update "y" >/dev/null

  assert_file "$HOME/.zshrc"
}

test_update_skips_when_answer_is_no() {
  run_update "n" >/dev/null

  assert_missing "$HOME/.zshrc"
  assert_missing "$HOME/scripts"
}

run_tests "$@"
