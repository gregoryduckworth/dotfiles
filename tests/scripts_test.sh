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

## ---------- scripts/nvm ---------- ##

test_nvm_is_loaded_when_installed() {
  skip_unless_command zsh
  mkdir -p "$HOME/.nvm"
  echo 'export NVM_LOADED=yes' >"$HOME/.nvm/nvm.sh"
  echo 'export NVM_COMPLETION_LOADED=yes' >"$HOME/.nvm/bash_completion"

  assert_eq "yes" "$(zsh_script nvm 'echo $NVM_LOADED')"
  assert_eq "yes" "$(zsh_script nvm 'echo $NVM_COMPLETION_LOADED')"
}

test_nvm_is_loaded_from_the_homebrew_prefix() {
  skip_unless_command zsh
  # `brew install nvm` keeps nvm.sh under its own prefix, with the completion
  # under etc/, and leaves $NVM_DIR to hold the runtimes only.
  local prefix="$TEST_TMP/homebrew"
  mkdir -p "$prefix/opt/nvm/etc/bash_completion.d"
  echo 'export NVM_LOADED=brew' >"$prefix/opt/nvm/nvm.sh"
  echo 'export NVM_COMPLETION_LOADED=brew' \
    >"$prefix/opt/nvm/etc/bash_completion.d/nvm"

  assert_eq "brew" \
    "$(HOMEBREW_PREFIX="$prefix" zsh_script nvm 'echo $NVM_LOADED')"
  assert_eq "brew" \
    "$(HOMEBREW_PREFIX="$prefix" zsh_script nvm 'echo $NVM_COMPLETION_LOADED')"
  # $NVM_DIR still points at where nvm keeps the runtimes it installs.
  assert_eq "$HOME/.nvm" \
    "$(HOMEBREW_PREFIX="$prefix" zsh_script nvm 'echo $NVM_DIR')"
}

test_nvm_prefers_the_copy_in_nvm_dir() {
  skip_unless_command zsh
  # Both flavours installed: the one in $NVM_DIR is the one nvm's own installer
  # put there, so it wins.
  local prefix="$TEST_TMP/homebrew"
  mkdir -p "$HOME/.nvm" "$prefix/opt/nvm"
  echo 'export NVM_LOADED=nvm_dir' >"$HOME/.nvm/nvm.sh"
  echo 'export NVM_LOADED=brew' >"$prefix/opt/nvm/nvm.sh"

  assert_eq "nvm_dir" \
    "$(HOMEBREW_PREFIX="$prefix" zsh_script nvm 'echo $NVM_LOADED')"
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
  mkdir -p "$HOME/.rbenv/bin"

  assert_contains "$(zsh_script rbenv 'echo $PATH')" "$HOME/.rbenv/bin"
}

