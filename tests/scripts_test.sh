#!/usr/bin/env bash
# Tests for the individual files in scripts/, each of which is sourced by
# .zshrc on every new shell.
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

## ---------- Every script ---------- ##

test_every_script_parses_as_zsh() {
  skip_unless_command zsh
  local script
  for script in "$REPO_ROOT"/scripts/*; do
    zsh -n "$script" || fail "$script is not valid zsh"
  done
}

test_every_script_exits_cleanly_on_its_own() {
  skip_unless_command zsh
  # A script that leaves a non-zero status behind breaks any caller that
  # sources the profile under errexit.
  local script
  for script in "$REPO_ROOT"/scripts/*; do
    zsh_script "$(basename "$script")" ||
      fail "$script left a non-zero exit status behind"
  done
}

## ---------- scripts/docker ---------- ##

test_docker_aliases_are_well_formed() {
  skip_unless_command zsh
  # A stray character on the end of this alias used to make it run
  # `docker build -q .` and then append a "d" to the image id.
  assert_eq "dr='docker run --rm -it \$(docker build -q .)'" \
    "$(zsh_script docker 'alias dr')"
  assert_eq "drs='docker stop \$(docker ps -a -q)'" "$(zsh_script docker 'alias drs')"
  assert_eq "drd='docker rm \$(docker ps -a -q)'" "$(zsh_script docker 'alias drd')"
  assert_eq "drp='docker system prune'" "$(zsh_script docker 'alias drp')"
}

test_docker_enables_buildkit() {
  skip_unless_command zsh
  assert_eq "1" "$(zsh_script docker 'echo $DOCKER_BUILDKIT')"
  assert_eq "1" "$(zsh_script docker 'echo $COMPOSE_DOCKER_CLI_BUILD')"
}

## ---------- scripts/github ---------- ##

test_github_aliases_wrap_the_expected_commands() {
  skip_unless_command zsh
  assert_eq "ga='git add'" "$(zsh_script github 'alias ga')"
  assert_eq "gcm='git commit -m'" "$(zsh_script github 'alias gcm')"
  assert_eq "gs='git status'" "$(zsh_script github 'alias gs')"
  assert_eq "ghpr='gh pr status'" "$(zsh_script github 'alias ghpr')"
}

test_every_github_alias_targets_git_or_gh() {
  skip_unless_command zsh
  local name definition
  # Take the alias names from the file, then ask zsh what each one expanded to,
  # so a typo in the file shows up as a mismatch here.
  while read -r name; do
    definition="$(zsh_script github "alias $name")"
    case "$definition" in
      "$name='git "* | "$name='gh "*) ;;
      *) fail "github alias $name does not run git or gh: ${definition:-<undefined>}" ;;
    esac
  done < <(sed -n "s/^alias \([a-z]*\)=.*/\1/p" "$REPO_ROOT/scripts/github")
}

## ---------- scripts/git ---------- ##

test_parse_git_branch_reports_the_current_branch() {
  skip_unless_command zsh
  skip_unless_command git
  local repo="$TEST_TMP/repo"
  mkdir -p "$repo"
  git -C "$repo" init --quiet
  git -C "$repo" checkout --quiet -b feature/example
  git -C "$repo" -c user.name=Test -c user.email=test@example.com \
    commit --quiet --allow-empty -m "first"

  assert_eq "[feature/example]" \
    "$(zsh_script git "cd '$repo' && parse_git_branch")"
}

test_parse_git_branch_is_quiet_outside_a_repository() {
  skip_unless_command zsh
  skip_unless_command git
  local plain="$TEST_TMP/plain"
  mkdir -p "$plain"

  assert_eq "" "$(zsh_script git "cd '$plain' && parse_git_branch")"
}

test_prompt_includes_the_branch() {
  skip_unless_command zsh
  assert_contains "$(zsh_script git 'echo $PROMPT')" 'parse_git_branch'
  # Without PROMPT_SUBST the prompt would show the literal command instead.
  assert_eq "on" "$(zsh_script git 'echo $options[promptsubst]')"
}

## ---------- scripts/nvm ---------- ##

test_nvm_is_loaded_when_installed() {
  skip_unless_command zsh
  mkdir -p "$HOME/.nvm"
  echo 'export NVM_LOADED=yes' >"$HOME/.nvm/nvm.sh"
  echo 'export NVM_COMPLETION_LOADED=yes' >"$HOME/.nvm/bash_completion"

  assert_eq "yes" "$(zsh_script nvm 'echo $NVM_LOADED')"
  assert_eq "yes" "$(zsh_script nvm 'echo $NVM_COMPLETION_LOADED')"
}

