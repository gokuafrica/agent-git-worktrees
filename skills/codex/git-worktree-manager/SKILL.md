---
name: git-worktree-manager
description: Manage Git worktree and Git work tree workflows for parallel agent work, especially bare-repo setups with a `.bare` directory plus sibling worktrees. Use when Codex needs to discuss git worktrees or git work trees, set up or maintain this repository layout, create feature or agent branches with `gnew` or `gwt`, inspect active worktrees with `gwl`, merge agent branches back into a feature or trunk branch, or safely remove finished worktrees with `gwrm`.
---

# Git Worktree Manager

## Overview

Use the helper scripts in this repository to create, branch, inspect, merge, and remove worktrees. Keep one agent per worktree and one branch per worktree; never try to check out the same branch in multiple worktrees.

Read [references/command-cookbook.md](./references/command-cookbook.md) when exact commands or naming patterns are needed.

## Verify Environment

Confirm that worktree helper commands are available before using them:

```powershell
. .\scripts\powershell\git-worktree.ps1
Get-Command gnew,gwt,gwl,gwrm
```

For Bash or Zsh:

```bash
source ./scripts/bash/git-worktree.sh
type gnew gwt gwl gwrm
```

Prefer the helper commands over hand-written `git worktree` commands because they already encode the bare-repo layout and cleanup behavior.

## Command Execution Nuance

In some Codex shell environments, setting a tool `workdir` is not enough to guarantee that `git` runs from that directory. Treat that as an execution quirk, not a repository problem.

Use these rules:

1. Prefer `git -C <worktree-path> ...` for ordinary Git commands such as `status`, `branch`, `merge`, `push`, and `diff`.
2. If `git -C` is still awkward or you are operating from outside the repo entirely, use `git --git-dir <project>/.bare --work-tree <project>/<branch> ...`.
3. Do not assume plain `git status` is safe just because the shell tool was given a `workdir`.
4. When verifying a managed repo, prefer `git -C <worktree-path> rev-parse --path-format=absolute --git-common-dir`.

## Use the Repository Layout

Assume this layout for managed projects:

```text
project/
  .bare/
  master/           or main/
  feat-foo/
  feat-foo-ui/
  feat-foo-server/
```

Treat `.bare` as the shared Git database. Treat every sibling directory as an equal worktree.

The helpers can be run from any directory inside a managed worktree, from the project root, or from `.bare`. If `gwt <branch>` is run from the project root or `.bare` without `-From`, it creates the new branch from the repository default branch. `gwrm` without an explicit branch still requires a current checked-out worktree so it can infer which branch to remove.

## Choose the Branch Strategy

Use this decision rule:

1. Create a new managed project with `gnew` when the repository does not yet use the bare-repo layout.
2. Create a feature integration branch from the default branch when multiple agents will collaborate on one larger feature.
3. Create one agent branch per agent from that feature integration branch.
4. Merge agent branches into the feature branch.
5. Merge the feature branch into the default branch.
6. Remove finished agent worktrees only after their changes are merged or no longer needed.

Do not create multiple worktrees for the same branch. If several agents are working on one feature, give them sibling branches that all start from the same feature branch instead.

## Create Worktrees

Create a new managed project:

```powershell
gnew <git-url> [folder-name]
```

Create a feature branch/worktree from trunk:

```powershell
gwt feat/voice-v2 -From master
```

Create agent branches/worktrees from that feature branch:

```powershell
gwt feat/voice-v2-ui -From feat/voice-v2
gwt feat/voice-v2-server -From feat/voice-v2
gwt feat/voice-v2-tests -From feat/voice-v2
```

Remember that `gwt <branch>` without `-From` defaults to the repository default branch, including when the shell is at the project root or inside `.bare`.

## Inspect Active Work

List worktrees with:

```powershell
gwl
```

Use `git -C <worktree-path> status --short --branch` inside a specific worktree when the user asks for branch state or dirtiness. Use `git worktree list` directly only when debugging helper behavior.

## Merge Back Safely

Merge agent branches into the feature branch from the feature branch worktree:

```powershell
git -C <feature-worktree-path> merge feat/voice-v2-ui
git -C <feature-worktree-path> merge feat/voice-v2-server
git -C <feature-worktree-path> merge feat/voice-v2-tests
```

Then merge the feature branch into trunk from the trunk worktree:

```powershell
git -C <trunk-worktree-path> merge feat/voice-v2
```

If the user prefers rebasing or squash merges, follow that preference explicitly. Otherwise use normal merges and report conflicts clearly.

## Clean Up Worktrees

Use `gwrm <branch>` for routine cleanup. It removes the worktree and deletes the branch, but only if the worktree is clean and not the default branch worktree.

Examples:

```powershell
gwrm feat/voice-v2-ui
gwrm feat/voice-v2-server
```

If already inside the target worktree, `gwrm` moves back to the default branch worktree before removing it.

## Safety Rules

Follow these rules every time:

1. Verify the current repository with `git -C <worktree-path> rev-parse --path-format=absolute --git-common-dir` when unsure whether the repo uses the bare layout.
2. Refuse to remove dirty worktrees unless the user explicitly wants destructive cleanup and has confirmed it.
3. Refuse to share a branch across multiple worktrees.
4. State clearly which branch is the integration branch and which branches are agent branches.
5. Prefer explicit `-From` arguments when creating agent branches from a feature branch so lineage stays obvious.
