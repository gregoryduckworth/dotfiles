# dotfiles

[![CI](https://github.com/gregoryduckworth/dotfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/gregoryduckworth/dotfiles/actions/workflows/ci.yml)

Install script for useful items

## Scripts

### Github
This sets up a few aliases, hub and adds the branch to the terminal output

## CI

Every push to `main` and every pull request runs `.github/workflows/ci.yml`:

- **Lint and syntax** (Ubuntu) - `shellcheck` on the bash scripts, `bash -n` and
  `zsh -n` parse checks, and a sandboxed `source ~/.zshrc` that catches scripts
  leaving a non-zero exit status behind.
- **Run install.sh** (macOS) - runs `install.sh` end to end against a throwaway
  `$HOME` and diffs the installed files against the repo.
