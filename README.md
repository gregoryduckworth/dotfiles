# dotfiles

[![CI](https://github.com/gregoryduckworth/dotfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/gregoryduckworth/dotfiles/actions/workflows/ci.yml)

Install script for useful items

## Usage

```sh
./install.sh             # bootstrap a machine
./install.sh --dry-run   # print what it would do, and do none of it
./install.sh --help      # usage
```

`install.sh` resolves paths against the checkout, so it can be run from
anywhere, and it is safe to re-run.

It installs [oh-my-zsh](https://github.com/ohmyzsh/ohmyzsh) into
`~/.oh-my-zsh` - a plain `git clone`, because the other half of oh-my-zsh's own
installer is writing a `.zshrc` and running `chsh`, and this repo owns the
first and does not ask for the second. A clone is all `omz update` needs, and
a machine that already has one is left alone.

It does not copy anything into `$HOME`; it symlinks:

```
~/.zshrc  -> <checkout>/.zshrc
~/scripts -> <checkout>/scripts
```

So updating is just a `git pull` in the checkout - there is no second copy to
re-install or to go stale, and editing a script in `~/scripts` is the same thing
as editing it in the checkout.

If a real `~/.zshrc` or `~/scripts` is already there, it is moved aside to
`~/.zshrc.backup-<timestamp>` rather than clobbered. Links from an earlier
install are simply repointed.

`install.sh` prompts for each group of optional dependencies (packages, ruby,
python, node); set `CI` to a non-empty value to decline all of them without
being asked. Every command that changes the machine goes through a `run`
wrapper, so `--dry-run` reports the whole bootstrap without touching anything.

The Ruby and Python steps install `rbenv` and `pyenv` and then build a language
version with them, so gems and pip packages never land in the system or
Homebrew toolchain. Both default to the newest stable release the version
manager offers; pin one instead with:

```sh
DOTFILES_RUBY_VERSION=3.3.6 DOTFILES_PYTHON_VERSION=3.12.7 ./install.sh
```

## Packages

Packages live in Brewfiles and are installed with `brew bundle`, so adding one
is a one-line diff and Homebrew handles casks, taps and the
already-installed check.

| File | Installed |
| --- | --- |
| `Brewfile` | always |
| `Brewfile.ruby` | when you answer yes to the Ruby prompt |
| `Brewfile.python` | when you answer yes to the Python prompt |
| `Brewfile.node` | when you answer yes to the Node prompt |

`brew bundle` has no tag support, so an optional group is a separate file. The
Ruby and Python ones declare only `rbenv` and `pyenv`: the interpreter itself
comes from the version manager, not from Homebrew.

Outside `install.sh` they are ordinary Brewfiles:

```sh
brew bundle --file=Brewfile         # install
brew bundle check --file=Brewfile   # dry run: what is missing?
brew bundle cleanup --file=Brewfile # report packages no longer declared
```

## Scripts

Every file in `scripts/` is sourced by `.zshrc` on shell startup, in glob
order, so the filenames decide the order.

| File | What it sets up |
| --- | --- |
| `browserstack` | BrowserStack credentials and the path to Chrome |
| `completion` | `compinit`, case-insensitive matching, arrow-key menu selection |
| `docker` | Docker aliases and BuildKit |
| `editor` | `$EDITOR` and `$VISUAL` |
| `git` | The prompt, including the current branch |
| `github` | `git` and `gh` aliases |
| `history` | A 50k-line shared history that dedupes |
| `homebrew` | Homebrew's curl on `$PATH` |
| `navigation` | `AUTO_CD` and the directory stack |
| `nvm` | nvm and its completion |
| `oh-my-zsh` | oh-my-zsh, when installed |
| `rbenv` | rbenv and its shims |
| `zsh-plugins` | `zsh-autosuggestions` and `zsh-syntax-highlighting`, when installed |

`oh-my-zsh` is the exception: `.zshrc` sources it by name before the loop, and
the loop then skips it. See below.

Two of the remaining filenames are load-bearing, and `tests/profile_test.sh`
guards both: `completion` has to sort before `nvm`, whose completion is loaded
on top of `compinit`, and `zsh-plugins` has to sort last, because
`zsh-syntax-highlighting` needs to see the widgets everything else defines.

The plugins in `zsh-plugins` are optional - `install.sh` installs them with the
general packages, and a shell without them starts normally.

### Oh My Zsh
Sourced before everything else in `scripts/`, because it brings aliases,
options and completions of its own and the files here are meant to win over
them: `gp` is `git pull` because `scripts/github` says so, not `git push`
because oh-my-zsh's git plugin does.

It is configured, not adopted wholesale:

- **No theme.** `scripts/git` owns `$PROMPT`, so a theme would only be read
  and then overwritten.
- **`plugins=(brew docker gh)`** - completion and aliases for tools this repo
  already installs. `git` is deliberately absent: `scripts/github` owns the git
  aliases, and the plugin's own hundred-odd would be shadowed where the two
  overlap and left standing where they do not.
- **`zstyle ':omz:update' mode reminder`** - the default stops and asks, which
  puts a prompt in front of the first command in a new terminal. Run
  `omz update` when it suits.
- **One completion dump.** oh-my-zsh runs `compinit` itself and would otherwise
  write its own dump into `$HOME`, so `scripts/oh-my-zsh` points it at the same
  cache-directory path `scripts/completion` uses, and `scripts/completion`
  skips the second `compinit` when oh-my-zsh has already run one.

Like `zsh-plugins`, it is optional at shell startup: a machine without
`~/.oh-my-zsh` gets a plain shell rather than an error on every prompt.

### Nvm
nvm owns the node runtime, the way `rbenv` and `pyenv` own theirs: `install.sh`
installs only `nvm` and then `nvm install --lts`, so there is no
Homebrew-installed `node` racing nvm's shims for `$PATH`. This script loads nvm
on every new shell - without it there is no `node` on `$PATH` at all - and finds
`nvm.sh` whether it came from the Homebrew formula or from nvm's own installer.

### Browserstack
Points `$CHROME` at the macOS Chrome binary and exports
`BROWSERSTACK_USERNAME` / `BROWSERSTACK_ACCESS_KEY` when they already hold a
value. It never assigns them: the credentials belong in `~/.zshrc.local` (see
below), not in this tracked file.

## Local overrides

`.zshrc` sources `~/.zshrc.local` last, if it exists. Anything
machine-specific or secret goes there, where it overrides everything in
`scripts/`:

```sh
cat >>~/.zshrc.local <<'EOF'
export BROWSERSTACK_USERNAME=your-username
export BROWSERSTACK_ACCESS_KEY=your-access-key
EOF
```

The file lives in `$HOME`, outside the checkout, and `install.sh` never touches
it: only `~/.zshrc` and `~/scripts` are linked. `.gitignore` covers it so a copy
made inside the checkout cannot be committed by a stray `gaa` (`git add .`).

## Tests

```sh
./tests/run.sh                  # run everything
./tests/run.sh source_profile   # run tests whose name contains "source_profile"
```

The suite needs nothing but `bash` and `zsh`, so it runs on a machine this repo
has not bootstrapped yet. Each test runs in its own subshell with a throwaway
`$HOME` and a stub directory at the front of `$PATH`, so a test can never touch
the real machine or run a real `brew`, `defaults` or `sudo`.

| File | Covers |
| --- | --- |
| `tests/install_test.sh` | `install.sh` functions: `brew bundle` installs, the CI/interactive prompt, the symlinks into `$HOME` and their backup and failure paths, macOS defaults |
| `tests/brewfile_test.sh` | the Brewfiles: every one is installed by `install.sh`, and every entry is a directive `brew bundle` understands |
| `tests/profile_test.sh` | `.zshrc`: loading `scripts/`, loading oh-my-zsh first and exactly once, sourcing `~/.zshrc.local` last, and coping with a missing or empty `~/scripts` |
| `tests/scripts_test.sh` | each file in `scripts/`: parses, exits cleanly, and defines the expected aliases, exports and functions |

`tests/helpers/framework.sh` is the (dependency-free) test framework: a test
file defines `test_*` functions and ends with `run_tests "$@"`.

## CI

Every push to `main` and every pull request runs `.github/workflows/ci.yml`:

- **Lint** (Ubuntu) - `shellcheck` and `bash -n` over the bash scripts and the
  tests.
- **Tests** (Ubuntu and macOS) - `./tests/run.sh`.
- **Run install.sh** (macOS) - runs `install.sh` end to end against a throwaway
  `$HOME`, twice, then checks the installed paths are symlinks into the checkout,
  that oh-my-zsh was cloned, and diffs the linked files against the repo.
