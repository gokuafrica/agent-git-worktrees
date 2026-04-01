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

## What Not to Do

- Do not delete dirty worktrees casually.
- Do not force-delete branches that still contain unique work.
- Do not remove the default branch worktree as part of normal cleanup.
