#!/usr/bin/env bash
# Tests for .zshrc, the profile that install.sh and update.sh drop into $HOME.
#
# The single-quoted arguments below are zsh snippets run in a child shell, so
# they are deliberately not expanded by bash (SC2016); $HOME and friends are set
# per test by the framework's subshell runner (SC2031).
# shellcheck disable=SC2016,SC2031
# shellcheck source-path=SCRIPTDIR
set -uo pipefail

# shellcheck source=helpers/framework.sh
source "$(dirname "$0")/helpers/framework.sh"
# shellcheck source=helpers/zsh.sh
source "$(dirname "$0")/helpers/zsh.sh"

test_profile_loads_every_script() {
  skip_unless_command zsh
  install_profile_into_home

  # One representative from each file in scripts/.
  assert_eq "1" "$(zsh_profile 'echo $DOCKER_BUILDKIT')" "scripts/docker"
  assert_eq "0" "$(zsh_profile 'alias gs >/dev/null; echo $?')" "scripts/github"
  assert_eq "0" "$(zsh_profile 'whence -w parse_git_branch >/dev/null; echo $?')" "scripts/git"
  assert_contains "$(zsh_profile 'echo $CHROME')" "Google" "scripts/browserstack"
  assert_contains "$(zsh_profile 'echo $NVM_DIR')" ".nvm" "scripts/nvm"
}

test_profile_survives_a_missing_scripts_directory() {
  skip_unless_command zsh
  cp "$REPO_ROOT/.zshrc" "$HOME/.zshrc"

  # Without a null glob the loop would try to source the literal
  # "~/scripts/*" and abort every caller running under errexit.
  zsh_profile || fail ".zshrc failed with no ~/scripts directory"
}

test_profile_survives_an_empty_scripts_directory() {
  skip_unless_command zsh
  cp "$REPO_ROOT/.zshrc" "$HOME/.zshrc"
  mkdir -p "$HOME/scripts"

  zsh_profile || fail ".zshrc failed with an empty ~/scripts directory"
}

test_profile_handles_script_names_with_spaces() {
  skip_unless_command zsh
  install_profile_into_home
  echo 'export SPACED=loaded' >"$HOME/scripts/my script"

  assert_eq "loaded" "$(zsh_profile 'echo $SPACED')"
}

test_profile_can_be_sourced_twice() {
  skip_unless_command zsh
  install_profile_into_home

  zsh_profile 'source ~/.zshrc' || fail ".zshrc is not safe to re-source"
}

test_sz_alias_reloads_the_installed_profile() {
  skip_unless_command zsh
  install_profile_into_home

  # `sz` has to point at a file this repo actually installs.
  assert_eq "sz='source ~/.zshrc'" "$(zsh_profile 'alias sz')"
}

run_tests "$@"
