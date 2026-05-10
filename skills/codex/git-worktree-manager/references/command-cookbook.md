# Command Cookbook

## Helper Commands

Use these PowerShell helpers in this environment:

- `gnew <url> [name]`: create `project/.bare`, configure fetch refs, fetch origin, and create the default-branch worktree
- `gwt <branch> [-From <base>]`: create a new worktree and branch under the current managed project
- `gwl`: list worktrees in the current managed project
- `gwrm [branch]`: remove a clean worktree and delete its branch
- `gprune [--force]`: destructively reset/prune a managed project to only `.bare` and the default branch worktree

`gwt`, `gwl`, `gwrm <branch>`, and `gprune` can be run from inside any managed worktree, from the project root, or from `.bare`. When `gwt <branch>` is run from the project root or `.bare` and `-From` is omitted, the branch is created from the repository default branch. `gwrm` without a branch still needs a current worktree to infer which branch to remove.

## Command Targeting Rule

In some Codex shell environments, do not rely on tool `workdir` alone for Git commands. Prefer one of these forms:

```powershell
git -C <worktree-path> <args...>
git --git-dir <project>/.bare --work-tree <worktree-path> <args...>
```

Use `git -C` by default. Use `--git-dir/--work-tree` when you are operating from outside the repository or when you need to target the bare repo explicitly.

## Common Flows

Initialize a new managed repo:

```powershell
cd "$HOME\OneDrive\Documents\Everything\repositories"
gnew https://github.com/example/repo.git
```

Create a feature branch and agent branches:

```powershell
gwt feat/search-redesign -From master
gwt feat/search-redesign-ui -From feat/search-redesign
gwt feat/search-redesign-api -From feat/search-redesign
```

Merge agent branches into the feature branch:

```powershell
git -C .\feat-search-redesign merge feat/search-redesign-ui
git -C .\feat-search-redesign merge feat/search-redesign-api
```

Merge the feature branch into trunk:

```powershell
git -C .\main merge feat/search-redesign
```

Clean up merged agent branches:

```powershell
gwrm feat/search-redesign-ui
gwrm feat/search-redesign-api
```

Reset a managed repo to only the default branch worktree after confirming all other work is disposable:

```powershell
gprune
gprune -Force
```

For Bash or Zsh:

```bash
gprune
gprune --force
```

Without the force flag, `gprune` prints a dry-run summary and exits non-zero. With the force flag, it fetches and prunes remotes, ensures `project/<default-branch>` exists, hard-resets it to `origin/<default-branch>`, cleans untracked files, removes all other registered worktrees including external or temporary worktrees, deletes removed non-default local branches where possible, runs `git worktree prune`, and removes stray project-root entries so only `.bare` and `<default-branch>` remain.

## Troubleshooting

If the helper commands are missing:

```powershell
. "$HOME\OneDrive\Documents\Everything\scripts\git-worktree.ps1"
```

If unsure whether the current directory belongs to a managed project:

```powershell
git -C <worktree-path> rev-parse --path-format=absolute --git-common-dir
```

Expect the result to end with `.bare` for managed projects created with `gnew`.

If plain `git status` fails even though the repo is a valid worktree, check whether the shell actually changed directories. Prefer:

```powershell
git -C <worktree-path> status --short --branch
```

If needed, target the managed bare repo explicitly:

```powershell
git --git-dir <project>/.bare --work-tree <worktree-path> status --short --branch
```

## Manual `gprune` Test Checklist

Use a disposable local repository fixture. Verify:

- `gprune` without force exits non-zero and removes nothing.
- `gprune --force` works from the project root, `.bare`, the default worktree, and a feature worktree.
- A missing default worktree is recreated at `project/<default-branch>`.
- Dirty non-default worktrees are removed after force confirmation.
- External registered worktrees are removed.
- Stray top-level project files and folders are removed.
- Final output shows remaining registered worktrees, default branch status, local and `origin/<default-branch>` SHAs, and top-level project-root contents.
