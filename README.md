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
| `rbenv` | rbenv and its shims |
| `zsh-plugins` | `zsh-autosuggestions` and `zsh-syntax-highlighting`, when installed |

Two of the filenames are load-bearing, and `tests/profile_test.sh` guards both:
`completion` has to sort before `nvm`, whose completion is loaded on top of
`compinit`, and `zsh-plugins` has to sort last, because
`zsh-syntax-highlighting` needs to see the widgets everything else defines.

The plugins in `zsh-plugins` are optional - `install.sh` installs them with the
general packages, and a shell without them starts normally.

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
| `tests/profile_test.sh` | `.zshrc`: loading `scripts/`, and coping with a missing or empty `~/scripts` |
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
