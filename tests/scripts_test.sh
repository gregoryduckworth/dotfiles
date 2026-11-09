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

## ---------- scripts/oh-my-zsh ---------- ##

# The same stand-in as tests/profile_test.sh: a file where scripts/oh-my-zsh
# expects one.
fake_oh_my_zsh() {
  mkdir -p "$HOME/.oh-my-zsh"
  cat >"$HOME/.oh-my-zsh/oh-my-zsh.sh" <<'EOF'
OMZ_LOADED=yes
EOF
}

test_oh_my_zsh_sources_the_installed_framework() {
  skip_unless_command zsh
  fake_oh_my_zsh

  assert_eq "yes" "$(zsh_script oh-my-zsh 'echo $OMZ_LOADED')"
  assert_eq "$HOME/.oh-my-zsh" "$(zsh_script oh-my-zsh 'echo $ZSH')"
}

test_oh_my_zsh_honours_an_existing_zsh_directory() {
  skip_unless_command zsh
  # $ZSH is oh-my-zsh's own name for its install directory.
  mkdir -p "$TEST_TMP/elsewhere"
  echo 'OMZ_LOADED=yes' >"$TEST_TMP/elsewhere/oh-my-zsh.sh"

  assert_eq "yes" \
    "$(ZSH="$TEST_TMP/elsewhere" zsh_script oh-my-zsh 'echo $OMZ_LOADED')"
}

test_oh_my_zsh_draws_the_prompt_with_its_default_theme() {
  skip_unless_command zsh
  fake_oh_my_zsh
  # Nothing in scripts/ sets $PROMPT, so the theme is what draws it.
  assert_eq "robbyrussell" "$(zsh_script oh-my-zsh 'echo $ZSH_THEME')"
}

test_no_script_overrides_the_oh_my_zsh_prompt() {
  # A $PROMPT set in scripts/ is sourced after oh-my-zsh and would silently
  # replace the theme's.
  local hits
  hits="$(grep -lE '^[[:space:]]*(export[[:space:]]+)?(PROMPT|PS1|RPROMPT)=' \
    "$REPO_ROOT"/scripts/* || true)"
  assert_eq "" "$hits" "scripts that set the prompt"
}

test_oh_my_zsh_enables_the_expected_plugins() {
  skip_unless_command zsh
  fake_oh_my_zsh
  local plugins
  plugins="$(zsh_script oh-my-zsh 'echo $plugins')"

  # git and docker supply the aliases, nvm/pyenv/rbenv load the version
  # managers; nothing in scripts/ does either any more.
  assert_eq "git brew docker gh nvm pyenv rbenv" "$plugins"
}

test_oh_my_zsh_lazy_loads_nvm() {
  skip_unless_command zsh
  fake_oh_my_zsh
  # Loading nvm is most of a new shell's startup time.
  assert_eq "yes" \
    "$(zsh_script oh-my-zsh 'zstyle -t ":omz:plugins:nvm" lazy && echo yes')"
}

test_oh_my_zsh_silences_the_pyenv_shims_warning() {
  skip_unless_command zsh
  mkdir -p "$HOME/.oh-my-zsh"
  # A pyenv on $PATH with its shims not, as with the Homebrew formula and no
  # ~/.zprofile, and the check the omz pyenv plugin makes before warning.
  stub pyenv 'exit 0'
  # shellcheck disable=SC2016  # expanded by zsh, not here
  echo '(( $+commands[pyenv] )) && [[ "$ZSH_PYENV_QUIET" != true ]] &&
    echo "Found pyenv, but it is badly configured" >&2
    true' >"$HOME/.oh-my-zsh/oh-my-zsh.sh"
  local errors
  errors="$(zsh_script oh-my-zsh 2>&1 >/dev/null)" || fail "scripts/oh-my-zsh failed"

  assert_eq "" "$errors" "a new shell warned about pyenv"
}

