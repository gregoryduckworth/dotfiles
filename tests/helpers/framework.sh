#!/usr/bin/env bash
# A tiny test framework. Deliberately dependency-free: this repo bootstraps a
# machine that has nothing installed yet, so the tests must run with the bash
# and zsh that ship with macOS (bash 3.2) and with a stock Ubuntu runner.
#
# A test file sources this helper, defines `test_*` functions, and ends with
# `run_tests "$@"`. Each test runs in its own subshell with a throwaway $HOME
# and a stub directory at the front of $PATH, so no test can touch the real
# machine.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
export TESTS_DIR REPO_ROOT

## ---------- Assertions ---------- ##

fail() {
  echo "assertion failed: $*" >&2
  return 1
}

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  [[ "$expected" == "$actual" ]] ||
    fail "${msg:+$msg: }expected '$expected', got '$actual'"
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  [[ "$haystack" == *"$needle"* ]] ||
    fail "${msg:+$msg: }'$needle' not found in: $haystack"
}

assert_not_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  [[ "$haystack" != *"$needle"* ]] ||
    fail "${msg:+$msg: }'$needle' unexpectedly found in: $haystack"
}

assert_file() {
  [[ -f "$1" ]] || fail "expected a file at $1"
}

assert_missing() {
  [[ ! -e "$1" ]] || fail "expected nothing at $1"
}

# Runs a command with errexit suspended and asserts it exited non-zero.
assert_failure() {
  local status=0
  "$@" >/dev/null 2>&1 || status=$?
  [[ $status -ne 0 ]] || fail "expected failure from: $*"
}

## ---------- Stubs ---------- ##

# stub <name> [body]
#
# Puts an executable <name> at the front of $PATH that records the arguments it
# was called with, one call per line, then runs [body]. The body decides the
# exit status, so a stub can pretend a package is missing, a command failed, and
# so on.
stub() {
  local name="$1" body="${2:-}"
  {
    echo '#!/usr/bin/env bash'
    printf 'printf "%%s\\n" "$*" >>%q\n' "$STUB_CALLS/$name"
    printf '%s\n' "$body"
  } >"$STUB_BIN/$name"
  chmod +x "$STUB_BIN/$name"
}

stub_calls() {
  cat "$STUB_CALLS/$1" 2>/dev/null || true
}

assert_stub_called() {
  local name="$1" args="$2"
  grep -Fqx -- "$args" "$STUB_CALLS/$name" 2>/dev/null ||
    fail "$name was never called with '$args'; calls were: [$(stub_calls "$name" | tr '\n' '|')]"
}

assert_stub_not_called() {
  local name="$1" args="$2"
  if grep -Fqx -- "$args" "$STUB_CALLS/$name" 2>/dev/null; then
    fail "$name was unexpectedly called with '$args'"
  fi
}

# Skips the current test when a prerequisite is missing, rather than failing on
# a machine that simply does not have the tool.
skip_unless_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "skipped: $1 is not installed" >&2
    exit 100
  fi
}

## ---------- Runner ---------- ##

_run_one() (
  set -euo pipefail

  TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-test.XXXXXX")"
  trap 'rm -rf "$TEST_TMP"' EXIT

  HOME="$TEST_TMP/home"
  STUB_BIN="$TEST_TMP/bin"
  STUB_CALLS="$TEST_TMP/calls"
  mkdir -p "$HOME" "$STUB_BIN" "$STUB_CALLS"
  PATH="$STUB_BIN:$PATH"
  export TEST_TMP HOME STUB_BIN STUB_CALLS PATH

  cd "$REPO_ROOT"
  "$1"
)

# run_tests [name-filter]
run_tests() {
  local filter="${1:-}" name output status total=0 failures=0 skipped=0

  for name in $(compgen -A function | grep '^test_' | sort); do
    if [[ -n "$filter" && "$name" != *"$filter"* ]]; then
      continue
    fi
    total=$((total + 1))

    status=0
    output="$(_run_one "$name" 2>&1)" || status=$?

    if [[ $status -eq 0 ]]; then
      printf '  ok    %s\n' "$name"
    elif [[ $status -eq 100 ]]; then
      skipped=$((skipped + 1))
      printf '  skip  %s (%s)\n' "$name" "$output"
    else
      failures=$((failures + 1))
      printf '  FAIL  %s\n' "$name"
      printf '%s\n' "$output" | sed 's/^/        /'
    fi
  done

  printf '%s: %d run, %d failed, %d skipped\n' \
    "$(basename "$0")" "$total" "$failures" "$skipped"
  [[ $failures -eq 0 ]]
}