test_rbenv_shims_are_not_added_twice() {
  skip_unless_command zsh
  mkdir -p "$HOME/.rbenv/bin"
  local path
  # .zshrc is re-sourced by hand (`sz`) all the time; each re-source used to
  # push another copy of the shims onto $PATH.
  stub rbenv 'exit 0'
  path="$(zsh_script rbenv "source '$REPO_ROOT/scripts/rbenv'; echo \$PATH")"

  assert_eq "1" "$(printf '%s\n' "${path//:/$'\n'}" | grep -c "^$HOME/.rbenv/bin$")"
}

test_rbenv_shims_are_left_off_the_path_when_missing() {
  skip_unless_command zsh
  # A real rbenv on the host would prepend its own shims, so stub it out: the
  # only thing under test is that a missing ~/.rbenv leaves $PATH alone rather
  # than adding a directory that does not exist.
  stub rbenv 'exit 0'

  assert_not_contains "$(zsh_script rbenv 'echo $PATH')" "$HOME/.rbenv"
}

test_rbenv_is_skipped_when_not_installed() {
  skip_unless_command zsh
  local errors
  # A PATH with no rbenv on it, so the `command -v rbenv` guard has to hold.
  # Without it the eval still succeeds, so the tell is the noise on stderr.
  errors="$(PATH="/usr/bin:/bin" zsh_script rbenv 2>&1 >/dev/null)" ||
    fail "scripts/rbenv failed without rbenv installed"
  assert_eq "" "$errors" "scripts/rbenv complained about the missing rbenv"
}

## ---------- scripts/pyenv ---------- ##

test_pyenv_is_initialised_when_installed() {
  skip_unless_command zsh
  stub pyenv 'echo "export PYENV_LOADED=yes"'

  assert_eq "yes" "$(zsh_script pyenv 'echo $PYENV_LOADED')"
}

test_pyenv_init_skips_the_startup_rehash() {
  skip_unless_command zsh
  # A rehash on startup is slow, and fails before any version is installed,
  # which would abort a profile sourced under errexit.
  stub pyenv 'exit 0'
  zsh_script pyenv || fail "scripts/pyenv left a non-zero exit status behind"

  assert_stub_called pyenv "init --no-rehash - zsh"
}

test_pyenv_shims_are_added_to_the_path() {
  skip_unless_command zsh
  mkdir -p "$HOME/.pyenv/bin"
  stub pyenv 'exit 0'

  assert_contains "$(zsh_script pyenv 'echo $PATH')" "$HOME/.pyenv/bin"
}

test_pyenv_shims_are_not_added_twice() {
  skip_unless_command zsh
  mkdir -p "$HOME/.pyenv/bin"
  stub pyenv 'exit 0'
  local path
  # As with rbenv: every `sz` used to push another copy onto $PATH.
  path="$(zsh_script pyenv "source '$REPO_ROOT/scripts/pyenv'; echo \$PATH")"

  assert_eq "1" "$(printf '%s\n' "${path//:/$'\n'}" | grep -c "^$HOME/.pyenv/bin$")"
}

test_pyenv_shims_are_left_off_the_path_when_missing() {
  skip_unless_command zsh
  # A Homebrew pyenv has no ~/.pyenv/bin; adding it anyway put a directory
  # that does not exist on every $PATH.
  stub pyenv 'exit 0'

  assert_not_contains "$(zsh_script pyenv 'echo $PATH')" "$HOME/.pyenv/bin"
}

test_pyenv_is_skipped_when_not_installed() {
  skip_unless_command zsh
  local errors
  # A PATH with no pyenv on it, so the `command -v pyenv` guard has to hold.
  errors="$(PATH="/usr/bin:/bin" zsh_script pyenv 2>&1 >/dev/null)" ||
    fail "scripts/pyenv failed without pyenv installed"
  assert_eq "" "$errors" "scripts/pyenv complained about the missing pyenv"
}

## ---------- scripts/homebrew ---------- ##

test_homebrew_curl_is_left_off_the_path_when_missing() {
  skip_unless_command zsh
  local prefix="$TEST_TMP/brew-without-curl"
  mkdir -p "$prefix"

  # Nothing to prepend: $PATH must not gain a directory that does not exist.
  assert_not_contains \
    "$(HOMEBREW_PREFIX="$prefix" zsh_script homebrew 'echo $PATH')" "$prefix"
}

test_homebrew_curl_comes_from_homebrew_prefix_first() {
  skip_unless_command zsh
  local prefix="$TEST_TMP/brew" path
  mkdir -p "$prefix/opt/curl/bin"
  path="$(HOMEBREW_PREFIX="$prefix" zsh_script homebrew 'echo $PATH')"

  assert_eq "$prefix/opt/curl/bin" "${path%%:*}"
}

test_homebrew_curl_is_not_added_twice() {
  skip_unless_command zsh
  local prefix="$TEST_TMP/brew" path
  mkdir -p "$prefix/opt/curl/bin"
  # Re-sourcing the profile (`sz`) used to push another copy onto $PATH.
  path="$(HOMEBREW_PREFIX="$prefix" zsh_script homebrew \
    "source '$REPO_ROOT/scripts/homebrew'; echo \$PATH")"

  assert_eq "1" "$(printf '%s\n' "${path//:/$'\n'}" | grep -cFx "$prefix/opt/curl/bin")"
}

test_homebrew_leaves_no_loop_variable_behind() {
  skip_unless_command zsh
  assert_eq "unset" \
    "$(zsh_script homebrew '[[ -z ${curl_bin+set} ]] && echo unset')"
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

## ---------- scripts/history ---------- ##

test_history_is_saved_to_a_file() {
  skip_unless_command zsh
  # zsh writes no history at all until HISTFILE is set, so this is the setting
  # the rest of the file depends on.
  assert_eq "$HOME/.zsh_history" "$(zsh_script history 'echo $HISTFILE')"
  assert_eq "50000" "$(zsh_script history 'echo $HISTSIZE')"
  # SAVEHIST smaller than HISTSIZE silently drops the oldest entries on exit.
  assert_eq "50000" "$(zsh_script history 'echo $SAVEHIST')"
}

test_history_options_are_set() {
  skip_unless_command zsh
  local option
  for option in sharehistory histignorealldups histignorespace histreduceblanks; do
    assert_eq "on" "$(zsh_script history "echo \$options[$option]")" "$option"
  done
}

## ---------- scripts/completion ---------- ##

test_completion_runs_compinit() {
  skip_unless_command zsh
  # compdef only exists once compinit has run, so it is the tell that the
  # completion system is actually initialised rather than merely autoloadable.
  assert_eq "compdef: function" "$(zsh_script completion 'whence -w compdef')"
}

test_completion_loads_the_menu_selection_module() {
  skip_unless_command zsh
  # Without zsh/complist the `menu select` style below has no keymap to drive.
  assert_eq "loaded" \
    "$(zsh_script completion 'zmodload -e zsh/complist && echo loaded')"
}

test_completion_styles_are_set() {
  skip_unless_command zsh
  local styles
  styles="$(zsh_script completion 'zstyle -L ":completion:*"')"

  assert_contains "$styles" "matcher-list 'm:{a-z}={A-Z}'"
  assert_contains "$styles" "menu select"
}

test_completion_matches_case_insensitively_in_one_direction_only() {
  skip_unless_command zsh
  local matcher
  matcher="$(zsh_script completion 'zstyle -L ":completion:*" matcher-list')"

  # 'm:{a-z}={A-Z}' widens lowercase to uppercase. The two-way spelling
  # 'm:{a-zA-Z}={A-Za-z}' would also let a typed capital match a lowercase
  # name, which makes an explicit capital meaningless.
  assert_not_contains "$matcher" "a-zA-Z"
}

test_completion_keeps_its_dump_out_of_home() {
  skip_unless_command zsh
  zsh_script completion || fail "scripts/completion left a non-zero exit status"

  assert_file "$HOME/.cache/zsh/zcompdump-$(zsh -c 'echo $ZSH_VERSION')"
  assert_missing "$HOME/.zcompdump"
}

test_completion_leaves_an_existing_compinit_alone() {
  skip_unless_command zsh
  # A second compinit would rebuild the same dump for nothing, so the file has
  # to notice that oh-my-zsh already ran one - compdef being the tell.
  zsh -c "set -e
    compdef() { : }
    source '$REPO_ROOT/scripts/completion'" ||
    fail "scripts/completion failed with compinit already run"

  assert_missing "$HOME/.cache/zsh/zcompdump-$(zsh -c 'echo $ZSH_VERSION')"
}

test_completion_is_quiet() {
  skip_unless_command zsh
  local errors
  # compinit stops to ask about completion files with the wrong permissions
  # unless it is told to skip them, which would hang a non-interactive shell.
  errors="$(zsh_script completion 2>&1 >/dev/null)" ||
    fail "scripts/completion failed"
  assert_eq "" "$errors" "scripts/completion wrote to stderr"
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

  # git supplies the git aliases (gst, gaa, gl, gp, gbda, ...); nothing in
  # scripts/ defines its own.
  assert_eq "git brew docker gh" "$plugins"
}

test_oh_my_zsh_does_not_prompt_to_update() {
  skip_unless_command zsh
  fake_oh_my_zsh
  # The default mode asks, on the first prompt of a new terminal.
  assert_contains "$(zsh_script oh-my-zsh 'zstyle -L ":omz:update"')" "mode reminder"
}

test_oh_my_zsh_shares_the_completion_dump() {
  skip_unless_command zsh
  fake_oh_my_zsh
  # Left unset, oh-my-zsh drops a second dump in $HOME.
  assert_eq "$HOME/.cache/zsh/zcompdump-$(zsh -c 'echo $ZSH_VERSION')" \
    "$(zsh_script oh-my-zsh 'echo $ZSH_COMPDUMP')"
  assert_missing "$HOME/.zcompdump"
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

## ---------- scripts/navigation ---------- ##

test_navigation_options_are_set() {
  skip_unless_command zsh
  # AUTO_CD itself only fires in an interactive shell, so the option is all
  # there is to assert from here.
  assert_eq "on" "$(zsh_script navigation 'echo $options[autocd]')"
  assert_eq "on" "$(zsh_script navigation 'echo $options[autopushd]')"
  assert_eq "on" "$(zsh_script navigation 'echo $options[pushdignoredups]')"
  assert_eq "20" "$(zsh_script navigation 'echo $DIRSTACKSIZE')"
}

test_cd_pushes_the_old_directory_onto_the_stack() {
  skip_unless_command zsh
  mkdir -p "$TEST_TMP/a" "$TEST_TMP/b"

  assert_eq "yes" "$(zsh_script navigation \
    "cd '$TEST_TMP/a'; previous=\$PWD; cd '$TEST_TMP/b'; [[ \$dirstack[1] == \$previous ]] && echo yes")"
}

test_bouncing_between_two_directories_does_not_fill_the_stack() {
  skip_unless_command zsh
  mkdir -p "$TEST_TMP/a" "$TEST_TMP/b"

  # Five hops between the same two directories, so without PUSHD_IGNORE_DUPS
  # the stack would hold five entries instead of the two distinct ones.
  assert_eq "2" "$(zsh_script navigation \
    "cd '$TEST_TMP/a'; cd '$TEST_TMP/b'; cd '$TEST_TMP/a'; cd '$TEST_TMP/b'; cd '$TEST_TMP/a'; echo \${#dirstack}")"
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