test_oh_my_zsh_does_not_prompt_to_update() {
  skip_unless_command zsh
  fake_oh_my_zsh
  # The default mode asks, on the first prompt of a new terminal.
  assert_contains "$(zsh_script oh-my-zsh 'zstyle -L ":omz:update"')" "mode reminder"
}

test_oh_my_zsh_keeps_the_completion_dump_out_of_home() {
  skip_unless_command zsh
  fake_oh_my_zsh
  # Left unset, oh-my-zsh drops its dump in $HOME.
  assert_eq "$HOME/.cache/zsh/zcompdump-$(zsh -c 'echo $ZSH_VERSION')" \
    "$(zsh_script oh-my-zsh 'echo $ZSH_COMPDUMP')"
  assert_missing "$HOME/.zcompdump"
}

test_oh_my_zsh_puts_homebrew_completions_on_fpath_before_compinit() {
  skip_unless_command zsh
  local prefix="$TEST_TMP/brew"
  mkdir -p "$prefix/share/zsh/site-functions" "$HOME/.oh-my-zsh"
  # Record $fpath at the moment oh-my-zsh starts, which is when its compinit
  # runs: the brew plugin adding the directory later is too late.
  # shellcheck disable=SC2016  # expanded by zsh, not here
  echo 'print -r -- "$fpath[1]" >"$HOME/fpath-at-load"' >"$HOME/.oh-my-zsh/oh-my-zsh.sh"
  HOMEBREW_PREFIX="$prefix" zsh_script oh-my-zsh

  assert_eq "$prefix/share/zsh/site-functions" "$(cat "$HOME/fpath-at-load")"
}

test_oh_my_zsh_leaves_no_loop_variable_behind() {
  skip_unless_command zsh
  fake_oh_my_zsh
  assert_eq "unset" \
    "$(zsh_script oh-my-zsh '[[ -z ${brew_prefix+set} ]] && echo unset')"
}

test_oh_my_zsh_is_a_no_op_when_not_installed() {
  skip_unless_command zsh
  assert_missing "$HOME/.oh-my-zsh"
  local errors

  # No oh-my-zsh means a plain shell, not an error on every prompt.
  errors="$(zsh_script oh-my-zsh 2>&1 >/dev/null)" ||
    fail "scripts/oh-my-zsh failed without oh-my-zsh installed"
  assert_eq "" "$errors" "scripts/oh-my-zsh complained about the missing install"
}

test_oh_my_zsh_survives_a_framework_that_exits_non_zero() {
  skip_unless_command zsh
  mkdir -p "$HOME/.oh-my-zsh"
  # oh-my-zsh.sh ends on its last plugin, and the stock brew plugin returns
  # non-zero with no Homebrew about. The profile is sourced under errexit.
  echo 'false' >"$HOME/.oh-my-zsh/oh-my-zsh.sh"

  zsh_script oh-my-zsh || fail "scripts/oh-my-zsh propagated oh-my-zsh's status"
}

## ---------- scripts/editor ---------- ##

# A $PATH holding nothing but zsh, so the editor probing below sees exactly the
# editors a test puts in front of it rather than whatever the machine has.
path_without_editors() {
  mkdir -p "$TEST_TMP/onlyzsh"
  ln -sf "$(command -v zsh)" "$TEST_TMP/onlyzsh/zsh"
  echo "$TEST_TMP/onlyzsh"
}

test_editor_prefers_the_first_installed_candidate() {
  skip_unless_command zsh
  local bare
  bare="$(path_without_editors)"
  ln -sf /bin/echo "$bare/vim"

  assert_eq "vim" "$(PATH="$bare" zsh_script editor 'echo $EDITOR')"

  # nvim outranks vim, so adding it has to change the answer.
  ln -sf /bin/echo "$bare/nvim"
  assert_eq "nvim" "$(PATH="$bare" zsh_script editor 'echo $EDITOR')"
}

