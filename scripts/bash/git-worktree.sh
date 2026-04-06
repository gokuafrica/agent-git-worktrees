#!/usr/bin/env bash

set -euo pipefail

git_checked() {
  local error_message="$1"
  shift
  if ! git "$@"; then
    printf '%s\n' "$error_message" >&2
    return 1
  fi
}

git_string() {
  git "$@" 2>/dev/null | head -n 1
}

git_ref_exists() {
  local git_dir="$1"
  local ref_name="$2"
  git -C "$git_dir" show-ref --verify --quiet "$ref_name" 2>/dev/null
}

repo_name_from_url() {
  local url="$1"
  local trimmed="${url%/}"
  local leaf="${trimmed##*/}"
  leaf="${leaf##*:}"
  printf '%s\n' "${leaf%.git}"
}

git_default_branch() {
  local git_dir="$1"
  local origin_head
  origin_head="$(git_string -C "$git_dir" symbolic-ref --quiet refs/remotes/origin/HEAD || true)"
  if [[ -n "$origin_head" ]]; then
    printf '%s\n' "${origin_head#refs/remotes/origin/}"
    return 0
  fi

  local head_ref
  head_ref="$(git_string -C "$git_dir" symbolic-ref --quiet --short HEAD || true)"
  if [[ -n "$head_ref" ]]; then
    printf '%s\n' "$head_ref"
    return 0
  fi

  printf "Could not determine the default branch for '%s'.\n" "$git_dir" >&2
  return 1
}

bare_project_root() {
  local start_path="${1:-$PWD}"
  local current_worktree
  current_worktree="$(git_string -C "$start_path" rev-parse --show-toplevel || true)"

  if [[ -z "$current_worktree" ]]; then
    if [[ "$(basename "$start_path")" == ".bare" && -d "$start_path" ]]; then
      dirname "$start_path"
      return 0
    fi

    if [[ -d "$start_path/.bare" ]]; then
      printf '%s\n' "$start_path"
      return 0
    fi

    printf 'Run this command inside a managed Git worktree, project root, or .bare directory.\n' >&2
    return 1
  fi

  local git_common_dir
  git_common_dir="$(git_string -C "$start_path" rev-parse --path-format=absolute --git-common-dir || true)"
  if [[ -z "$git_common_dir" ]]; then
    printf 'Run this command inside a managed Git worktree, project root, or .bare directory.\n' >&2
    return 1
  fi

  if [[ "$(basename "$git_common_dir")" != ".bare" ]]; then
    printf 'This command expects the bare-repo layout: <project>/.bare plus sibling worktrees.\n' >&2
    return 1
  fi

  dirname "$git_common_dir"
}

gnew() {
  if [[ $# -lt 1 || $# -gt 2 ]]; then
    printf 'Usage: gnew <url> [name]\n' >&2
    return 1
  fi

  local url="$1"
  local name="${2:-$(repo_name_from_url "$url")}"
  local project_root="$PWD/$name"
  local bare_dir="$project_root/.bare"

  if [[ -e "$project_root" ]]; then
    printf "Target directory already exists: %s\n" "$project_root" >&2
    return 1
  fi

  mkdir -p "$project_root"
  git_checked "Failed to create bare clone." clone --bare "$url" "$bare_dir"
  git_checked "Failed to configure origin fetch refspec." -C "$bare_dir" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
  git_checked "Failed to enable fetch pruning." -C "$bare_dir" config fetch.prune true
  git_checked "Failed to fetch origin." -C "$bare_dir" fetch origin --prune
  git -C "$bare_dir" remote set-head origin --auto >/dev/null 2>&1 || true

  local default_branch
  default_branch="$(git_default_branch "$bare_dir")"
  local main_worktree="$project_root/$default_branch"

  git_checked "Failed to create the default worktree." -C "$bare_dir" worktree add "$main_worktree" "$default_branch"
  git_checked "Failed to set upstream tracking." -C "$main_worktree" branch --set-upstream-to "origin/$default_branch" "$default_branch"

  cd "$main_worktree"
  printf 'Ready: %s/%s\n' "$name" "$default_branch"
}

gwt() {
  if [[ $# -lt 1 || $# -gt 2 ]]; then
    printf 'Usage: gwt <branch> [from]\n' >&2
    return 1
  fi

  local branch="$1"
  local from="${2:-}"
  local project_root
  project_root="$(bare_project_root)"
  local bare_dir="$project_root/.bare"
  local default_branch
  default_branch="$(git_default_branch "$bare_dir")"

  if [[ -z "$from" ]]; then
    from="$default_branch"
  fi

  local worktree_path="$project_root/$branch"
  if [[ -e "$worktree_path" ]]; then
    printf "Target worktree path already exists: %s\n" "$worktree_path" >&2
    return 1
  fi

  if git_ref_exists "$bare_dir" "refs/heads/$branch"; then
    printf "Local branch already exists: %s\n" "$branch" >&2
    return 1
  fi

  git_checked "Failed to fetch origin." -C "$bare_dir" fetch origin --prune

  local start_point=
  if git_ref_exists "$bare_dir" "refs/heads/$from"; then
    start_point="$from"
  elif git_ref_exists "$bare_dir" "refs/remotes/origin/$from"; then
    start_point="origin/$from"
  else
    printf "Base branch not found locally or on origin: %s\n" "$from" >&2
    return 1
  fi

  mkdir -p "$(dirname "$worktree_path")"
  git_checked "Failed to create worktree '$branch'." -C "$bare_dir" worktree add -b "$branch" "$worktree_path" "$start_point"

  cd "$worktree_path"
  printf 'Ready: %s/%s (from %s)\n' "$(basename "$project_root")" "$branch" "$from"
}

gwl() {
  local project_root
  project_root="$(bare_project_root)"
  git_checked "Failed to list worktrees." -C "$project_root/.bare" worktree list
}

gwrm() {
  local project_root
  project_root="$(bare_project_root)"
  local bare_dir="$project_root/.bare"
  local default_branch
  default_branch="$(git_default_branch "$bare_dir")"
  local current_branch
  if [[ -n "$(git_string -C "$PWD" rev-parse --show-toplevel || true)" ]]; then
    current_branch="$(git_string -C "$PWD" branch --show-current || true)"
  else
    current_branch=""
  fi
  local branch="${1:-$current_branch}"

  if [[ -z "$branch" ]]; then
    printf 'Could not determine which branch to remove.\n' >&2
    return 1
  fi

  if [[ "$branch" == "$default_branch" ]]; then
    printf 'Refusing to remove the default worktree branch: %s\n' "$branch" >&2
    return 1
  fi

  local worktree_path="$project_root/$branch"
  if [[ ! -d "$worktree_path" ]]; then
    printf 'Worktree path does not exist: %s\n' "$worktree_path" >&2
    return 1
  fi

  if [[ -n "$(git -C "$worktree_path" status --porcelain)" ]]; then
    printf 'Worktree has uncommitted changes: %s\n' "$worktree_path" >&2
    return 1
  fi

  if [[ "$current_branch" == "$branch" ]]; then
    cd "$project_root/$default_branch"
  fi

  git_checked "Failed to remove worktree '$branch'." -C "$bare_dir" worktree remove "$worktree_path"
  git_checked "Failed to delete branch '$branch'." -C "$bare_dir" branch --delete "$branch"
  printf 'Removed: %s/%s\n' "$(basename "$project_root")" "$branch"
}
