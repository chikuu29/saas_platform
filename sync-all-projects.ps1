param(
    [switch]$IncludeRoot
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path

$projects = @(
    @{
        Name = "identity-backend"
        Path = Join-Path $root "apps\identity_server\backend"
    },
    @{
        Name = "identity-web"
        Path = Join-Path $root "apps\identity_server\web"
    },
    @{
        Name = "workspace-backend"
        Path = Join-Path $root "apps\work_space\backend"
    },
    @{
        Name = "workspace-web"
        Path = Join-Path $root "apps\work_space\web"
    }
)

if ($IncludeRoot) {
    $projects = @(
        @{
            Name = "root"
            Path = $root
        }
    ) + $projects
}

function Test-GitRepoClean {
    param(
        [string]$RepoPath
    )

    $status = git -C $RepoPath status --porcelain 2>$null
    return [string]::IsNullOrWhiteSpace(($status | Out-String))
}

function Get-CurrentBranch {
    param(
        [string]$RepoPath
    )

    return (git -C $RepoPath rev-parse --abbrev-ref HEAD 2>$null).Trim()
}

Write-Host "Syncing projects..."
Write-Host ""

foreach ($project in $projects) {
    if (-not (Test-Path $project.Path)) {
        Write-Warning "Skipping $($project.Name): path not found: $($project.Path)"
        continue
    }

    if (-not (Test-Path (Join-Path $project.Path ".git"))) {
        Write-Warning "Skipping $($project.Name): not a Git repo"
        continue
    }

    Write-Host "[$($project.Name)]"

    $branch = Get-CurrentBranch -RepoPath $project.Path
    if (-not $branch) {
        Write-Warning "Could not determine the current branch. Skipping."
        Write-Host ""
        continue
    }

    if (-not (Test-GitRepoClean -RepoPath $project.Path)) {
        Write-Warning "Working tree has local changes on branch '$branch'. Skipping pull to keep your work safe."
        Write-Host ""
        continue
    }

    try {
        git -C $project.Path fetch --all --prune
        git -C $project.Path pull --ff-only
        Write-Host "Synced branch '$branch'."
    }
    catch {
        Write-Warning "Sync failed for $($project.Name): $($_.Exception.Message)"
    }

    Write-Host ""
}

Write-Host "Sync finished."
