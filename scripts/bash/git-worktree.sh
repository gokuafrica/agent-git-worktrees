#!/usr/bin/env bash

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

git_lines() {
  git "$@" 2>/dev/null || true
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

  if git_ref_exists "$git_dir" "refs/remotes/origin/main"; then
    printf 'main\n'
    return 0
  fi

  if git_ref_exists "$git_dir" "refs/remotes/origin/master"; then
    printf 'master\n'
    return 0
  fi

  if git_ref_exists "$git_dir" "refs/heads/main"; then
    printf 'main\n'
    return 0
  fi

  if git_ref_exists "$git_dir" "refs/heads/master"; then
    printf 'master\n'
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
  git_checked "Failed to create bare clone." clone --bare "$url" "$bare_dir" || return 1
  git_checked "Failed to configure origin fetch refspec." -C "$bare_dir" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' || return 1
  git_checked "Failed to enable fetch pruning." -C "$bare_dir" config fetch.prune true || return 1
  git_checked "Failed to fetch origin." -C "$bare_dir" fetch origin --prune || return 1
  git -C "$bare_dir" remote set-head origin --auto >/dev/null 2>&1 || true

  local default_branch
  default_branch="$(git_default_branch "$bare_dir")"
  local main_worktree="$project_root/$default_branch"

  git_checked "Failed to create the default worktree." -C "$bare_dir" worktree add "$main_worktree" "$default_branch" || return 1
  git_checked "Failed to set upstream tracking." -C "$main_worktree" branch --set-upstream-to "origin/$default_branch" "$default_branch" || return 1

  cd "$main_worktree"
  printf 'Ready: %s/%s\n' "$name" "$default_branch"
}

