# Merge and Cleanup

## Standard Merge Flow

Example branch set:

- `main`
- `feat/search-redesign`
- `feat/search-redesign-ui`
- `feat/search-redesign-api`

Merge agent branches into the feature branch from the feature worktree:

```bash
git merge feat/search-redesign-ui
git merge feat/search-redesign-api
```

Then merge the feature branch into trunk:

```bash
git merge feat/search-redesign
```

## When Conflicts Happen

- Resolve conflicts in the branch that is receiving the merge.
- Keep agent branches small and narrow in scope to reduce conflict surface.
- If several agent branches drift far from the feature branch, rebase or merge the feature branch into them before final integration.

## Cleanup

Only clean up a worktree after its branch has been merged or intentionally abandoned.

The normal cleanup sequence is:

1. Confirm the worktree is clean.
2. Remove the worktree checkout.
3. Delete the branch.

The helper command `gwrm` does that for managed repos when the worktree is clean.

## Destructive Prune To Default Only

Use `gprune` only when all non-default worktrees and local branches are disposable and the desired final layout is:

```text
project/
  .bare/
  main/       or master/
```

Preview the destructive cleanup:

```bash
gprune
```

Run it after explicit confirmation:

```bash
gprune --force
```

In PowerShell, use:

```powershell
gprune -Force
```

With force, `gprune` fetches and prunes remotes, ensures the default branch worktree exists at `project/<default-branch>`, hard-resets it to `origin/<default-branch>`, removes untracked files and directories, removes every other registered worktree including external or temporary worktrees, deletes removed non-default local branches where possible, runs `git worktree prune`, and removes stray top-level project-root entries. It must never remove `.bare` or the canonical default branch worktree.

Run the Bash helper smoke tests on macOS or Linux with:

```bash
./tests/bash/git-worktree-helper-tests.sh
```

Manual test checklist for changes to `gprune`:

- dry-run exits non-zero and removes nothing
- forced cleanup works from project root, `.bare`, default worktree, and feature worktree
- missing default worktree is recreated
- dirty non-default worktrees are removed with force
- external registered worktrees are removed
- stray top-level project-root files and folders are removed
- final output includes remaining worktrees, default status, default/local remote SHAs, and root contents

## What Not to Do

- Do not delete dirty worktrees casually.
- Do not force-delete branches that still contain unique work.
- Do not remove the default branch worktree as part of normal cleanup.
- Do not run `gprune --force` unless the user has explicitly confirmed that all non-default work is disposable.
