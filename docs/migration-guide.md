# Migration Guide

This guide covers moving an existing normal clone into the bare-repo worktree layout without deleting local work.

## Recommended Migration Strategy

1. Fetch and inspect the repo first.
2. Preserve all local refs and working files.
3. Make a full sibling backup copy of the original repo.
4. Rebuild the original repo path as:

```text
repo/
  .bare/
  main/ or master/
```

5. Reapply any uncommitted local changes into the active default-branch worktree.

This repository includes a PowerShell implementation at `scripts/powershell/migrate-repo-to-worktrees.ps1`.

## Why Rebuild in Place

Re-cloning from remote is not sufficient when local refs, local commits, or dirty files exist.

Cloning from the existing local repo into a new bare repo preserves:

- local branches
- local commits not yet pushed
- Git config stored in the repository

Keeping a sibling backup also gives a straightforward rollback path.

## Push Before Migration

If the current branch is ahead of origin and the local state is intended, push before migrating.

If the repo has uncommitted changes, either:

- commit and push them first, or
- preserve them during migration and commit later

## Post-Migration Checks

After migration, verify:

```bash
git rev-parse --path-format=absolute --git-common-dir
git worktree list
git status --short --branch
```

For a managed repo, the common dir should end with `.bare`.