test_editor_falls_back_to_vi() {
  skip_unless_command zsh
  # Every macOS and Linux box has vi, so an unresolvable $EDITOR is worse than
  # guessing it.
  assert_eq "vi" "$(PATH="$(path_without_editors)" zsh_script editor 'echo $EDITOR')"
}

test_editor_keeps_an_editor_already_in_the_environment() {
  skip_unless_command zsh
  # A deliberate choice from the terminal or an earlier script must survive.
  assert_eq "code -w" "$(EDITOR='code -w' zsh_script editor 'echo $EDITOR')"
  assert_eq "code -w" "$(EDITOR='code -w' zsh_script editor 'echo $VISUAL')"
}

test_editor_and_visual_agree_and_are_exported() {
  skip_unless_command zsh
  assert_eq "same" "$(zsh_script editor '[[ $EDITOR == $VISUAL ]] && echo same')"
  # Exported, or the tools that shell out to an editor never see them.
  assert_eq "yes" "$(zsh_script editor '[[ ${(t)EDITOR} == *export* ]] && echo yes')"
  assert_eq "yes" "$(zsh_script editor '[[ ${(t)VISUAL} == *export* ]] && echo yes')"
}

test_editor_leaves_no_loop_variable_behind() {
  skip_unless_command zsh
  assert_eq "unset" \
    "$(zsh_script editor '[[ -z ${candidate+set} ]] && echo unset')"
}

## ---------- scripts/zsh-plugins ---------- ##

# Writes stand-in plugin files under a fake Homebrew prefix and echoes the
# prefix. Each one records that it was sourced, in order, so the tests can
# assert on both the fact and the ordering without installing the real thing.
fake_brew_plugins() {
  local prefix="$TEST_TMP/brew" name
  for name in zsh-autosuggestions zsh-syntax-highlighting; do
    mkdir -p "$prefix/share/$name"
    echo "print -r -- $name >>'$TEST_TMP/sourced'" >"$prefix/share/$name/$name.zsh"
  done
  echo "$prefix"
}

test_plugins_are_sourced_from_the_homebrew_prefix() {
  skip_unless_command zsh
  local prefix sourced
  prefix="$(fake_brew_plugins)"

  HOMEBREW_PREFIX="$prefix" zsh_script zsh-plugins ||
    fail "scripts/zsh-plugins failed with the plugins installed"

  sourced="$(sort "$TEST_TMP/sourced")"
  assert_contains "$sourced" "zsh-autosuggestions"
  assert_contains "$sourced" "zsh-syntax-highlighting"
}

test_syntax_highlighting_is_sourced_after_autosuggestions() {
  skip_unless_command zsh
  local prefix
  prefix="$(fake_brew_plugins)"

  # zsh-syntax-highlighting's install notes require it to come last, so that
  # the widgets it wraps include the ones autosuggestions defines.
  HOMEBREW_PREFIX="$prefix" zsh_script zsh-plugins
  assert_eq "zsh-syntax-highlighting" "$(tail -n 1 "$TEST_TMP/sourced")"
}

test_plugins_are_skipped_when_not_installed() {
  skip_unless_command zsh
  local errors
  # An empty prefix, so neither plugin is there to source. A shell on a machine
  # that has not run install.sh still has to start.
  mkdir -p "$TEST_TMP/empty/share"
  errors="$(HOMEBREW_PREFIX="$TEST_TMP/empty" zsh_script zsh-plugins 2>&1 >/dev/null)" ||
    fail "scripts/zsh-plugins failed without the plugins installed"
  assert_eq "" "$errors" "scripts/zsh-plugins complained about the missing plugins"
}

test_plugins_leave_no_helper_variable_behind() {
  skip_unless_command zsh
  assert_eq "unset" \
    "$(zsh_script zsh-plugins '[[ -z ${zsh_plugin_dir+set} ]] && echo unset')"
}

run_tests "$@"
