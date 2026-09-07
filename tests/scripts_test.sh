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
  # Branch cleanup needs branching logic, so it is a function rather than an
  # alias; the tests below exercise what it does.
  assert_eq "gbc: function" "$(zsh_script github 'whence -w gbc')"
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

test_gbc_replaces_a_stale_gbc_alias() {
  skip_unless_command zsh
  # gbc used to be an alias, and zsh refuses to define a function over one, so
  # re-sourcing this file in a shell left over from before the change has to
  # clear the alias rather than die with a parse error.
  assert_eq "gbc: function" "$(zsh -c "set -e
    alias gbc='git branch -d \$(git branch --merged=master)'
    source '$REPO_ROOT/scripts/github'
    whence -w gbc" 2>&1)"
}

# Builds a repository whose default branch is main, with an origin to prune
# against, and prints its path. The branches cover the ways branch cleanup can
# go wrong:
#
#   main               the default branch, and the one to measure against
#   master             a stale decoy, left behind the default branch on purpose
#                      so that "merged into main" and "merged into master" are
#                      different sets of branches
#   feat-master-thing  merged, and only into master; its name contains the name
#                      of a long-lived branch
#   feat-main-thing    merged into main only; its name likewise
#   other              merged into main only
#   unmerged           has a commit of its own, so it is not merged anywhere
gbc_repo() {
  local origin="$TEST_TMP/origin" work="$TEST_TMP/work"

  git init --quiet --bare "$origin"
  git init --quiet "$work"
  git -C "$work" symbolic-ref HEAD refs/heads/main
  git_commit "$work" "first"
  git -C "$work" remote add origin "$origin"
  git -C "$work" push --quiet -u origin main
  git -C "$work" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

  git -C "$work" branch master
  git -C "$work" branch feat-master-thing
  git_commit "$work" "second"
  git -C "$work" branch feat-main-thing
  git -C "$work" branch other
  git -C "$work" checkout --quiet -b unmerged
  git_commit "$work" "third"
  git -C "$work" checkout --quiet main

  printf '%s\n' "$work"
}

git_commit() {
  git -C "$1" -c user.name=Test -c user.email=test@example.com \
    commit --quiet --allow-empty -m "$2"
}

# The branches left behind, as a single space-separated line.
gbc_branches() {
  git -C "$1" branch --format='%(refname:short)' | paste -sd' ' -
}

test_gbc_deletes_the_branches_merged_into_the_default_branch() {
  skip_unless_command zsh
  skip_unless_command git
  local repo
  repo="$(gbc_repo)"

  zsh_script github "cd '$repo' && gbc" >/dev/null 2>&1 ||
    fail "gbc failed: $(zsh_script github "cd '$repo' && gbc" 2>&1)"

  # Everything merged into main goes, whatever its name; the default branch,
  # the stale "master" and the unmerged branch stay.
  assert_eq "main master unmerged" "$(gbc_branches "$repo")"
}

test_gbc_uses_the_default_branch_rather_than_master() {
  skip_unless_command zsh
  skip_unless_command git
  local repo
  repo="$(gbc_repo)"
  # "other" is merged into main but not into master, so it is only ever cleaned
  # up by working out what the default branch is instead of assuming "master".
  assert_not_contains \
    " $(git -C "$repo" branch --merged master --format='%(refname:short)' | paste -sd' ' -) " \
    " other " "the fixture no longer distinguishes main from master"

  zsh_script github "cd '$repo' && gbc" >/dev/null 2>&1 || fail "gbc failed"

  assert_not_contains " $(gbc_branches "$repo") " " other "
}

test_gbc_deletes_the_branches_before_it_prunes() {
  skip_unless_command zsh
  skip_unless_command git
  local repo real_git calls delete_line prune_line
  real_git="$(command -v git)"
  repo="$(gbc_repo)"
  # A git that records its arguments and then does the real work, so the order
  # of the calls can be asserted: backgrounding the delete with a single "&"
  # raced it against the fetch instead of sequencing the two.
  stub git "exec '$real_git' \"\$@\""

  zsh_script github "cd '$repo' && gbc" >/dev/null 2>&1 || fail "gbc failed"

  calls="$(stub_calls git)"
  delete_line="$(printf '%s\n' "$calls" | grep -n '^branch -d ' | tail -1 | cut -d: -f1)" || true
  prune_line="$(printf '%s\n' "$calls" | grep -n '^fetch --prune$' | head -1 | cut -d: -f1)" || true

  [[ -n "$delete_line" ]] || fail "gbc deleted no branch; calls were: [$calls]"
  [[ -n "$prune_line" ]] || fail "gbc never pruned; calls were: [$calls]"
  [[ "$prune_line" -gt "$delete_line" ]] ||
    fail "gbc pruned before it finished deleting; calls were: [$calls]"
}

test_gbc_falls_back_to_a_local_default_branch() {
  skip_unless_command zsh
  skip_unless_command git
  local repo="$TEST_TMP/solo"
  # No remote, so there is no origin/HEAD to read the default branch from and
  # nothing to prune.
  git init --quiet "$repo"
  git -C "$repo" symbolic-ref HEAD refs/heads/main
  git_commit "$repo" "first"
  git -C "$repo" branch spike

  zsh_script github "cd '$repo' && gbc" >/dev/null 2>&1 ||
    fail "gbc failed without a remote"

  assert_eq "main" "$(gbc_branches "$repo")"
}

test_gbc_gives_up_outside_a_repository() {
  skip_unless_command zsh
  skip_unless_command git
  local plain="$TEST_TMP/plain" errors
  mkdir -p "$plain"

  assert_failure zsh_script github "cd '$plain' && gbc"
  # And says why, rather than dying silently on the first failing git call.
  errors="$(zsh_script github "cd '$plain' && gbc" 2>&1 >/dev/null)" || true
  assert_contains "$errors" "gbc: cannot work out which branch to compare against"
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
  assert_contains "$(zsh_script pyenv 'echo $PATH')" "$HOME/.pyenv/bin"
}

test_pyenv_is_skipped_when_not_installed() {
  skip_unless_command zsh
  local errors
  # A PATH with no pyenv on it, so the `which pyenv` guard has to hold.
  errors="$(PATH="/usr/bin:/bin" zsh_script pyenv 2>&1 >/dev/null)" ||
    fail "scripts/pyenv failed without pyenv installed"
  assert_eq "" "$errors" "scripts/pyenv complained about the missing pyenv"
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

test_completion_is_quiet() {
  skip_unless_command zsh
  local errors
  # compinit stops to ask about completion files with the wrong permissions
  # unless it is told to skip them, which would hang a non-interactive shell.
  errors="$(zsh_script completion 2>&1 >/dev/null)" ||
    fail "scripts/completion failed"
  assert_eq "" "$errors" "scripts/completion wrote to stderr"
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
