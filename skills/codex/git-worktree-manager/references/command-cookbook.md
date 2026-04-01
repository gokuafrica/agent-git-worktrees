# Command Cookbook

## Helper Commands

Use these PowerShell helpers in this environment:

- `gnew <url> [name]`: create `project/.bare`, configure fetch refs, fetch origin, and create the default-branch worktree
- `gwt <branch> [-From <base>]`: create a new worktree and branch under the current managed project
- `gwl`: list worktrees in the current managed project
- `gwrm [branch]`: remove a clean worktree and delete its branch

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
git merge feat/search-redesign-ui
git merge feat/search-redesign-api
```

Merge the feature branch into trunk:

```powershell
git merge feat/search-redesign
```

Clean up merged agent branches:

```powershell
gwrm feat/search-redesign-ui
gwrm feat/search-redesign-api
```

## Troubleshooting

If the helper commands are missing:

```powershell
. "$HOME\OneDrive\Documents\Everything\scripts\git-worktree.ps1"
```

If unsure whether the current directory belongs to a managed project:

```powershell
git rev-parse --path-format=absolute --git-common-dir
```

Expect the result to end with `.bare` for managed projects created with `gnew`.