gwt() {
  if [[ $# -lt 1 || $# -gt 3 ]]; then
    printf 'Usage: gwt <branch> [from|-From <from>|--from <from>]\n' >&2
    return 1
  fi

  local branch="$1"
  shift
  local from=""
  if [[ $# -eq 1 ]]; then
    from="$1"
  elif [[ $# -eq 2 && ( "$1" == "-From" || "$1" == "--from" ) ]]; then
    from="$2"
  elif [[ $# -gt 0 ]]; then
    printf 'Usage: gwt <branch> [from|-From <from>|--from <from>]\n' >&2
    return 1
  fi
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

  git_checked "Failed to fetch origin." -C "$bare_dir" fetch origin --prune || return 1

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
  git_checked "Failed to create worktree '$branch'." -C "$bare_dir" worktree add -b "$branch" "$worktree_path" "$start_point" || return 1

  cd "$worktree_path"
  printf 'Ready: %s/%s (from %s)\n' "$(basename "$project_root")" "$branch" "$from"
}

gwl() {
  local project_root
  project_root="$(bare_project_root)"
  git_checked "Failed to list worktrees." -C "$project_root/.bare" worktree list || return 1
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

  git_checked "Failed to remove worktree '$branch'." -C "$bare_dir" worktree remove "$worktree_path" || return 1
  git_checked "Failed to delete branch '$branch'." -C "$bare_dir" branch --delete "$branch" || return 1
  printf 'Removed: %s/%s\n' "$(basename "$project_root")" "$branch"
}

gprune_collect_worktrees() {
  local bare_dir="$1"
  git_lines -C "$bare_dir" worktree list --porcelain | awk '
    /^worktree / {
      if (path != "") {
        print path "\t" branch "\t" is_bare
      }
      path = substr($0, 10)
      branch = ""
      is_bare = "0"
      next
    }
    /^bare$/ {
      is_bare = "1"
      next
    }
    /^branch refs\/heads\// {
      branch = substr($0, 19)
      next
    }
    END {
      if (path != "") {
        print path "\t" branch "\t" is_bare
      }
    }
  '
}

gprune_canonical_path() {
  local target="$1"
  local parent
  local leaf

  if [[ -d "$target" ]]; then
    (cd "$target" 2>/dev/null && pwd -P) && return 0
  fi

  parent="$(dirname "$target")"
  leaf="$(basename "$target")"
  if [[ -d "$parent" ]]; then
    local canonical_parent
    canonical_parent="$(cd "$parent" 2>/dev/null && pwd -P)" || return 1
    printf '%s/%s\n' "$canonical_parent" "$leaf"
    return 0
  fi

  printf '%s\n' "$target"
}

gprune_report() {
  local project_root="$1"
  local bare_dir="$2"
  local default_branch="$3"
  local default_worktree="$4"

  printf 'Project root: %s\n' "$project_root"
  printf 'Bare directory: %s\n' "$bare_dir"
  printf 'Default branch: %s\n' "$default_branch"
  printf 'Default worktree: %s\n' "$default_worktree"
  printf '\nRegistered worktrees:\n'
  git -C "$bare_dir" worktree list || true
  printf '\nTop-level project root contents:\n'
  find "$project_root" -mindepth 1 -maxdepth 1 -print | sort || true
}

gprune_verify() {
  local project_root="$1"
  local bare_dir="$2"
  local default_branch="$3"
  local default_worktree="$4"

  printf '\nVerification:\n'
  printf 'Remaining registered worktrees:\n'
  git -C "$bare_dir" worktree list
  printf '\nDefault branch status:\n'
  git -C "$default_worktree" status --short --branch
  local local_sha
  local origin_sha
  local_sha="$(git -C "$default_worktree" rev-parse HEAD)"
  origin_sha="$(git -C "$bare_dir" rev-parse "refs/remotes/origin/$default_branch")"
  printf '\nDefault HEAD SHA: %s\n' "$local_sha"
  printf 'origin/%s SHA: %s\n' "$default_branch" "$origin_sha"
  printf '\nTop-level project root contents:\n'
  find "$project_root" -mindepth 1 -maxdepth 1 -print | sort
}

gprune_remove_reported_clean_paths() {
  local default_worktree="$1"
  local relative_path

  while IFS= read -r -d '' relative_path; do
    [[ -n "$relative_path" ]] || continue
    rm -rf -- "$default_worktree/$relative_path"
  done < <(git -C "$default_worktree" ls-files --others --ignored --exclude-standard --directory -z)
}

gprune_clean_default_worktree() {
  local default_worktree="$1"

  if git -C "$default_worktree" clean -ffdx; then
    return 0
  fi

  printf 'Warning: initial git clean failed; retrying after direct removal of reported untracked/ignored paths.\n' >&2
  if git -C "$default_worktree" clean -ffdx; then
    return 0
  fi

  gprune_remove_reported_clean_paths "$default_worktree"
  git_checked "Failed to clean default worktree." -C "$default_worktree" clean -ffdx || return 1
}

gprune() {
  local force=0
  if [[ $# -gt 1 ]]; then
    printf 'Usage: gprune [--force]\n' >&2
    return 1
  fi
  if [[ $# -eq 1 ]]; then
    case "$1" in
      --force) force=1 ;;
      *)
        printf 'Usage: gprune [--force]\n' >&2
        return 1
        ;;
    esac
  fi

  local project_root
  project_root="$(bare_project_root)"
  local bare_dir="$project_root/.bare"

  git_checked "Failed to fetch remotes." -C "$bare_dir" fetch --all --prune || return 1
  git -C "$bare_dir" remote set-head origin --auto >/dev/null 2>&1 || true

  local default_branch
  default_branch="$(git_default_branch "$bare_dir")"
  if ! git_ref_exists "$bare_dir" "refs/remotes/origin/$default_branch"; then
    printf 'Remote default branch not found: origin/%s\n' "$default_branch" >&2
    return 1
  fi

  local default_worktree="$project_root/$default_branch"
  local default_worktree_compare
  default_worktree_compare="$(gprune_canonical_path "$default_worktree")"

  if [[ "$force" -ne 1 ]]; then
    printf 'DRY RUN: gprune would destructively reset this managed repo to only the default branch worktree.\n\n'
    gprune_report "$project_root" "$bare_dir" "$default_branch" "$default_worktree"
    printf '\nWould reset and clean: %s\n' "$default_worktree"
    printf 'Would remove registered worktrees except: %s\n' "$default_worktree"
    printf 'Would delete non-default local branches whose worktrees are removed, where possible.\n'
    printf 'Would remove stray top-level project entries except .bare and %s.\n' "$default_branch"
    printf '\nRe-run with: gprune --force\n' >&2
    return 1
  fi

  if [[ -d "$default_worktree" ]]; then
    cd "$default_worktree"
  else
    cd "$project_root"
  fi

  local entries=()
  while IFS= read -r entry; do
    entries+=("$entry")
  done < <(gprune_collect_worktrees "$bare_dir")
  local entry worktree_path_entry branch is_bare rest worktree_path_compare
  local branches_to_delete=()
  for entry in "${entries[@]}"; do
    worktree_path_entry="${entry%%$'\t'*}"
    rest="${entry#*$'\t'}"
    branch="${rest%%$'\t'*}"
    is_bare="${entry##*$'\t'}"
    if [[ "$is_bare" == "1" ]]; then
      continue
    fi
    worktree_path_compare="$(gprune_canonical_path "$worktree_path_entry")"
    if [[ "$worktree_path_compare" == "$default_worktree_compare" ]]; then
      continue
    fi

    git_checked "Failed to remove worktree '$worktree_path_entry'." -C "$bare_dir" worktree remove --force "$worktree_path_entry" || return 1
    if [[ -n "$branch" && "$branch" != "$default_branch" ]]; then
      branches_to_delete+=("$branch")
    fi
  done

  if [[ ! -d "$default_worktree" || -z "$(git -C "$default_worktree" rev-parse --show-toplevel 2>/dev/null || true)" ]]; then
    rm -rf -- "$default_worktree"
    git -C "$bare_dir" worktree remove --force "$default_worktree" >/dev/null 2>&1 || true
    git_checked "Failed to prune stale default worktree metadata." -C "$bare_dir" worktree prune || return 1
    git_checked "Failed to create the default worktree." -C "$bare_dir" worktree add -B "$default_branch" "$default_worktree" "origin/$default_branch" || return 1
  fi

  git_checked "Failed to check out default branch." -C "$default_worktree" checkout -B "$default_branch" "origin/$default_branch" || return 1
  git_checked "Failed to reset default worktree." -C "$default_worktree" reset --hard "origin/$default_branch" || return 1
  gprune_clean_default_worktree "$default_worktree" || return 1
  git -C "$default_worktree" branch --set-upstream-to "origin/$default_branch" "$default_branch" >/dev/null 2>&1 || true

  local branch_to_delete
  if ((${#branches_to_delete[@]})); then
    for branch_to_delete in "${branches_to_delete[@]}"; do
      if git_ref_exists "$bare_dir" "refs/heads/$branch_to_delete"; then
        git -C "$bare_dir" branch -D "$branch_to_delete" || printf 'Warning: failed to delete local branch: %s\n' "$branch_to_delete" >&2
      fi
    done
  fi

  git_checked "Failed to prune worktree metadata." -C "$bare_dir" worktree prune || return 1

  local item
  while IFS= read -r -d '' item; do
    case "$item" in
      "$bare_dir"|"$default_worktree") ;;
      *)
        rm -rf -- "$item"
        ;;
    esac
  done < <(find "$project_root" -mindepth 1 -maxdepth 1 -print0)

  gprune_verify "$project_root" "$bare_dir" "$default_branch" "$default_worktree"
}
