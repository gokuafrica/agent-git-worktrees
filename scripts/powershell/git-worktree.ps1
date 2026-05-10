function Invoke-GitChecked {
    param(
        [Parameter(Mandatory)][string]$ErrorMessage,
        [Parameter(Mandatory, ValueFromRemainingArguments)][string[]]$GitArgs
    )

    & git @GitArgs
    if ($LASTEXITCODE -ne 0) {
        throw $ErrorMessage
    }
}

function Get-GitString {
    param(
        [Parameter(Mandatory, ValueFromRemainingArguments)][string[]]$GitArgs
    )

    $output = & git @GitArgs 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    return ($output | Select-Object -First 1)
}

function Get-GitLines {
    param(
        [Parameter(Mandatory, ValueFromRemainingArguments)][string[]]$GitArgs
    )

    $output = & git @GitArgs 2>$null
    if ($LASTEXITCODE -ne 0) {
        return @()
    }

    return @($output)
}

function Test-GitRef {
    param(
        [Parameter(Mandatory)][string]$GitDir,
        [Parameter(Mandatory)][string]$RefName
    )

    & git -C $GitDir show-ref --verify --quiet $RefName 2>$null
    return $LASTEXITCODE -eq 0
}

function ConvertTo-ComparablePath {
    param([Parameter(Mandatory)][string]$Path)

    return ([System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/') -replace '/', '\').ToLowerInvariant()
}

function Get-RepoNameFromGitUrl {
    param([Parameter(Mandatory)][string]$Url)

    $trimmed = $Url.Trim().TrimEnd('/')
    $leaf = $trimmed.Split('/')[-1]
    $leaf = $leaf.Split(':')[-1]

    if ($leaf.EndsWith('.git')) {
        return $leaf.Substring(0, $leaf.Length - 4)
    }

    return $leaf
}

function Get-GitDefaultBranch {
    param([Parameter(Mandatory)][string]$GitDir)

    $originHeadRef = Get-GitString -C $GitDir symbolic-ref --quiet refs/remotes/origin/HEAD
    if ($originHeadRef) {
        return ($originHeadRef -replace '^refs/remotes/origin/', '')
    }

    if (Test-GitRef -GitDir $GitDir -RefName 'refs/remotes/origin/main') {
        return 'main'
    }

    if (Test-GitRef -GitDir $GitDir -RefName 'refs/remotes/origin/master') {
        return 'master'
    }

    if (Test-GitRef -GitDir $GitDir -RefName 'refs/heads/main') {
        return 'main'
    }

    if (Test-GitRef -GitDir $GitDir -RefName 'refs/heads/master') {
        return 'master'
    }

    $headRef = Get-GitString -C $GitDir symbolic-ref --quiet --short HEAD
    if ($headRef) {
        return $headRef
    }

    throw "Could not determine the default branch for '$GitDir'."
}

function Get-BareWorktreeProject {
    param([string]$StartPath = (Get-Location).Path)

    $resolvedStartPath = (Resolve-Path -LiteralPath $StartPath).Path
    $currentWorktree = Get-GitString -C $resolvedStartPath rev-parse --show-toplevel
    $currentBranch = $null
    $bareDir = $null

    if ($currentWorktree) {
        $gitCommonDir = Get-GitString -C $resolvedStartPath rev-parse --path-format=absolute --git-common-dir
        if (-not $gitCommonDir) {
            throw "Run this command inside a managed Git worktree, project root, or .bare directory."
        }

        $bareDir = $gitCommonDir.Trim()
        $currentBranch = Get-GitString -C $resolvedStartPath branch --show-current
    }
    elseif ((Split-Path -Leaf $resolvedStartPath) -eq '.bare') {
        $bareDir = $resolvedStartPath
    }
    else {
        $candidateBareDir = Join-Path $resolvedStartPath '.bare'
        if (Test-Path -LiteralPath $candidateBareDir -PathType Container) {
            $bareDir = (Resolve-Path -LiteralPath $candidateBareDir).Path
        }
        else {
            throw "Run this command inside a managed Git worktree, project root, or .bare directory."
        }
    }

    if ((Split-Path -Leaf $bareDir) -ne '.bare') {
        throw "This command expects the bare-repo layout: <project>/.bare plus sibling worktrees."
    }

    $projectRoot = Split-Path -Parent $bareDir

    [pscustomobject]@{
        BareDir         = $bareDir
        ProjectRoot     = $projectRoot
        ProjectName     = Split-Path -Leaf $projectRoot
        CurrentWorktree = $currentWorktree
        CurrentBranch   = $currentBranch
        DefaultBranch   = Get-GitDefaultBranch -GitDir $bareDir
    }
}

function gnew {
    param(
        [Parameter(Mandatory)][string]$Url,
        [string]$Name
    )

    if (-not $Name) {
        $Name = Get-RepoNameFromGitUrl -Url $Url
    }

    $projectRoot = Join-Path (Get-Location) $Name
    $bareDir = Join-Path $projectRoot '.bare'

    if (Test-Path $projectRoot) {
        throw "Target directory already exists: $projectRoot"
    }

    New-Item -ItemType Directory -Path $projectRoot | Out-Null

    try {
        Invoke-GitChecked "Failed to create bare clone." clone --bare $Url $bareDir
        Invoke-GitChecked "Failed to configure origin fetch refspec." -C $bareDir config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
        Invoke-GitChecked "Failed to enable fetch pruning." -C $bareDir config fetch.prune true
        Invoke-GitChecked "Failed to fetch origin." -C $bareDir fetch origin --prune

        & git -C $bareDir remote set-head origin --auto 2>$null | Out-Null

        $defaultBranch = Get-GitDefaultBranch -GitDir $bareDir
        $mainWorktree = Join-Path $projectRoot $defaultBranch

        Invoke-GitChecked "Failed to create the default worktree." -C $bareDir worktree add $mainWorktree $defaultBranch
        Set-Location $mainWorktree

        Write-Host "Ready: $Name/$defaultBranch"
    }
    catch {
        throw
    }
}

function gwt {
    param(
        [Parameter(Mandatory)][string]$Branch,
        [string]$From
    )

    $project = Get-BareWorktreeProject

    if (-not $From) {
        $From = $project.DefaultBranch
    }

    $worktreePath = Join-Path $project.ProjectRoot $Branch
    $worktreeParent = Split-Path -Parent $worktreePath

    if (Test-Path $worktreePath) {
        throw "Target worktree path already exists: $worktreePath"
    }

    if (Test-GitRef -GitDir $project.BareDir -RefName "refs/heads/$Branch") {
        throw "Local branch already exists: $Branch"
    }

    Invoke-GitChecked "Failed to fetch origin." -C $project.BareDir fetch origin --prune

    $startPoint = $null
    if (Test-GitRef -GitDir $project.BareDir -RefName "refs/heads/$From") {
        $startPoint = $From
    }
    elseif (Test-GitRef -GitDir $project.BareDir -RefName "refs/remotes/origin/$From") {
        $startPoint = "origin/$From"
    }
    else {
        throw "Base branch not found locally or on origin: $From"
    }

    if (-not (Test-Path $worktreeParent)) {
        New-Item -ItemType Directory -Path $worktreeParent -Force | Out-Null
    }

    Invoke-GitChecked "Failed to create worktree '$Branch'." -C $project.BareDir worktree add -b $Branch $worktreePath $startPoint
    Set-Location $worktreePath

    Write-Host "Ready: $($project.ProjectName)/$Branch (from $From)"
}

function gwl {
    $project = Get-BareWorktreeProject
    Invoke-GitChecked "Failed to list worktrees." -C $project.BareDir worktree list
}

function gwrm {
    param(
        [string]$Branch
    )

    $project = Get-BareWorktreeProject

    if (-not $Branch) {
        $Branch = $project.CurrentBranch
    }

    if (-not $Branch) {
        throw "Could not determine which branch to remove."
    }

    if ($Branch -eq $project.DefaultBranch) {
        throw "Refusing to remove the default worktree branch: $Branch"
    }

    $worktreePath = Join-Path $project.ProjectRoot $Branch
    if (-not (Test-Path $worktreePath)) {
        throw "Worktree path does not exist: $worktreePath"
    }

    $status = & git -C $worktreePath status --porcelain
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to inspect worktree status: $worktreePath"
    }

    if ($status) {
        throw "Worktree has uncommitted changes: $worktreePath"
    }

    if ($project.CurrentBranch -eq $Branch) {
        Set-Location (Join-Path $project.ProjectRoot $project.DefaultBranch)
    }

    Invoke-GitChecked "Failed to remove worktree '$Branch'." -C $project.BareDir worktree remove $worktreePath
    Invoke-GitChecked "Failed to delete branch '$Branch'." -C $project.BareDir branch --delete $Branch

    Write-Host "Removed: $($project.ProjectName)/$Branch"
}

function Get-GpruneWorktrees {
    param([Parameter(Mandatory)][string]$BareDir)

    $entries = @()
    $currentPath = $null
    $currentBranch = $null
    $currentIsBare = $false

    foreach ($line in (Get-GitLines -C $BareDir worktree list --porcelain)) {
        if ($line.StartsWith('worktree ')) {
            if ($currentPath) {
                $entries += [pscustomobject]@{
                    Path   = $currentPath
                    Branch = $currentBranch
                    IsBare = $currentIsBare
                }
            }

            $currentPath = $line.Substring(9)
            $currentBranch = $null
            $currentIsBare = $false
            continue
        }

        if ($line -eq 'bare') {
            $currentIsBare = $true
            continue
        }

        if ($line.StartsWith('branch refs/heads/')) {
            $currentBranch = $line.Substring(18)
        }
    }

    if ($currentPath) {
        $entries += [pscustomobject]@{
            Path   = $currentPath
            Branch = $currentBranch
            IsBare = $currentIsBare
        }
    }

    return $entries
}

function Show-GpruneReport {
    param(
        [Parameter(Mandatory)][pscustomobject]$Project,
        [Parameter(Mandatory)][string]$DefaultWorktree
    )

    Write-Host "Project root: $($Project.ProjectRoot)"
    Write-Host "Bare directory: $($Project.BareDir)"
    Write-Host "Default branch: $($Project.DefaultBranch)"
    Write-Host "Default worktree: $DefaultWorktree"
    Write-Host ''
    Write-Host 'Registered worktrees:'
    & git -C $Project.BareDir worktree list
    Write-Host ''
    Write-Host 'Top-level project root contents:'
    Get-ChildItem -LiteralPath $Project.ProjectRoot -Force | Sort-Object Name | ForEach-Object {
        Write-Host $_.FullName
    }
}

function Show-GpruneVerification {
    param(
        [Parameter(Mandatory)][pscustomobject]$Project,
        [Parameter(Mandatory)][string]$DefaultWorktree
    )

    Write-Host ''
    Write-Host 'Verification:'
    Write-Host 'Remaining registered worktrees:'
    Invoke-GitChecked "Failed to list remaining worktrees." -C $Project.BareDir worktree list
    Write-Host ''
    Write-Host 'Default branch status:'
    Invoke-GitChecked "Failed to inspect default branch status." -C $DefaultWorktree status --short --branch

    $localSha = Get-GitString -C $DefaultWorktree rev-parse HEAD
    $originSha = Get-GitString -C $Project.BareDir rev-parse "refs/remotes/origin/$($Project.DefaultBranch)"
    Write-Host ''
    Write-Host "Default HEAD SHA: $localSha"
    Write-Host "origin/$($Project.DefaultBranch) SHA: $originSha"
    Write-Host ''
    Write-Host 'Top-level project root contents:'
    Get-ChildItem -LiteralPath $Project.ProjectRoot -Force | Sort-Object Name | ForEach-Object {
        Write-Host $_.FullName
    }
}

function gprune {
    param(
        [switch]$Force
    )

    $project = Get-BareWorktreeProject

    Invoke-GitChecked "Failed to fetch remotes." -C $project.BareDir fetch --all --prune
    & git -C $project.BareDir remote set-head origin --auto 2>$null | Out-Null
    $project.DefaultBranch = Get-GitDefaultBranch -GitDir $project.BareDir

    if (-not (Test-GitRef -GitDir $project.BareDir -RefName "refs/remotes/origin/$($project.DefaultBranch)")) {
        throw "Remote default branch not found: origin/$($project.DefaultBranch)"
    }

    $defaultWorktree = Join-Path $project.ProjectRoot $project.DefaultBranch

    if (-not $Force) {
        Write-Host 'DRY RUN: gprune would destructively reset this managed repo to only the default branch worktree.'
        Write-Host ''
        Show-GpruneReport -Project $project -DefaultWorktree $defaultWorktree
        Write-Host ''
        Write-Host "Would reset and clean: $defaultWorktree"
        Write-Host "Would remove registered worktrees except: $defaultWorktree"
        Write-Host 'Would delete non-default local branches whose worktrees are removed, where possible.'
        Write-Host "Would remove stray top-level project entries except .bare and $($project.DefaultBranch)."
        throw 'Re-run with: gprune -Force'
    }

    if (Test-Path -LiteralPath $defaultWorktree -PathType Container) {
        Set-Location $defaultWorktree
    }
    else {
        Set-Location $project.ProjectRoot
    }

    $branchesToDelete = @()
    $defaultWorktreeComparable = ConvertTo-ComparablePath -Path $defaultWorktree
    foreach ($entry in (Get-GpruneWorktrees -BareDir $project.BareDir)) {
        if ($entry.IsBare) {
            continue
        }

        if ((ConvertTo-ComparablePath -Path $entry.Path) -eq $defaultWorktreeComparable) {
            continue
        }

        Invoke-GitChecked "Failed to remove worktree '$($entry.Path)'." -C $project.BareDir worktree remove --force $entry.Path

        if ($entry.Branch -and $entry.Branch -ne $project.DefaultBranch) {
            $branchesToDelete += $entry.Branch
        }
    }

    $defaultWorktreeUsable = $false
    if (Test-Path -LiteralPath $defaultWorktree -PathType Container) {
        $topLevel = Get-GitString -C $defaultWorktree rev-parse --show-toplevel
        $defaultWorktreeUsable = [bool]$topLevel
    }

    if (-not $defaultWorktreeUsable) {
        if (Test-Path -LiteralPath $defaultWorktree) {
            Remove-Item -LiteralPath $defaultWorktree -Recurse -Force
        }

        & git -C $project.BareDir worktree remove --force $defaultWorktree 2>$null | Out-Null
        Invoke-GitChecked "Failed to prune stale default worktree metadata." -C $project.BareDir worktree prune
        Invoke-GitChecked "Failed to create the default worktree." -C $project.BareDir worktree add -B $project.DefaultBranch $defaultWorktree "origin/$($project.DefaultBranch)"
    }

    Invoke-GitChecked "Failed to check out default branch." -C $defaultWorktree checkout -B $project.DefaultBranch "origin/$($project.DefaultBranch)"
    Invoke-GitChecked "Failed to reset default worktree." -C $defaultWorktree reset --hard "origin/$($project.DefaultBranch)"
    Invoke-GitChecked "Failed to clean default worktree." -C $defaultWorktree clean -fdx
    & git -C $defaultWorktree branch --set-upstream-to "origin/$($project.DefaultBranch)" $project.DefaultBranch 2>$null | Out-Null

    foreach ($branch in ($branchesToDelete | Select-Object -Unique)) {
        if (Test-GitRef -GitDir $project.BareDir -RefName "refs/heads/$branch") {
            & git -C $project.BareDir branch -D $branch
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Failed to delete local branch: $branch"
            }
        }
    }

    Invoke-GitChecked "Failed to prune worktree metadata." -C $project.BareDir worktree prune

    $bareDirComparable = ConvertTo-ComparablePath -Path $project.BareDir
    foreach ($item in (Get-ChildItem -LiteralPath $project.ProjectRoot -Force)) {
        $itemComparable = ConvertTo-ComparablePath -Path $item.FullName
        if ($itemComparable -eq $bareDirComparable -or $itemComparable -eq $defaultWorktreeComparable) {
            continue
        }

        Remove-Item -LiteralPath $item.FullName -Recurse -Force
    }

    Show-GpruneVerification -Project $project -DefaultWorktree $defaultWorktree
}
