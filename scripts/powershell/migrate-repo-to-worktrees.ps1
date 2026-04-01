param(
    [Parameter(Mandatory)][string]$BasePath,
    [Parameter(Mandatory)][string[]]$RepoNames,
    [string]$BackupSuffix
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

function Get-DefaultBranch {
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

function Test-GitRef {
    param(
        [Parameter(Mandatory)][string]$GitDir,
        [Parameter(Mandatory)][string]$RefName
    )

    & git -C $GitDir show-ref --verify --quiet $RefName 2>$null
    return $LASTEXITCODE -eq 0
}

function Ensure-ParentDirectory {
    param([Parameter(Mandatory)][string]$Path)

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

function Copy-RepoPath {
    param(
        [Parameter(Mandatory)][string]$FromRoot,
        [Parameter(Mandatory)][string]$ToRoot,
        [Parameter(Mandatory)][string]$RelativePath
    )

    $fromPath = Join-Path $FromRoot $RelativePath
    $toPath = Join-Path $ToRoot $RelativePath

    if (-not (Test-Path $fromPath)) {
        return
    }

    Ensure-ParentDirectory -Path $toPath

    $item = Get-Item -LiteralPath $fromPath
    if ($item.PSIsContainer) {
        Copy-Item -LiteralPath $fromPath -Destination $toPath -Recurse -Force
    }
    else {
        Copy-Item -LiteralPath $fromPath -Destination $toPath -Force
    }
}

function Remove-RepoPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$RelativePath
    )

    $targetPath = Join-Path $Root $RelativePath
    if (Test-Path $targetPath) {
        Remove-Item -LiteralPath $targetPath -Recurse -Force
    }
}

function Apply-WorkingTreeChanges {
    param(
        [Parameter(Mandatory)][string]$BackupPath,
        [Parameter(Mandatory)][string]$WorktreePath,
        [Parameter(Mandatory)][string[]]$StatusLines
    )

    foreach ($line in $StatusLines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $xy = $line.Substring(0, 2)
        $payload = $line.Substring(3)

        if ($xy -eq '??') {
            Copy-RepoPath -FromRoot $BackupPath -ToRoot $WorktreePath -RelativePath $payload
            continue
        }

        if ($payload.Contains(' -> ')) {
            $parts = $payload -split ' -> ', 2
            $oldPath = $parts[0]
            $newPath = $parts[1]
            Remove-RepoPath -Root $WorktreePath -RelativePath $oldPath
            Copy-RepoPath -FromRoot $BackupPath -ToRoot $WorktreePath -RelativePath $newPath
            continue
        }

        if ($xy[0] -eq 'D' -or $xy[1] -eq 'D') {
            Remove-RepoPath -Root $WorktreePath -RelativePath $payload
            continue
        }

        Copy-RepoPath -FromRoot $BackupPath -ToRoot $WorktreePath -RelativePath $payload
    }
}

function Backup-DirectoryContents {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$BackupPath
    )

    New-Item -ItemType Directory -Path $BackupPath | Out-Null
    & robocopy $SourcePath $BackupPath /E /COPY:DAT /DCOPY:T /R:1 /W:1 /XJ /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -gt 7) {
        throw "Failed to create backup copy at '$BackupPath'."
    }
}

function Clear-DirectoryContents {
    param([Parameter(Mandatory)][string]$Path)

    $emptyDir = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-empty-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $emptyDir | Out-Null

    try {
        & robocopy $emptyDir $Path /MIR /R:1 /W:1 /XJ /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -gt 7) {
            throw "Failed to clear directory contents at '$Path'."
        }
    }
    finally {
        if (Test-Path $emptyDir) {
            Remove-Item -LiteralPath $emptyDir -Recurse -Force
        }
    }
}

if (-not $BackupSuffix) {
    $BackupSuffix = 'pre-worktree-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
}

foreach ($repoName in $RepoNames) {
    $repoPath = Join-Path $BasePath $repoName
    $gitPath = Join-Path $repoPath '.git'

    if (-not (Test-Path $repoPath)) {
        throw "Repository path does not exist: $repoPath"
    }

    if (-not (Test-Path $gitPath)) {
        throw "Not a standard Git repository: $repoPath"
    }

    $remoteUrl = Get-GitString -C $repoPath remote get-url origin
    if (-not $remoteUrl) {
        throw "Repository has no origin remote: $repoPath"
    }

    Invoke-GitChecked "Failed to fetch origin for '$repoName'." -C $repoPath fetch origin --prune

    $currentBranch = Get-GitString -C $repoPath branch --show-current
    $statusLines = @(Get-GitLines -C $repoPath status --porcelain=v1)

    $backupPath = Join-Path $BasePath "$repoName.$BackupSuffix"
    if (Test-Path $backupPath) {
        throw "Backup path already exists: $backupPath"
    }

    Backup-DirectoryContents -SourcePath $repoPath -BackupPath $backupPath
    Clear-DirectoryContents -Path $repoPath

    try {
        $barePath = Join-Path $repoPath '.bare'
        Invoke-GitChecked "Failed to create bare clone for '$repoName'." clone --bare $backupPath $barePath
        Invoke-GitChecked "Failed to repoint origin for '$repoName'." -C $barePath remote set-url origin $remoteUrl
        Invoke-GitChecked "Failed to configure fetch refs for '$repoName'." -C $barePath config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
        Invoke-GitChecked "Failed to enable fetch pruning for '$repoName'." -C $barePath config fetch.prune true
        Invoke-GitChecked "Failed to fetch origin for '$repoName'." -C $barePath fetch origin --prune

        & git -C $barePath remote set-head origin --auto 2>$null | Out-Null

        $defaultBranch = Get-DefaultBranch -GitDir $barePath
        if ($currentBranch -and $currentBranch -eq $defaultBranch) {
            $defaultWorktree = Join-Path $repoPath $currentBranch
            Invoke-GitChecked "Failed to create default worktree for '$repoName'." -C $barePath worktree add $defaultWorktree $currentBranch
        }
        else {
            $defaultWorktree = Join-Path $repoPath $defaultBranch
            Invoke-GitChecked "Failed to create default worktree for '$repoName'." -C $barePath worktree add $defaultWorktree $defaultBranch
        }

        if (Test-GitRef -GitDir $barePath -RefName "refs/remotes/origin/$defaultBranch") {
            Invoke-GitChecked "Failed to set upstream tracking for '$repoName'." -C $defaultWorktree branch --set-upstream-to "origin/$defaultBranch" $defaultBranch
        }

        if (@($statusLines).Count -gt 0) {
            Apply-WorkingTreeChanges -BackupPath $backupPath -WorktreePath $defaultWorktree -StatusLines $statusLines
        }

        Write-Host "Migrated $repoName -> $defaultWorktree"
        if (@($statusLines).Count -gt 0) {
            Write-Host "Preserved uncommitted paths from backup: $($statusLines.Count)"
        }
        Write-Host "Backup kept at $backupPath"
    }
    catch {
        throw
    }
}
