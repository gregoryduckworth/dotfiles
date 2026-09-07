# dotfiles

[![CI](https://github.com/gregoryduckworth/dotfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/gregoryduckworth/dotfiles/actions/workflows/ci.yml)

Install script for useful items

## Usage

```sh
./install.sh   # bootstrap a machine
./update.sh    # re-copy scripts/ and .zshrc into $HOME
```

Both scripts resolve paths against the checkout, so they can be run from
anywhere, and both are safe to re-run.

The Ruby and Python steps install `rbenv` and `pyenv` and then build a language
version with them, so gems and pip packages never land in the system or
Homebrew toolchain. Both default to the newest stable release the version
manager offers; pin one instead with:

```sh
DOTFILES_RUBY_VERSION=3.3.6 DOTFILES_PYTHON_VERSION=3.12.7 ./install.sh
```

## Scripts

Every file in `scripts/` is sourced by `.zshrc` on shell startup.

### Github
This sets up a few aliases, hub and adds the branch to the terminal output

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

The file lives in `$HOME` and is never copied, overwritten or removed by
`install.sh` or `update.sh`, and `.gitignore` covers it so a copy made inside
the checkout cannot be committed by a stray `gaa` (`git add .`).

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
| `tests/install_test.sh` | `install.sh` functions: brew installs, the CI/interactive prompt, profile installation and its failure paths, macOS defaults |
| `tests/update_test.sh` | `update.sh`: the prompt's answers and the copy into `$HOME` |
| `tests/profile_test.sh` | `.zshrc`: loading `scripts/`, sourcing `~/.zshrc.local` last, and coping with a missing or empty `~/scripts` |
| `tests/scripts_test.sh` | each file in `scripts/`: parses, exits cleanly, and defines the expected aliases, exports and functions |

`tests/helpers/framework.sh` is the (dependency-free) test framework: a test
file defines `test_*` functions and ends with `run_tests "$@"`.

## CI

Every push to `main` and every pull request runs `.github/workflows/ci.yml`:

- **Lint** (Ubuntu) - `shellcheck` and `bash -n` over the bash scripts and the
  tests.
- **Tests** (Ubuntu and macOS) - `./tests/run.sh`.
- **Run install.sh** (macOS) - runs `install.sh` end to end against a throwaway
  `$HOME` and diffs the installed files against the repo.
