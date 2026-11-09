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
installer is writing a `.zshrc` and running `chsh`, and this repo does both of
those itself. A clone is all `omz update` needs, and a machine that already has
one is left alone.

It makes zsh the login shell, so every new terminal - iTerm2, Terminal, VS
Code's - starts the zsh this repo configures. It reads the current shell from
the account database (`dscl` on macOS), and when that is not already a zsh it
runs `chsh -s /bin/zsh`, which asks for your password. `/bin/zsh` is preferred
over a Homebrew zsh because macOS ships it and already lists it in
`/etc/shells`; on a machine without it, the first `zsh` on `$PATH` is added to
`/etc/shells` (with `sudo`) and used instead. A failed `chsh` prints the
command to run by hand rather than stopping the bootstrap, and the step is
skipped in CI.

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

The Node step clones [nvm](https://github.com/nvm-sh/nvm) into `~/.nvm` at its
latest release - nvm's own manual install, since nvm does not support the
Homebrew formula - and runs `nvm install --lts`, so there is no Homebrew
`node` racing nvm's shims for `$PATH`. A `~/.nvm` left behind by a Homebrew
nvm (node versions, but no `nvm.sh`) gets nvm fetched into it in place, the
way nvm's own installer does, so the versions already installed keep working.

### Upgrading an existing machine

`git pull` in the checkout is normally the whole update, but a machine
bootstrapped when nvm came from Homebrew needs one more step: re-run
`./install.sh` and answer yes to Node. Until then `scripts/nvm` is gone and
oh-my-zsh's nvm plugin finds no `nvm.sh` in `~/.nvm`, so new terminals have no
`node`, `npm` or `npx`. The re-run installs nvm into the existing `~/.nvm`
without touching the node versions in it; `brew uninstall nvm` afterwards is
optional.

## Packages

Packages live in Brewfiles and are installed with `brew bundle`, so adding one
is a one-line diff and Homebrew handles casks, taps and the
already-installed check.

| File | Installed |
| --- | --- |
| `Brewfile` | always |
| `Brewfile.ruby` | when you answer yes to the Ruby prompt |
| `Brewfile.python` | when you answer yes to the Python prompt |

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

The shell is [oh-my-zsh](https://github.com/ohmyzsh/ohmyzsh) with its standard
plugins; `scripts/` holds only what oh-my-zsh does not do. Every file in it is
sourced by `.zshrc` on shell startup, in glob order.

| File | What it sets up |
| --- | --- |
| `browserstack` | BrowserStack credentials and the path to Chrome |
| `editor` | `$EDITOR` and `$VISUAL` |
| `oh-my-zsh` | oh-my-zsh, its theme and plugins, when installed |
| `zsh-plugins` | `zsh-autosuggestions` and `zsh-syntax-highlighting`, when installed |

`oh-my-zsh` is the exception to the glob order: `.zshrc` sources it by name
before the loop, and the loop then skips it. `zsh-plugins` has to sort last,
because `zsh-syntax-highlighting` needs to see the widgets everything else
defines; `tests/profile_test.sh` guards that.

The plugins in `zsh-plugins` are optional - `install.sh` installs them with the
general packages, and a shell without them starts normally.

### Oh My Zsh
Sourced before everything else in `scripts/`, because it brings aliases,
options and completions of its own, and anything here - or in
`~/.zshrc.local` - is meant to win over them. Nothing in `scripts/` redefines
an oh-my-zsh alias today.

Besides the plugins, oh-my-zsh's own `lib/` provides what used to be separate
files here: completion (`compinit`, menu selection, case-insensitive
matching), a 50k-line shared history in `~/.zsh_history`, and `AUTO_CD` with
the directory stack.

- **`ZSH_THEME="robbyrussell"`** - oh-my-zsh's default theme draws the
  prompt, git branch and dirty marker included. Nothing in `scripts/` sets
  `$PROMPT`, and `tests/scripts_test.sh` keeps it that way, since a file
  sourced after oh-my-zsh would silently replace the theme's.
- **`plugins=(git brew docker gh nvm pyenv rbenv)`** - the standard aliases
  and completion for the everyday tools, and the version managers loaded:
  - `git`: the standard git aliases (`gst` status, `gaa` add all, `gl` pull,
    `gp` push, `gbda` delete merged branches, ...); see `alias | grep git` or
    the [plugin's README](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/git).
  - `docker`: the standard docker aliases (`dr` run, `dps` ps, `dsprune`
    system prune, ...).
  - `brew`: also runs `brew shellenv` when Homebrew is not on `$PATH` yet,
    which on Apple Silicon is what puts it there: nothing else in this repo,
    and no `~/.zprofile`, does.
  - `nvm`, `pyenv`, `rbenv`: load the version managers `install.sh` sets up,
    each skipped when its tool is not installed. nvm is lazy-loaded
    (`zstyle ':omz:plugins:nvm' lazy yes`): loading it was most of the
    startup time, about 0.65 s of 1 s, so it now loads on the first `nvm`,
    `node`, `npm`, `npx`, `yarn`, `pnpm` or `corepack` instead. Until then,
    global npm tools (`tsc`, `eslint`, ...) are not on `$PATH`, and nor are
    they for git hooks that call them - run `node -v` once in a new terminal
    first. To lazy-load on a global tool too, add it to the plugin's
    `lazy-cmd` style in `scripts/oh-my-zsh`; to load eagerly again, delete the
    `lazy` line. (`~/.zshrc.local` is too late for either: the plugin has
    already run.)
- **Homebrew completions.** `scripts/oh-my-zsh` puts Homebrew's
  `share/zsh/site-functions` on `$fpath` before oh-my-zsh runs `compinit`, as
  Homebrew's instructions say. The `brew` plugin adds it too, but only after
  `compinit`, which left `brew`, `docker` and the rest without completion.
- **`zstyle ':omz:update' mode reminder`** - the default stops and asks, which
  puts a prompt in front of the first command in a new terminal. Run
  `omz update` when it suits.
- **The completion dump** goes under the cache directory
  (`~/.cache/zsh/zcompdump-<zsh version>`) rather than into `$HOME`.

oh-my-zsh is optional at shell startup: a machine without `~/.oh-my-zsh` gets
zsh's plain defaults rather than an error on every prompt.

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
made inside the checkout cannot be committed by a stray `gaa` (`git add --all`).

## Tests

```sh
./tests/run.sh                  # run everything
./tests/run.sh source_profile   # run tests whose name contains "source_profile"
```

The suite needs nothing but `bash` and `zsh`, so it runs on a machine this repo
has not bootstrapped yet. Each test runs in its own subshell with a throwaway
`$HOME` and a stub directory at the front of `$PATH`, so a test can never touch
the real machine or run a real `brew`, `defaults`, `chsh` or `sudo`. The
variables a loaded oh-my-zsh or nvm exports (`ZSH`, `NVM_DIR`, ...) are cleared
too, so the suite gives the same answer from a fully set-up shell as from CI.

| File | Covers |
| --- | --- |
| `tests/install_test.sh` | `install.sh` functions: `brew bundle` installs, the CI/interactive prompt, the nvm clone, the symlinks into `$HOME` and their backup and failure paths, the login shell, macOS defaults |
| `tests/brewfile_test.sh` | the Brewfiles: every one is installed by `install.sh`, every entry is a directive `brew bundle` understands, and none declares nvm or node |
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
