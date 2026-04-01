# Why the Bare-Repo Layout Wins

This repository recommends:

```text
project/
  .bare/
  main/
  feat-a/
  feat-a-ui/
  feat-a-api/
```

Instead of:

```text
project/
  .git/
  .worktrees/
    feat-a-ui/
    feat-a-api/
```

## Practical Reasons

- The bare repo layout makes every checkout equal.
- There is no single privileged checkout that hosts all the others.
- The root directory becomes an organizational container, not a mutable working copy.
- Tools and editors handle each worktree as a normal repo checkout.
- You do not need to remember to ignore `.worktrees/`.

## Agent-Specific Reasons

- Agents should not treat one checkout as the place where every change must start.
- Agents can reason locally about "my branch, my worktree, my files" without worrying about side effects in a host checkout.
- Cleanup becomes easier to explain: remove the worktree directory and delete the branch.

## Main Constraint

`git worktree` does not want the same branch checked out in multiple worktrees.

That means the right model is:

- one feature branch for integration
- one child branch per agent
- one worktree per agent branch

Not:

- one branch shared by many worktrees
