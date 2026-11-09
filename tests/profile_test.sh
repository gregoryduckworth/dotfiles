#!/usr/bin/env bash
# Tests for .zshrc, the profile install.sh links into $HOME.
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
  assert_contains "$(zsh_profile 'echo $CHROME')" "Google" "scripts/browserstack"
  assert_eq "0" "$(zsh_profile '[[ -n $EDITOR ]]; echo $?')" "scripts/editor"
  assert_contains "$(zsh_profile 'echo $ZSH')" ".oh-my-zsh" "scripts/oh-my-zsh"
  mkdir -p "$HOME/.local/bin"
  assert_contains "$(zsh_profile 'echo $PATH')" "$HOME/.local/bin" "scripts/path"
}

# The order ~/scripts is sourced in, one filename per line. .zshrc uses a plain
# glob, so this is the same order a new shell gets.
sourced_order() {
  zsh -c 'for file in ~/scripts/*(N); do echo ${file:t}; done'
}

test_the_plugins_are_sourced_last() {
  skip_unless_command zsh
  install_profile_into_home

  # zsh-syntax-highlighting has to be sourced after everything that defines a
  # ZLE widget, so its file has to sort to the end of ~/scripts.
  assert_eq "zsh-plugins" "$(sourced_order | tail -n 1)"
}

test_profile_is_quiet() {
  skip_unless_command zsh
  install_profile_into_home
  local errors

  # A new terminal that opens with a warning on it is the thing everybody
  # learns to ignore.
  errors="$(zsh_profile 2>&1 >/dev/null)" || fail ".zshrc failed"
  assert_eq "" "$errors" ".zshrc wrote to stderr"
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

## ---------- oh-my-zsh ---------- ##

# A stand-in for ~/.oh-my-zsh: enough to find and source, recording each load
# and defining an alias for the profile to override.
fake_oh_my_zsh() {
  mkdir -p "$HOME/.oh-my-zsh"
  cat >"$HOME/.oh-my-zsh/oh-my-zsh.sh" <<'EOF'
print -r -- loaded >>"$HOME/omz-loads"
alias demo='oh-my-zsh'
alias omz-only='oh-my-zsh'
EOF
}

test_profile_loads_oh_my_zsh() {
  skip_unless_command zsh
  install_profile_into_home
  fake_oh_my_zsh

  assert_eq "0" "$(zsh_profile 'alias omz-only >/dev/null; echo $?')"
}

test_scripts_override_oh_my_zsh() {
  skip_unless_command zsh
  install_profile_into_home
  fake_oh_my_zsh

  # Why .zshrc sources oh-my-zsh first: anything in ~/scripts has to win over
  # an oh-my-zsh alias of the same name.
  echo "alias demo='mine'" >"$HOME/scripts/demo"

  assert_eq "demo=mine" "$(zsh_profile 'alias demo')"
}

test_profile_loads_oh_my_zsh_exactly_once() {
  skip_unless_command zsh
  install_profile_into_home
  fake_oh_my_zsh
  # .zshrc sources it by name and then loops over the same directory, so the
  # loop has to skip it.
  zsh_profile || fail ".zshrc failed with oh-my-zsh installed"

  assert_eq "1" "$(wc -l <"$HOME/omz-loads" | tr -d '[:blank:]')"
}

test_profile_is_quiet_with_oh_my_zsh_installed() {
  skip_unless_command zsh
  install_profile_into_home
  fake_oh_my_zsh
  local errors

  errors="$(zsh_profile 2>&1 >/dev/null)" || fail ".zshrc failed"
  assert_eq "" "$errors" ".zshrc wrote to stderr with oh-my-zsh installed"
}

## ---------- ~/.zprofile ---------- ##

test_zprofile_parses_as_zsh() {
  skip_unless_command zsh
  zsh -n "$REPO_ROOT/.zprofile" || fail ".zprofile is not valid zsh"
}

test_zprofile_puts_homebrew_on_the_path_of_a_login_shell() {
  skip_unless_command zsh
  local brew_bin
  for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [[ -x "$brew_bin" ]] && break
    brew_bin=""
  done
  if [[ -z "$brew_bin" ]]; then
    echo "skipped: Homebrew is not installed" >&2
    exit 100
  fi

  # A login shell that never reaches .zshrc, with no Homebrew on $PATH yet.
  assert_eq "$brew_bin" \
    "$(PATH=/usr/bin:/bin zsh -c "source '$REPO_ROOT/.zprofile'; whence -p brew")"
}

test_zprofile_leaves_no_loop_variable_behind() {
  skip_unless_command zsh
  assert_eq "unset" \
    "$(zsh -c "source '$REPO_ROOT/.zprofile'; [[ -z \${brew_bin+set} ]] && echo unset")"
}

## ---------- ~/.zshrc.local ---------- ##

test_profile_sources_the_local_override_last() {
  skip_unless_command zsh
  install_profile_into_home
  # Machine-specific settings and secrets have to win over the tracked scripts,
  # which is the whole point of keeping them out of the repo.
  echo 'export CHROME=/custom/chrome' >"$HOME/.zshrc.local"

  assert_eq "/custom/chrome" "$(zsh_profile 'echo $CHROME')"
}

test_profile_survives_a_missing_local_override() {
  skip_unless_command zsh
  install_profile_into_home
  assert_missing "$HOME/.zshrc.local"

  # The override is optional, and a missing one must not leave a non-zero
  # status behind for a caller running under errexit.
  zsh_profile || fail ".zshrc failed with no ~/.zshrc.local"
}

test_local_override_is_not_tracked_by_the_repo() {
  skip_unless_command git
  # A credential in a tracked file is one `gaa` (`git add --all`) away from being
  # published, so git has to ignore the override outright.
  git -C "$REPO_ROOT" check-ignore -q .zshrc.local ||
    fail ".zshrc.local is not gitignored"
}

test_sz_alias_reloads_the_installed_profile() {
  skip_unless_command zsh
  install_profile_into_home

  # `sz` has to point at a file this repo actually installs.
  assert_eq "sz='source ~/.zshrc'" "$(zsh_profile 'alias sz')"
}

run_tests "$@"
