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

function Test-GitRef {
    param(
        [Parameter(Mandatory)][string]$GitDir,
        [Parameter(Mandatory)][string]$RefName
    )

    & git -C $GitDir show-ref --verify --quiet $RefName 2>$null
    return $LASTEXITCODE -eq 0
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

    $headRef = Get-GitString -C $GitDir symbolic-ref --quiet --short HEAD
    if ($headRef) {
        return $headRef
    }

    throw "Could not determine the default branch for '$GitDir'."
}

function Get-BareWorktreeProject {
    param([string]$StartPath = (Get-Location).Path)

    $gitCommonDir = Get-GitString -C $StartPath rev-parse --path-format=absolute --git-common-dir
    if (-not $gitCommonDir) {
        throw "Run this command inside a Git worktree."
    }

    $bareDir = $gitCommonDir.Trim()
    if ((Split-Path -Leaf $bareDir) -ne '.bare') {
        throw "This command expects the bare-repo layout: <project>/.bare plus sibling worktrees."
    }

    $projectRoot = Split-Path -Parent $bareDir
    $currentWorktree = Get-GitString -C $StartPath rev-parse --show-toplevel
    $currentBranch = Get-GitString -C $StartPath branch --show-current

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
