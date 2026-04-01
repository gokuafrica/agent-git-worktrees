# Agent Git Worktrees

Bare-repo Git worktree patterns for parallel agent workflows.

This repository exists for one reason: make Git worktrees practical for multi-agent coding. The central recommendation is simple:

1. Use one bare repository as the shared Git database.
2. Use one branch per worktree.
3. Use one agent per worktree.
4. Never check out the same branch in multiple worktrees.

That gives you shared object storage, isolated working directories, and a layout that does not privilege one checkout as "the main repo".

## Why This Layout

The recommended structure is:

```text
project/
  .bare/
  main/                  or master/
  feat-search/
  feat-search-ui/
  feat-search-api/
```

`.bare/` is the brain. Every sibling directory is just a checkout.

This is usually better than a single normal clone that also hosts `.worktrees/` because:

- every worktree is equal
- there is no "special" checkout that hosts the others
- there is nothing extra to `.gitignore`
- the mental model stays clean for both humans and agents

## Recommended Branch Model

Use this pattern when several agents work on one larger feature:

- `main` or `master`: trunk
- `feat/search-redesign`: integration branch for the feature
- `feat/search-redesign-ui`: agent branch
- `feat/search-redesign-api`: agent branch
- `feat/search-redesign-tests`: agent branch

Each agent branch starts from the feature branch, not directly from trunk.

## Quick Start

### PowerShell

Source the helpers:

```powershell
. .\scripts\powershell\git-worktree.ps1
```

Create a new managed repo:

```powershell
gnew https://github.com/OWNER/REPO.git
```

Create a feature branch from trunk:

```powershell
gwt feat/search-redesign -From main
```

Create agent branches from the feature branch:

```powershell
gwt feat/search-redesign-ui -From feat/search-redesign
gwt feat/search-redesign-api -From feat/search-redesign
```

List worktrees:

```powershell
gwl
```

Remove a clean merged worktree:

```powershell
gwrm feat/search-redesign-ui
```

### Bash / Zsh

Source the helpers:

```bash
source ./scripts/bash/git-worktree.sh
```

The command surface is the same: `gnew`, `gwt`, `gwl`, `gwrm`.

## Merge Flow

Merge agent branches into the feature branch from the feature worktree:

```bash
git merge feat/search-redesign-ui
git merge feat/search-redesign-api
git merge feat/search-redesign-tests
```

Then merge the feature branch into trunk:

```bash
git merge feat/search-redesign
```

## Migration

If you already have a normal clone and want to move to the bare-repo layout, see [docs/migration-guide.md](./docs/migration-guide.md).

For Windows/PowerShell, a migration script is included at [scripts/powershell/migrate-repo-to-worktrees.ps1](./scripts/powershell/migrate-repo-to-worktrees.ps1). It keeps a full sibling backup of the original repo before rebuilding the working layout.

## Included Artifacts

- [AGENTS.md](./AGENTS.md): platform-neutral agent instructions
- [docs/why-bare-repo-layout.md](./docs/why-bare-repo-layout.md): rationale and tradeoffs
- [docs/merge-and-cleanup.md](./docs/merge-and-cleanup.md): merge, cleanup, and conflict guidance
- [scripts/powershell/git-worktree.ps1](./scripts/powershell/git-worktree.ps1): PowerShell helpers
- [scripts/powershell/migrate-repo-to-worktrees.ps1](./scripts/powershell/migrate-repo-to-worktrees.ps1): migration helper
- [scripts/bash/git-worktree.sh](./scripts/bash/git-worktree.sh): Bash/Zsh helpers
- [skills/codex/git-worktree-manager/SKILL.md](./skills/codex/git-worktree-manager/SKILL.md): Codex skill version of this workflow

## Safety Rules

1. Never share a branch across multiple worktrees.
2. Keep one agent per worktree.
3. Use explicit `-From` bases when creating agent branches from a feature branch.
4. Refuse to delete dirty worktrees unless the user explicitly wants destructive cleanup.
5. Keep backups when migrating existing repositories.

## License

MIT. See [LICENSE](./LICENSE).
