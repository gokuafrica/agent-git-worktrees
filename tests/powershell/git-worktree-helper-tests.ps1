param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:Helper = Join-Path $script:RepoRoot 'scripts\powershell\git-worktree.ps1'

function Assert-PathExists {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Expected path to exist: $Path"
    }
}

function Assert-PathMissing {
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path -LiteralPath $Path) {
        throw "Expected path to be absent: $Path"
    }
}

function Assert-OnlyDefaultLayout {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$DefaultBranch
    )

    Assert-PathExists (Join-Path $ProjectRoot '.bare')
    Assert-PathExists (Join-Path $ProjectRoot $DefaultBranch)

    $contents = @(Get-ChildItem -LiteralPath $ProjectRoot -Force | Sort-Object Name | ForEach-Object Name)
    $expected = @('.bare', $DefaultBranch)
    if (($contents -join '|') -ne ($expected -join '|')) {
        throw "Unexpected project contents: $($contents -join ',')"
    }

    $status = & git -C (Join-Path $ProjectRoot $DefaultBranch) status --porcelain
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to inspect default worktree status."
    }
    if ($status) {
        throw "Default worktree is not clean: $status"
    }
}

function New-TestRemote {
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$DefaultBranch = 'main'
    )

    $origin = Join-Path $Root 'origin.git'
    $seed = Join-Path $Root 'seed'

    & git init --bare $origin | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to init bare origin." }

    & git clone $origin $seed | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to clone seed." }

    & git -C $seed config user.email 'codex@example.test'
    & git -C $seed config user.name 'Codex Test'
    Set-Content -LiteralPath (Join-Path $seed 'README.md') -Value 'initial'
    & git -C $seed add README.md
    & git -C $seed commit -m 'initial' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to commit seed." }

    & git -C $seed branch -M $DefaultBranch
    & git -C $seed push -u origin $DefaultBranch | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to push default branch." }

    & git -C $origin symbolic-ref HEAD "refs/heads/$DefaultBranch"
    if ($LASTEXITCODE -ne 0) { throw "Failed to set remote HEAD." }

    return $origin
}

function Invoke-TestCase {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Body
    )

    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("gwt-ps-test-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $root | Out-Null

    Write-Host "TEST: $Name"
    Push-Location $root
    try {
        . $script:Helper
        & $Body $root
    }
    finally {
        Set-Location $script:RepoRoot
        Pop-Location
        if (Test-Path -LiteralPath $root) {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }
}

Invoke-TestCase 'gnew, gwt -From, gwl, and clean gwrm' {
    param($Root)

    $origin = New-TestRemote -Root $Root
    gnew $origin managed
    $managed = Join-Path $Root 'managed'

    gwt feat/base -From main
    Set-Location $managed
    $list = & git -C (Join-Path $managed '.bare') worktree list
    if (-not ($list -match 'feat/base')) {
        throw 'Expected feat/base worktree to be registered.'
    }

    gwrm feat/base
    Assert-PathMissing (Join-Path $managed 'feat\base')
    if (& git -C (Join-Path $managed '.bare') show-ref --verify --quiet refs/heads/feat/base) {
        throw 'Expected feat/base branch to be deleted.'
    }
}

Invoke-TestCase 'gprune dry-run exits non-zero and removes nothing' {
    param($Root)

    $origin = New-TestRemote -Root $Root
    gnew $origin managed
    $managed = Join-Path $Root 'managed'
    gwt feat/dry -From main
    Set-Content -LiteralPath (Join-Path $managed 'stray.txt') -Value 'stray'
    Set-Location $managed

    $failed = $false
    try {
        gprune
    }
    catch {
        $failed = $true
    }

    if (-not $failed) {
        throw 'Expected gprune dry-run to fail.'
    }
    Assert-PathExists (Join-Path $managed 'feat\dry')
    Assert-PathExists (Join-Path $managed 'stray.txt')
}

Invoke-TestCase 'gprune -Force from project root' {
    param($Root)

    $origin = New-TestRemote -Root $Root
    gnew $origin managed
    $managed = Join-Path $Root 'managed'
    gwt feat/root -From main
    Set-Content -LiteralPath (Join-Path $managed 'feat\root\dirty.txt') -Value 'dirty'
    Set-Content -LiteralPath (Join-Path $managed 'stray.txt') -Value 'stray'
    $nodeModulesPath = Join-Path $managed 'main\node_modules\pkg\subpkg'
    New-Item -ItemType Directory -Path $nodeModulesPath -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $nodeModulesPath 'index.js') -Value 'dependency'
    Set-Location $managed
    gprune -Force
    Assert-OnlyDefaultLayout -ProjectRoot $managed -DefaultBranch main
    Assert-PathMissing (Join-Path $managed 'main\node_modules')
}

Invoke-TestCase 'gprune -Force from .bare' {
    param($Root)

    $origin = New-TestRemote -Root $Root
    gnew $origin managed
    $managed = Join-Path $Root 'managed'
    gwt feat/bare -From main
    Set-Location (Join-Path $managed '.bare')
    gprune -Force
    Assert-OnlyDefaultLayout -ProjectRoot $managed -DefaultBranch main
}

Invoke-TestCase 'gprune -Force from default worktree' {
    param($Root)

    $origin = New-TestRemote -Root $Root
    gnew $origin managed
    $managed = Join-Path $Root 'managed'
    gwt feat/default -From main
    Set-Location (Join-Path $managed 'main')
    gprune -Force
    Assert-OnlyDefaultLayout -ProjectRoot $managed -DefaultBranch main
}

Invoke-TestCase 'gprune -Force from feature worktree' {
    param($Root)

    $origin = New-TestRemote -Root $Root
    gnew $origin managed
    $managed = Join-Path $Root 'managed'
    gwt feat/current -From main
    Set-Location (Join-Path $managed 'feat\current')
    gprune -Force
    Assert-OnlyDefaultLayout -ProjectRoot $managed -DefaultBranch main
}

Invoke-TestCase 'gprune recreates missing default worktree' {
    param($Root)

    $origin = New-TestRemote -Root $Root
    gnew $origin managed
    $managed = Join-Path $Root 'managed'
    Set-Location $managed
    Remove-Item -LiteralPath (Join-Path $managed 'main') -Recurse -Force
    gprune -Force
    Assert-OnlyDefaultLayout -ProjectRoot $managed -DefaultBranch main
}

Invoke-TestCase 'gprune removes external registered worktree and branch' {
    param($Root)

    $origin = New-TestRemote -Root $Root
    gnew $origin managed
    $managed = Join-Path $Root 'managed'
    $external = Join-Path $Root 'external-worktree'
    & git -C (Join-Path $managed '.bare') worktree add -b feat/external $external origin/main | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to create external worktree.' }

    Set-Location $managed
    gprune -Force

    Assert-OnlyDefaultLayout -ProjectRoot $managed -DefaultBranch main
    Assert-PathMissing $external
    if (& git -C (Join-Path $managed '.bare') show-ref --verify --quiet refs/heads/feat/external) {
        throw 'Expected feat/external branch to be deleted.'
    }
}

Invoke-TestCase 'default branch fallback supports master' {
    param($Root)

    $origin = New-TestRemote -Root $Root -DefaultBranch master
    gnew $origin managed
    $managed = Join-Path $Root 'managed'
    Assert-PathExists (Join-Path $managed 'master')
    gwt feat/master-test -From master
    Set-Location $managed
    gprune -Force
    Assert-OnlyDefaultLayout -ProjectRoot $managed -DefaultBranch master
}

Write-Host 'All PowerShell git-worktree helper tests passed.'
