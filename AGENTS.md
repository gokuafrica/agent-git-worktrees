# Agent Rules

Use this repository when the task involves Git worktrees, Git work trees, parallel agent branches, or migration to a bare-repo worktree layout.

## Core Model

- Prefer a bare repository at `.bare/` plus sibling worktrees.
- Treat `.bare/` as the shared Git database and every sibling directory as an equal checkout.
- Keep one agent per worktree.
- Keep one branch per worktree.
- Never check out the same branch in multiple worktrees.

## Branching Strategy

Use this sequence:

1. Create a feature integration branch from trunk when multiple agents will collaborate on one feature.
2. Create one agent branch per agent from that feature branch.
3. Merge agent branches into the feature branch.
4. Merge the feature branch into trunk.
5. Remove finished worktrees after merge.

## Command Preference

Prefer the helper scripts in `scripts/powershell/` or `scripts/bash/` over ad hoc `git worktree` commands when the environment matches those shells.

The helpers may be invoked from any managed worktree, the project root, or `.bare`. `gwt <branch>` from the project root or `.bare` uses the repository default branch when no base is provided. `gwrm` without an explicit branch only infers the branch when the current directory is inside a checked-out worktree.

When running ordinary Git commands such as `status`, `diff`, `merge`, `branch`, or `push`, prefer explicit targeting:

- `git -C <worktree-path> ...`
- `git --git-dir <project>/.bare --work-tree <worktree-path> ...`

Do not rely on a tool-level working directory alone in shell environments where it may not actually be applied.

## Safety

- Refuse to remove dirty worktrees unless the user explicitly approves destructive cleanup.
- Verify the current repo layout before assuming `.bare/` exists.
- State clearly which branch is the integration branch and which branches are agent branches.
- Treat workdir failures as an execution quirk, not as evidence that the worktree layout is wrong.