test_nvm_is_skipped_when_not_installed() {
  skip_unless_command zsh
  assert_eq "$HOME/.nvm" "$(zsh_script nvm 'echo $NVM_DIR')"
  zsh_script nvm || fail "scripts/nvm failed without nvm installed"
}

## ---------- scripts/rbenv ---------- ##

test_rbenv_is_initialised_when_installed() {
  skip_unless_command zsh
  stub rbenv 'echo "export RBENV_LOADED=yes"'

  assert_eq "yes" "$(zsh_script rbenv 'echo $RBENV_LOADED')"
}

test_rbenv_shims_are_added_to_the_path() {
  skip_unless_command zsh
  assert_contains "$(zsh_script rbenv 'echo $PATH')" "$HOME/.rbenv/bin"
}

test_rbenv_is_skipped_when_not_installed() {
  skip_unless_command zsh
  local errors
  # A PATH with no rbenv on it, so the `which rbenv` guard has to hold. Without
  # it the eval still succeeds, so the tell is the noise on stderr.
  errors="$(PATH="/usr/bin:/bin" zsh_script rbenv 2>&1 >/dev/null)" ||
    fail "scripts/rbenv failed without rbenv installed"
  assert_eq "" "$errors" "scripts/rbenv complained about the missing rbenv"
}

## ---------- scripts/homebrew ---------- ##

test_homebrew_curl_is_prepended_when_present() {
  skip_unless_command zsh
  local path
  path="$(zsh_script homebrew 'echo $PATH')"

  if [[ -d /opt/homebrew/opt/curl/bin ]]; then
    assert_eq "/opt/homebrew/opt/curl/bin" "${path%%:*}"
  elif [[ -d /usr/local/opt/curl/bin ]]; then
    assert_eq "/usr/local/opt/curl/bin" "${path%%:*}"
  else
    # Nothing to prepend: the script must leave $PATH alone rather than adding
    # a directory that does not exist.
    assert_not_contains "$path" "opt/curl/bin"
  fi
}

## ---------- scripts/browserstack ---------- ##

test_browserstack_keeps_credentials_from_the_environment() {
  skip_unless_command zsh
  # The file used to export empty strings unconditionally, so every new shell
  # wiped out credentials the environment already carried.
  export BROWSERSTACK_USERNAME=someone BROWSERSTACK_ACCESS_KEY=s3cret

  assert_eq "someone" "$(zsh_script browserstack 'echo $BROWSERSTACK_USERNAME')"
  assert_eq "s3cret" "$(zsh_script browserstack 'echo $BROWSERSTACK_ACCESS_KEY')"
}

test_browserstack_leaves_unset_credentials_unset() {
  skip_unless_command zsh
  # Whatever the machine running the suite happens to export.
  unset BROWSERSTACK_USERNAME BROWSERSTACK_ACCESS_KEY
  # Unset, not set-but-empty: anything checking `${VAR:?}` or falling back to a
  # config file has to be able to tell the difference.
  assert_eq "yes" "$(zsh_script browserstack '[[ -z ${BROWSERSTACK_USERNAME+set} ]] && echo yes')"
  assert_eq "yes" "$(zsh_script browserstack '[[ -z ${BROWSERSTACK_ACCESS_KEY+set} ]] && echo yes')"
}

test_browserstack_exports_a_credential_set_as_a_plain_variable() {
  skip_unless_command zsh
  unset BROWSERSTACK_USERNAME BROWSERSTACK_ACCESS_KEY
  # Exported, so tools launched from the shell can pick the values up.
  local name
  for name in BROWSERSTACK_USERNAME BROWSERSTACK_ACCESS_KEY; do
    assert_eq "scalar-export" "$(zsh -c "
      set -e
      $name=value
      source '$REPO_ROOT/scripts/browserstack'
      echo \${(t)$name}")" "$name"
  done
}

test_browserstack_holds_no_credentials_of_its_own() {
  # A real key in this tracked file is one `gaa` away from being published.
  local assignments
  assignments="$(grep -nE "^[[:space:]]*(export[[:space:]]+)?BROWSERSTACK_[A-Z_]+=" \
    "$REPO_ROOT/scripts/browserstack" || true)"
  assert_eq "" "$assignments" "scripts/browserstack assigns a credential"
}

test_browserstack_exports_chrome() {
  skip_unless_command zsh
  # No stray backslash: the path has to survive being used as "$CHROME".
  assert_eq "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "$(zsh_script browserstack 'echo $CHROME')"
}

run_tests "$@"
