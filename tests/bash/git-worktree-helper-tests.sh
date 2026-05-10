#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HELPER="$REPO_ROOT/scripts/bash/git-worktree.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_exists() {
  [[ -e "$1" ]] || fail "Expected path to exist: $1"
}

assert_not_exists() {
  [[ ! -e "$1" ]] || fail "Expected path to be absent: $1"
}

assert_only_default_layout() {
  local project_root="$1"
  local default_branch="$2"
  assert_exists "$project_root/.bare"
  assert_exists "$project_root/$default_branch"
  local contents
  contents="$(find "$project_root" -mindepth 1 -maxdepth 1 -exec basename {} \; | sort | tr '\n' ' ')"
  [[ "$contents" == ".bare $default_branch " ]] || fail "Unexpected project contents: $contents"
  git -C "$project_root/$default_branch" diff --quiet || fail "Default worktree has tracked changes"
  [[ -z "$(git -C "$project_root/$default_branch" status --porcelain)" ]] || fail "Default worktree is not clean"
}

make_remote() {
  local root="$1"
  local origin="$root/origin.git"
  local seed="$root/seed"
  git init --bare "$origin" >/dev/null
  git clone "$origin" "$seed" >/dev/null
  git -C "$seed" config user.email "codex@example.test"
  git -C "$seed" config user.name "Codex Test"
  printf 'initial\n' > "$seed/README.md"
  git -C "$seed" add README.md
  git -C "$seed" commit -m "initial" >/dev/null
  git -C "$seed" branch -M main
  git -C "$seed" push -u origin main >/dev/null
  git -C "$origin" symbolic-ref HEAD refs/heads/main
  printf '%s\n' "$origin"
}

run_case() {
  local name="$1"
  local body="$2"
  local root
  root="$(mktemp -d "${TMPDIR:-/tmp}/gwt-test.XXXXXX")"
  printf 'TEST: %s\n' "$name"
  (
    # shellcheck source=/dev/null
    source "$HELPER"
    cd "$root"
    local origin
    origin="$(make_remote "$root")"
    eval "$body"
  )
  rm -rf "$root"
}

run_case "gwt supports -From and gprune dry-run is non-zero" '
  gnew "$origin" managed
  cd "$root/managed"
  gwt feat/from-test -From main
  cd "$root/managed"
  if gprune >/tmp/gprune-dry-run.out 2>&1; then
    fail "gprune dry-run should fail"
  fi
  assert_exists "$root/managed/feat/from-test"
'

run_case "gprune force from feature worktree removes dirty worktree and stray root entries" '
  gnew "$origin" managed
  gwt feat/test main
  printf dirty > "$root/managed/feat/test/dirty.txt"
  printf stray > "$root/managed/stray.txt"
  mkdir "$root/managed/stray-dir"
  gprune --force
  assert_only_default_layout "$root/managed" main
  assert_not_exists "$root/managed/feat"
  if git -C "$root/managed/.bare" show-ref --verify --quiet refs/heads/feat/test; then
    fail "Expected feat/test branch to be deleted"
  fi
'

run_case "gprune recreates missing default worktree" '
  gnew "$origin" managed
  cd "$root/managed"
  rm -rf main
  gprune --force
  assert_only_default_layout "$root/managed" main
'

printf 'All git-worktree helper tests passed.\n'
